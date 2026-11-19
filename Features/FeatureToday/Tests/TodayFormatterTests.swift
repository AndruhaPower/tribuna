import CoreDomain
import Foundation
import Testing
@testable import FeatureToday

struct TodayFormatterTests {
    @Test(arguments: [
        (1, "1 матч"), (2, "2 матча"), (4, "4 матча"), (5, "5 матчей"), (11, "11 матчей"),
        (12, "12 матчей"), (14, "14 матчей"), (20, "20 матчей"), (21, "21 матч"), (22, "22 матча"), (25, "25 матчей"),
    ])
    func matchCount(count: Int, expected: String) {
        #expect(TodayFormatter.matchCount(count) == expected)
    }

    @Test func leadingByStatus() {
        let cal = calendar()
        #expect(TodayFormatter.leading(match("a"), calendar: cal) == "22:00")
        #expect(TodayFormatter.leading(match("a", status: .finished, score: (2, 1)), calendar: cal) == "2 : 1")
        #expect(TodayFormatter.leading(match("a", status: .live, score: (2, 1)), calendar: cal) == "LIVE 2 : 1")
        #expect(TodayFormatter.leading(match("a", status: .paused, score: (0, 0)), calendar: cal) == "LIVE 0 : 0")
        #expect(TodayFormatter.leading(match("a", status: .postponed), calendar: cal) == "Перенесён")
        #expect(TodayFormatter.leading(match("a", status: .cancelled), calendar: cal) == "Отменён")
    }

    @Test func titleFallsBackToDashForUnknownTeam() {
        #expect(TodayFormatter.title(match("a")) == "Ливерпуль — Арсенал")
        #expect(TodayFormatter.title(match("a", home: nil)) == "— — Арсенал")
    }
}
