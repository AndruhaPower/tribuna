// План запуска sync-football: чистая логика, без I/O.

const MIN = 60_000;
export const MATCHES_INTERVAL_MS = 15 * MIN; // как часто тянуть матчи вне live
export const SOON_WINDOW_MS = 15 * MIN; // «скоро» = начало в ближайшие 15 минут
export const STANDINGS_MAX_AGE_MS = 6 * 60 * MIN; // таблица считается устаревшей
export const MAX_STANDINGS_PER_RUN = 2;

export type CompetitionState = {
  code: string;
  standingsUpdatedAt: Date | null;
  lastFinishedAt: Date | null;
};

export function isLiveOrSoon(matches: { status: string; utc_date: string }[], now: Date): boolean {
  const t = now.getTime();
  return matches.some((m) => {
    if (m.status === "IN_PLAY" || m.status === "PAUSED") return true;
    if (m.status !== "TIMED" && m.status !== "SCHEDULED") return false;
    const start = new Date(m.utc_date).getTime();
    return start >= t && start <= t + SOON_WINDOW_MS;
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
    (c.standingsUpdatedAt === null || c.lastFinishedAt > c.standingsUpdatedAt);
  const stale = (c: CompetitionState) =>
    c.standingsUpdatedAt === null ||
    now.getTime() - c.standingsUpdatedAt.getTime() > STANDINGS_MAX_AGE_MS;

  const first = comps.filter(finished).sort(byUpdated);
  const second = comps.filter((c) => !finished(c) && stale(c)).sort(byUpdated);
  const standingsCodes = [...first, ...second].slice(0, MAX_STANDINGS_PER_RUN).map((c) => c.code);
  return { fetchMatches, standingsCodes };
}
