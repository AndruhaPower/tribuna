import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import { mapMatches, mapStandings } from "./mapping.ts";

const fixture = (name: string) =>
  JSON.parse(Deno.readTextFileSync(new URL(`../../../tribuna_api_report/raw/${name}.body`, import.meta.url)));

const unique = (ids: number[]) => new Set(ids).size === ids.length;

Deno.test("mapMatches: матчи недели", () => {
  const { competitions, teams, matches } = mapMatches(fixture("fd_matches_week"));
  assertEquals(matches.length, 12);
  assertEquals(matches[0].id, 555081);
  assertEquals(matches[0].status, "TIMED");
  assertEquals(matches[0].matchday, 35);
  assertEquals(matches[0].home_score, null);
  assert(unique(competitions.map((c) => c.id)));
  assert(competitions.some((c) => c.id === 2013 && c.code === "BSA"));
  assert(unique(teams.map((t) => t.id)));
  assert(teams.some((t) => t.id === 4241 && t.tla === "COR" && t.short_name === "Coritiba"));
});

Deno.test("mapMatches: команда без tla и shortName, счёт, неопределённая команда", () => {
  const base = fixture("fd_matches_week").matches[0];
  const json = {
    matches: [{
      ...base,
      homeTeam: { id: 1, name: "Some FC", crest: null },
      awayTeam: { id: null, name: null },
      score: { winner: "HOME_TEAM", fullTime: { home: 2, away: 1 } },
    }],
  };
  const { teams, matches } = mapMatches(json);
  assertEquals(teams, [{ id: 1, name: "Some FC", short_name: "Some FC", tla: null, crest_url: null }]);
  assertEquals([matches[0].home_score, matches[0].away_score], [2, 1]);
  assertEquals(matches[0].away_team_id, null);
});

Deno.test("mapStandings: PL", () => {
  const { competitionId, rows } = mapStandings(fixture("fd_standings_PL"));
  assertEquals(competitionId, 2021);
  assertEquals(rows.length, 20);
  assertEquals(rows[0].position, 1);
  assertEquals(rows[0].team_id, 57);
  assertEquals(rows[0].points, 27);
  assertEquals(rows[0].played, 10);
});

Deno.test("mapStandings: CL", () => {
  const { competitionId, rows } = mapStandings(fixture("fd_standings_CL"));
  assertEquals(competitionId, 2001);
  assert(rows.length > 0 && rows.every((r) => r.stage === "LEAGUE_STAGE"));
});

Deno.test("невалидный ответ даёт понятную ошибку", () => {
  assertThrows(() => mapMatches({}), Error, "matches");
  assertThrows(() => mapStandings({ standings: [] }), Error, "competition");
});
