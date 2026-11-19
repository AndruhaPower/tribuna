import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { handle } from "./index.ts";

const SECRET = "test-sync-secret";
const KEY = "test-fd-key";
const NOW = new Date("2026-11-19T20:00:00Z");

// Логи функции собираем, а не печатаем: вывод тестов чистый, а ключ проверяем ниже.
const logs: string[] = [];
console.error = (...args: unknown[]) => logs.push(args.join(" "));

type Call = { table: string; ops: [string, unknown[]][] };

// Фейк Supabase-клиента: записывает цепочки вызовов, отвечает по таблице.
function fakeDb(respond: (c: Call) => unknown = () => []) {
  const calls: Call[] = [];
  const rpcs: { fn: string; args: unknown }[] = [];
  const db = {
    from(table: string) {
      const call: Call = { table, ops: [] };
      calls.push(call);
      const builder: Record<string, unknown> = {
        then: (ok: (v: unknown) => unknown, fail: (e: unknown) => unknown) =>
          Promise.resolve({ data: respond(call), error: null }).then(ok, fail),
      };
      for (const op of ["select", "eq", "in", "gte", "lte", "order", "limit", "maybeSingle", "upsert"]) {
        builder[op] = (...args: unknown[]) => (call.ops.push([op, args]), builder);
      }
      return builder;
    },
    rpc(fn: string, args: unknown) {
      rpcs.push({ fn, args });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { db: db as unknown as SupabaseClient, calls, rpcs };
}

const upserts = (calls: Call[], table: string) =>
  calls.filter((c) => c.table === table && c.ops.some(([op]) => op === "upsert"))
    .map((c) => c.ops.find(([op]) => op === "upsert")![1]);

function fakeFetch(handler: (url: string) => Response | Promise<Response>) {
  const requests: { url: string; headers: Headers }[] = [];
  const fn = ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    requests.push({ url, headers: new Headers(init?.headers) });
    return Promise.resolve(handler(url));
  }) as typeof fetch;
  return { fetch: fn, requests };
}

const env = (overrides: Record<string, string | undefined> = {}) => (k: string) =>
  ({ SYNC_SECRET: SECRET, FOOTBALL_DATA_KEY: KEY, ...overrides } as Record<string, string | undefined>)[k];

const req = (secret?: string) =>
  new Request("http://localhost/sync-football", {
    method: "POST",
    headers: secret === undefined ? {} : { "x-sync-secret": secret },
  });

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

// Включён только PL, таблица PL свежая, матчи давно не тянули.
const baseRespond = (c: Call): unknown => {
  if (c.table === "competitions") return [{ id: 2021, code: "PL", standings_updated_at: null }];
  if (c.table === "sync_state") return null;
  return [];
};

const team = (id: number) => ({ id, name: `Team ${id}`, shortName: `T${id}`, tla: `T${id}`, crest: null });
const matchesJson = {
  matches: [{
    id: 1,
    competition: { id: 2021, code: "PL", name: "Premier League", emblem: "e.png" },
    utcDate: "2026-11-19T19:00:00Z",
    status: "FINISHED",
    matchday: 12,
    stage: "REGULAR_SEASON",
    group: null,
    homeTeam: team(10),
    awayTeam: team(11),
    score: { winner: "HOME_TEAM", fullTime: { home: 2, away: 1 } },
    lastUpdated: "2026-11-19T19:55:00Z",
  }],
};
const standingsJson = (table: unknown[]) => ({
  competition: { id: 2021, code: "PL" },
  standings: [{ stage: "REGULAR_SEASON", type: "TOTAL", group: null, table }],
});

Deno.test("без заголовка x-sync-secret → 401, fetch не вызывался", async () => {
  const { db, calls } = fakeDb();
  const f = fakeFetch(() => json({}));
  const res = await handle(req(), { env: env(), fetch: f.fetch, db, now: () => NOW });
  assertEquals(res.status, 401);
  assertEquals(f.requests.length, 0);
  assertEquals(calls.length, 0);
});

Deno.test("неверный секрет → 401", async () => {
  const { db } = fakeDb();
  const f = fakeFetch(() => json({}));
  const res = await handle(req("wrong"), { env: env(), fetch: f.fetch, db, now: () => NOW });
  assertEquals(res.status, 401);
  assertEquals(f.requests.length, 0);
});

Deno.test("SYNC_SECRET не задан → 401 даже с пустым заголовком", async () => {
  const { db } = fakeDb();
  const f = fakeFetch(() => json({}));
  const res = await handle(req(""), { env: env({ SYNC_SECRET: undefined }), fetch: f.fetch, db, now: () => NOW });
  assertEquals(res.status, 401);
});

Deno.test("нет FOOTBALL_DATA_KEY → 500 без значения секрета", async () => {
  const { db } = fakeDb();
  const f = fakeFetch(() => json({}));
  const res = await handle(req(SECRET), {
    env: env({ FOOTBALL_DATA_KEY: undefined }),
    fetch: f.fetch,
    db,
    now: () => NOW,
  });
  assertEquals(res.status, 500);
  const text = await res.text();
  assert(!text.includes(SECRET));
  assertEquals(f.requests.length, 0);
});

Deno.test("429 на матчи → 200, error с 429, таблицы не трогаем, last_run записан", async () => {
  const { db, calls, rpcs } = fakeDb(baseRespond);
  const f = fakeFetch(() => new Response("slow down", { status: 429 }));
  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.fetchedMatches, false);
  assertEquals(body.standings, []);
  assertStringIncludes(body.error, "429");
  assert(!JSON.stringify(body).includes(KEY));
  assertEquals(f.requests.length, 1, "после 429 запросы прекращаются");
  assertEquals(rpcs.length, 0);
  const state = upserts(calls, "sync_state").map((a) => a[0] as { key: string; value: Record<string, unknown> });
  assertEquals(state.map((s) => s.key), ["last_run"]);
  assertStringIncludes(String(state[0].value.error), "429");
});

Deno.test("сетевая ошибка → 200 с error", async () => {
  const { db, rpcs } = fakeDb(baseRespond);
  const f = fakeFetch(() => Promise.reject(new TypeError("connection refused")));
  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertStringIncludes(body.error, "connection refused");
  assertEquals(f.requests.length, 1);
  assertEquals(rpcs.length, 0);
});

Deno.test("успешный запуск: окно дат, заголовок, синк-колонки, команды до replace_standings", async () => {
  const { db, calls, rpcs } = fakeDb(baseRespond);
  const order: string[] = [];
  const origRpc = db.rpc.bind(db);
  (db as unknown as { rpc: unknown }).rpc = (fn: string, args: unknown) => (order.push("rpc"), origRpc(fn, args));
  const f = fakeFetch((url) => {
    if (url.includes("/matches")) return json(matchesJson);
    order.push(`teams-upserts-before-rpc:${upserts(calls, "teams").length}`);
    return json(standingsJson([{ position: 1, team: team(12), playedGames: 1, points: 3 }]));
  });

  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { fetchedMatches: true, standings: ["PL"] });

  assertEquals(f.requests.map((r) => r.url), [
    "https://api.football-data.org/v4/matches?competitions=PL&dateFrom=2026-11-18&dateTo=2026-11-26",
    "https://api.football-data.org/v4/competitions/PL/standings",
  ]);
  for (const r of f.requests) assertEquals(r.headers.get("X-Auth-Token"), KEY);

  assertEquals(upserts(calls, "competitions"), [[
    [{ id: 2021, code: "PL", name: "Premier League", emblem_url: "e.png" }],
    { onConflict: "id" },
  ]]);
  const teamUpserts = upserts(calls, "teams");
  assertEquals(teamUpserts.length, 2);
  assertEquals(Object.keys((teamUpserts[0][0] as object[])[0]).sort(), [
    "crest_url",
    "id",
    "name",
    "short_name",
    "tla",
    "updated_at",
  ]);
  assertEquals((teamUpserts[0][0] as { updated_at: string }[])[0].updated_at, NOW.toISOString());
  assertEquals((upserts(calls, "matches")[0][0] as { synced_at: string }[])[0].synced_at, NOW.toISOString());
  const windowQuery = calls.find((c) => c.table === "matches" && c.ops.some(([op]) => op === "gte"))!;
  assert(windowQuery.ops.some(([op, a]) => op === "in" && a[0] === "competition_id" && (a[1] as number[])[0] === 2021));
  assertEquals((teamUpserts[1][0] as { id: number }[]).map((t) => t.id), [12]);
  assertEquals(upserts(calls, "matches").length, 1);

  // команды из таблицы upsert-нуты до replace_standings (R4)
  assertEquals(order, ["teams-upserts-before-rpc:1", "rpc"]);
  assertEquals(calls.filter((c) => c.table === "teams").length, 2);
  assertEquals(rpcs.length, 1);
  assertEquals(rpcs[0].fn, "replace_standings");
  assertEquals((rpcs[0].args as { p_competition_id: number }).p_competition_id, 2021);

  const state = upserts(calls, "sync_state").map((a) => a[0] as { key: string; value: Record<string, unknown> });
  assertEquals(state.map((s) => s.key), ["matches", "last_run"]);
  assertEquals(state[0].value, { fetchedAt: NOW.toISOString() });
  assertEquals(state[1].value, { at: NOW.toISOString(), fetchedMatches: true, standings: ["PL"], error: null });
});

Deno.test("пустая таблица → replace_standings не вызывается, error записан", async () => {
  const { db, rpcs } = fakeDb(baseRespond);
  const f = fakeFetch((url) => url.includes("/matches") ? json({ matches: [] }) : json(standingsJson([])));
  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  const body = await res.json();
  assertEquals(rpcs.length, 0);
  assertEquals(body.standings, []);
  assertStringIncludes(body.error, "PL");
});

const twoComps = (c: Call): unknown => {
  if (c.table === "competitions") {
    return [{ id: 2021, code: "PL", standings_updated_at: null }, { id: 2019, code: "SA", standings_updated_at: null }];
  }
  return c.table === "sync_state" ? null : [];
};

Deno.test("стендинги: 404 у первой не мешает второй", async () => {
  const { db, rpcs } = fakeDb(twoComps);
  const f = fakeFetch((url) =>
    url.includes("/matches")
      ? json({ matches: [] })
      : url.includes("/PL/") ? new Response("nf", { status: 404 }) : json(standingsJson([{ position: 1, team: team(12) }]))
  );
  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  const body = await res.json();
  assertEquals(f.requests.length, 3);
  assertEquals(rpcs.length, 1);
  assertEquals(body.standings, ["SA"]);
  assertStringIncludes(body.error, "404");
});

Deno.test("стендинги: 429 у первой прекращает запросы", async () => {
  const { db, rpcs } = fakeDb(twoComps);
  const f = fakeFetch((url) =>
    url.includes("/matches") ? json({ matches: [] }) : new Response("slow", { status: 429 })
  );
  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  const body = await res.json();
  assertEquals(f.requests.length, 2, "матчи + одна таблица, вторая не запрошена");
  assertEquals(rpcs.length, 0);
  assertStringIncludes(body.error, "429");
});

Deno.test("plan: lastFinishedAt из FINISHED-матчей, свежие матчи не тянем", async () => {
  const { db, calls } = fakeDb((c) => {
    if (c.table === "competitions") {
      return [{ id: 2021, code: "PL", standings_updated_at: "2026-11-19T19:00:00Z" }];
    }
    if (c.table === "sync_state") return { value: { fetchedAt: "2026-11-19T19:55:00Z" } };
    if (c.ops.some(([op, a]) => op === "eq" && a[0] === "status")) {
      return [{ source_updated_at: "2026-11-19T19:50:00Z" }];
    }
    return [];
  });
  const f = fakeFetch(() => json(standingsJson([{ position: 1, team: team(12) }])));
  const res = await handle(req(SECRET), { env: env(), fetch: f.fetch, db, now: () => NOW });
  assertEquals(await res.json(), { fetchedMatches: false, standings: ["PL"] });
  assertEquals(f.requests.length, 1);
  const finishedQuery = calls.find((c) => c.ops.some(([op, a]) => op === "eq" && a[0] === "status"))!;
  assert(finishedQuery.ops.some(([op, a]) => op === "eq" && a[0] === "competition_id" && a[1] === 2021));
});

Deno.test("ключи не попадают в логи", () => {
  assert(logs.length > 0);
  for (const l of logs) assert(!l.includes(KEY) && !l.includes(SECRET), l);
});
