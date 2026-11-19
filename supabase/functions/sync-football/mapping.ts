import type { CompetitionRow, MatchRow, StandingRow, TeamRow } from "./types.ts";

// deno-lint-ignore no-explicit-any
type Json = any; // граница доверия: ответ внешнего API, проверяем только нужное

function arrayField(json: Json, key: string): Json[] {
  const arr = json?.[key];
  if (!Array.isArray(arr)) throw new Error(`football-data: в ответе нет массива ${key}`);
  return arr;
}

function requireId(value: Json, what: string): number {
  if (typeof value !== "number") throw new Error(`football-data: нет id у ${what}`);
  return value;
}

function mapTeam(t: Json): TeamRow {
  return {
    id: t.id,
    name: t.name,
    short_name: t.shortName ?? t.name,
    tla: t.tla ?? null,
    crest_url: t.crest ?? null,
  };
}

export function mapMatches(json: unknown): {
  competitions: CompetitionRow[];
  teams: TeamRow[];
  matches: MatchRow[];
} {
  const competitions = new Map<number, CompetitionRow>();
  const teams = new Map<number, TeamRow>();
  const matches: MatchRow[] = [];

  for (const m of arrayField(json, "matches")) {
    const competitionId = requireId(m.competition?.id, "competition");
    const id = requireId(m.id, "match");
    competitions.set(competitionId, {
      id: competitionId,
      code: m.competition.code,
      name: m.competition.name,
      emblem_url: m.competition.emblem ?? null,
    });
    // В плей-офф команда может быть ещё не определена (id = null).
    for (const t of [m.homeTeam, m.awayTeam]) {
      if (typeof t?.id === "number") teams.set(t.id, mapTeam(t));
    }
    matches.push({
      id,
      competition_id: competitionId,
      utc_date: m.utcDate,
      status: m.status,
      matchday: m.matchday ?? null,
      stage: m.stage ?? null,
      group_name: m.group ?? null,
      home_team_id: m.homeTeam?.id ?? null,
      away_team_id: m.awayTeam?.id ?? null,
      home_score: m.score?.fullTime?.home ?? null,
      away_score: m.score?.fullTime?.away ?? null,
      winner: m.score?.winner ?? null,
      source_updated_at: m.lastUpdated ?? null,
    });
  }

  return { competitions: [...competitions.values()], teams: [...teams.values()], matches };
}

export function mapStandings(json: unknown): { competitionId: number; rows: StandingRow[] } {
  const competitionId = requireId((json as Json)?.competition?.id, "competition");
  const rows: StandingRow[] = [];

  for (const s of arrayField(json, "standings")) {
    if (s.type !== "TOTAL") continue;
    for (const r of s.table ?? []) {
      rows.push({
        stage: s.stage,
        group_name: s.group ?? "",
        position: r.position,
        team_id: requireId(r.team?.id, "team в таблице"),
        played: r.playedGames ?? null,
        won: r.won ?? null,
        draw: r.draw ?? null,
        lost: r.lost ?? null,
        goals_for: r.goalsFor ?? null,
        goals_against: r.goalsAgainst ?? null,
        goal_difference: r.goalDifference ?? null,
        points: r.points ?? null,
        form: r.form ?? null,
      });
    }
  }

  return { competitionId, rows };
}
