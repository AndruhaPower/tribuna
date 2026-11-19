// Edge Function sync-football: pg_cron раз в минуту, тянет football-data.org и пишет в таблицы.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { mapMatches, mapStandings } from "./mapping.ts";
import { isLiveOrSoon, planRun } from "./plan.ts";

const API = "https://api.football-data.org/v4";
const DAY = 86_400_000;

export type Deps = {
  env: (k: string) => string | undefined;
  fetch: typeof fetch;
  db: SupabaseClient;
  now?: () => Date; // для тестов
};

const ymd = (d: Date) => d.toISOString().slice(0, 10);
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// Сравниваем хэши, а не строки: время сравнения не выдаёт префикс секрета.
async function sameSecret(a: string, b: string): Promise<boolean> {
  const h = async (s: string) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))).join();
  return (await h(a)) === (await h(b));
}

// Ответ PostgREST: при ошибке бросаем, данные отдаём как есть.
async function q<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(`db: ${error.message}`);
  return data;
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const secret = deps.env("SYNC_SECRET");
  const given = req.headers.get("x-sync-secret");
  if (!secret || given === null || !(await sameSecret(given, secret))) {
    return reply({ error: "unauthorized" }, 401);
  }
  const key = deps.env("FOOTBALL_DATA_KEY");
  if (!key) return reply({ error: "FOOTBALL_DATA_KEY не задан" }, 500);

  const { db } = deps;
  const now = deps.now?.() ?? new Date();
  let fetchedMatches = false;
  const standings: string[] = [];
  let error: string | null = null;

  // Любая ошибка выходит из try ниже: после 429/сети запросов в этом запуске больше нет.
  const get = async (path: string): Promise<unknown> => {
    let res: Response;
    try {
      res = await deps.fetch(`${API}${path}`, { headers: { "X-Auth-Token": key } });
    } catch (e) {
      throw new Error(`football-data: сеть: ${e instanceof Error ? e.message : String(e)}`);
    }
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`football-data: HTTP ${res.status} на ${path.split("?")[0]}`);
    }
    return res.json();
  };

  try {
    const comps = await q(
      db.from("competitions").select("id, code, standings_updated_at").eq("enabled", true),
    ) as { id: number; code: string; standings_updated_at: string | null }[];
    const matchesState = await q(
      db.from("sync_state").select("value").eq("key", "matches").maybeSingle(),
    ) as { value: { fetchedAt?: string } } | null;

    const dateFrom = ymd(new Date(now.getTime() - DAY));
    const dateTo = ymd(new Date(now.getTime() + 7 * DAY));
    const windowMatches = await q(
      db.from("matches").select("status, utc_date")
        .gte("utc_date", `${dateFrom}T00:00:00Z`).lte("utc_date", `${dateTo}T23:59:59Z`),
    ) as { status: string; utc_date: string }[];

    const competitions = await Promise.all(comps.map(async (c) => {
      const last = await q(
        db.from("matches").select("source_updated_at")
          .eq("competition_id", c.id).eq("status", "FINISHED")
          .order("source_updated_at", { ascending: false, nullsFirst: false }).limit(1),
      ) as { source_updated_at: string | null }[];
      const at = last[0]?.source_updated_at;
      return {
        code: c.code,
        standingsUpdatedAt: c.standings_updated_at ? new Date(c.standings_updated_at) : null,
        lastFinishedAt: at ? new Date(at) : null,
      };
    }));

    const fetchedAt = matchesState?.value?.fetchedAt;
    const plan = planRun(now, {
      enabledCodes: comps.map((c) => c.code),
      lastMatchesFetchAt: fetchedAt ? new Date(fetchedAt) : null,
      liveOrSoon: isLiveOrSoon(windowMatches, now),
      competitions,
    });

    if (plan.fetchMatches) {
      const codes = comps.map((c) => c.code).join(",");
      const m = mapMatches(await get(`/matches?competitions=${codes}&dateFrom=${dateFrom}&dateTo=${dateTo}`));
      // competitions: только синк-колонки, enabled/name_ru/standings_updated_at не трогаем
      if (m.competitions.length) await q(db.from("competitions").upsert(m.competitions, { onConflict: "id" }));
      if (m.teams.length) await q(db.from("teams").upsert(m.teams, { onConflict: "id" }));
      if (m.matches.length) await q(db.from("matches").upsert(m.matches, { onConflict: "id" }));
      await q(db.from("sync_state").upsert({ key: "matches", value: { fetchedAt: now.toISOString() } }));
      fetchedMatches = true;
    }

    const skipped: string[] = [];
    for (const code of plan.standingsCodes) {
      const s = mapStandings(await get(`/competitions/${code}/standings`));
      // пустой массив стёр бы таблицу турнира
      if (s.rows.length === 0) {
        skipped.push(code);
        continue;
      }
      // команды из таблицы могут отсутствовать в окне матчей: иначе упадёт FK standings.team_id
      await q(db.from("teams").upsert(s.teams, { onConflict: "id" }));
      await q(db.rpc("replace_standings", { p_competition_id: s.competitionId, p_rows: s.rows }));
      standings.push(code);
    }
    if (skipped.length) error = `football-data: пустая таблица у ${skipped.join(", ")}`;
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }

  try {
    await q(
      db.from("sync_state").upsert({
        key: "last_run",
        value: { at: now.toISOString(), fetchedMatches, standings, error },
      }),
    );
  } catch (e) {
    error ??= e instanceof Error ? e.message : String(e);
  }

  if (error) console.error(`sync-football: ${error}`);
  return reply(error ? { fetchedMatches, standings, error } : { fetchedMatches, standings });
}

if (import.meta.main) {
  Deno.serve((req) =>
    handle(req, {
      env: (k) => Deno.env.get(k),
      fetch,
      db: createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
        auth: { persistSession: false },
      }),
    })
  );
}
