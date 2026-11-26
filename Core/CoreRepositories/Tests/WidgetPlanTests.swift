#if FEATURE_WIDGET
import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

struct WidgetPlanTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func match(_ id: String, at offset: TimeInterval, _ status: MatchStatus = .scheduled) -> Match {
        Match(id: MatchID(rawValue: "football:\(id)"), sport: .football, competition: Competition(code: "PL", name: "АПЛ"),
              kickoff: now.addingTimeInterval(offset), status: status, home: nil, away: nil, homeScore: nil, awayScore: nil,
              round: nil, homeTeamID: nil, awayTeamID: nil)
    }

    @Test func bookmarksFirstThenUpcomingBeforeFinishedThenKickoff() {
        let finished = match("1", at: -7200, .finished), late = match("2", at: 3600), early = match("3", at: 600)
        let bookmarkedLate = match("4", at: 7200), extra = match("5", at: 9000)
        let picked = WidgetPlan.pick([finished, late, early, bookmarkedLate, extra], bookmarks: [bookmarkedLate.id], limit: 3)
        #expect(picked.map(\.id) == [bookmarkedLate.id, early.id, late.id])
    }

    @Test func refreshOftenDuringLive() {
        #expect(WidgetPlan.nextRefresh([match("1", at: -600, .live)], now: now) == now.addingTimeInterval(300))
        #expect(WidgetPlan.nextRefresh([match("1", at: -600, .paused)], now: now) == now.addingTimeInterval(300))
    }

    @Test func refreshAtNextKickoffButAtMostHalfHour() {
        #expect(WidgetPlan.nextRefresh([match("1", at: 600), match("2", at: 300)], now: now) == now.addingTimeInterval(300))
        #expect(WidgetPlan.nextRefresh([match("1", at: 7200)], now: now) == now.addingTimeInterval(1800))
        #expect(WidgetPlan.nextRefresh([match("1", at: -7200, .finished)], now: now) == now.addingTimeInterval(1800))
        #expect(WidgetPlan.nextRefresh([], now: now) == now.addingTimeInterval(1800))
    }
}
#endif
