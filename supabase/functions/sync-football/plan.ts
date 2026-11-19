// План запуска sync-football: чистая логика, без I/O.

const MIN = 60_000;
export const MATCHES_INTERVAL_MS = 15 * MIN; // как часто тянуть матчи вне live
export const SOON_WINDOW_MS = 15 * MIN; // «скоро» = начало в ближайшие 15 минут
export const STARTED_WINDOW_MS = 3 * 60 * MIN; // TIMED/SCHEDULED старше 3 ч считаем не live (статус не обновился)
export const STANDINGS_SETTLE_MS = 10 * MIN; // football-data пересчитывает таблицу не мгновенно
export const STANDINGS_MAX_AGE_MS = 6 * 60 * MIN; // таблица считается устаревшей
export const MAX_STANDINGS_PER_RUN = 2;

export type CompetitionState = {
  code: string;
  standingsUpdatedAt: Date | null;
  lastFinishedAt: Date | null;
};

const LIVE = new Set(["IN_PLAY", "PAUSED", "EXTRA_TIME", "PENALTY_SHOOTOUT"]);

// TIMED/SCHEDULED, но уже начался: football-data меняет статус с задержкой, окно [-3 ч; +15 мин].
export function isLiveOrSoon(matches: { status: string; utc_date: string }[], now: Date): boolean {
  const t = now.getTime();
  return matches.some((m) => {
    if (LIVE.has(m.status)) return true;
    if (m.status !== "TIMED" && m.status !== "SCHEDULED") return false;
    const start = new Date(m.utc_date).getTime();
    return start >= t - STARTED_WINDOW_MS && start <= t + SOON_WINDOW_MS;
  });
}

// null = «никогда не обновлялась», сортируется первой
const byUpdated = (a: CompetitionState, b: CompetitionState) =>
  (a.standingsUpdatedAt?.getTime() ?? -Infinity) - (b.standingsUpdatedAt?.getTime() ?? -Infinity);

export function planRun(
  now: Date,
  s: {
    enabledCodes: string[];
    lastMatchesFetchAt: Date | null;
    liveOrSoon: boolean;
    competitions: CompetitionState[];
  },
): { fetchMatches: boolean; standingsCodes: string[] } {
  if (s.enabledCodes.length === 0) return { fetchMatches: false, standingsCodes: [] };

  const fetchMatches = s.liveOrSoon || s.lastMatchesFetchAt === null ||
    now.getTime() - s.lastMatchesFetchAt.getTime() >= MATCHES_INTERVAL_MS;

  const comps = s.competitions.filter((c) => s.enabledCodes.includes(c.code));
  const finished = (c: CompetitionState) =>
    c.lastFinishedAt !== null &&
    (c.standingsUpdatedAt === null ||
      c.standingsUpdatedAt.getTime() < c.lastFinishedAt.getTime() + STANDINGS_SETTLE_MS);
  const stale = (c: CompetitionState) =>
    c.standingsUpdatedAt === null ||
    now.getTime() - c.standingsUpdatedAt.getTime() > STANDINGS_MAX_AGE_MS;

  const first = comps.filter(finished).sort(byUpdated);
  const second = comps.filter((c) => !finished(c) && stale(c)).sort(byUpdated);
  const standingsCodes = [...first, ...second].slice(0, MAX_STANDINGS_PER_RUN).map((c) => c.code);
  return { fetchMatches, standingsCodes };
}
