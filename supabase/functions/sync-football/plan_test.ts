import { assertEquals } from "jsr:@std/assert";
import { CompetitionState, isLiveOrSoon, planRun } from "./plan.ts";

const now = new Date("2026-11-19T20:00:00Z");
const at = (hhmm: string) => new Date(`2026-11-19T${hhmm}:00Z`);
const ago = (min: number) => new Date(now.getTime() - min * 60_000);
const m = (status: string, hhmm: string) => ({ status, utc_date: `2026-11-19T${hhmm}:00Z` });

Deno.test("isLiveOrSoon: идущие матчи", () => {
  assertEquals(isLiveOrSoon([m("IN_PLAY", "19:30")], now), true);
  assertEquals(isLiveOrSoon([m("PAUSED", "19:30")], now), true);
});

Deno.test("isLiveOrSoon: скоро начало", () => {
  assertEquals(isLiveOrSoon([m("TIMED", "20:10")], now), true);
  assertEquals(isLiveOrSoon([m("SCHEDULED", "20:10")], now), true);
  assertEquals(isLiveOrSoon([m("TIMED", "20:20")], now), false);
});

Deno.test("isLiveOrSoon: TIMED/SCHEDULED уже начался (окно -3 ч)", () => {
  assertEquals(isLiveOrSoon([m("TIMED", "19:55")], now), true);
  assertEquals(isLiveOrSoon([m("SCHEDULED", "17:00")], now), true);
  assertEquals(isLiveOrSoon([m("TIMED", "16:59")], now), false);
});

Deno.test("isLiveOrSoon: граница +15 минут включительно", () => {
  assertEquals(isLiveOrSoon([m("TIMED", "20:15")], now), true);
  assertEquals(isLiveOrSoon([m("TIMED", "20:16")], now), false);
});

Deno.test("isLiveOrSoon: доп. время и пенальти", () => {
  assertEquals(isLiveOrSoon([m("EXTRA_TIME", "18:00")], now), true);
  assertEquals(isLiveOrSoon([m("PENALTY_SHOOTOUT", "18:00")], now), true);
});

Deno.test("isLiveOrSoon: прочие статусы", () => {
  for (const s of ["POSTPONED", "CANCELLED", "SUSPENDED"]) {
    assertEquals(isLiveOrSoon([m(s, "20:05")], now), false);
  }
  assertEquals(isLiveOrSoon([m("FINISHED", "19:00")], now), false);
});

const base = { enabledCodes: ["PL"], lastMatchesFetchAt: ago(1), liveOrSoon: false, competitions: [] };

Deno.test("planRun: fetchMatches", () => {
  const f = (o: object) => planRun(now, { ...base, ...o }).fetchMatches;
  assertEquals(f({ lastMatchesFetchAt: null }), true);
  assertEquals(f({ liveOrSoon: true, lastMatchesFetchAt: ago(0.5) }), true);
  assertEquals(f({ lastMatchesFetchAt: ago(14) }), false);
  assertEquals(f({ lastMatchesFetchAt: ago(15) }), true);
  assertEquals(f({ enabledCodes: [], lastMatchesFetchAt: null, liveOrSoon: true }), false);
});

const c = (code: string, upd: Date | null, fin: Date | null = null): CompetitionState => ({
  code,
  standingsUpdatedAt: upd,
  lastFinishedAt: fin,
});
const codes = (enabledCodes: string[], competitions: CompetitionState[]) =>
  planRun(now, { ...base, enabledCodes, competitions }).standingsCodes;

Deno.test("planRun: таблицы после окончания матча идут первыми", () => {
  const res = codes(["PL", "SA"], [c("SA", ago(8 * 60)), c("PL", at("19:00"), at("19:50"))]);
  assertEquals(res, ["PL", "SA"]);
});

Deno.test("planRun: таблица, снятая сразу после FINISHED, обновляется ещё раз", () => {
  const f = (upd: Date) => codes(["PL"], [c("PL", upd, at("19:50"))]);
  assertEquals(f(at("19:55")), ["PL"]);
  assertEquals(f(at("20:01")), []);
});

Deno.test("planRun: не больше двух, null первым", () => {
  assertEquals(codes(["A", "B", "C"], [c("A", null), c("B", null), c("C", null)]).length, 2);
  assertEquals(codes(["A", "B"], [c("A", ago(7 * 60)), c("B", null)]), ["B", "A"]);
});

Deno.test("planRun: свежие таблицы не трогаем", () => {
  assertEquals(codes(["PL"], [c("PL", ago(60), at("18:00"))]), []);
});

Deno.test("planRun: устаревшая таблица", () => {
  assertEquals(codes(["PL", "SA"], [c("PL", ago(7 * 60)), c("SA", ago(60))]), ["PL"]);
});

Deno.test("planRun: только включённые коды", () => {
  assertEquals(codes(["PL"], [c("SA", null), c("PL", ago(60))]), []);
  assertEquals(codes([], [c("PL", null)]), []);
});
