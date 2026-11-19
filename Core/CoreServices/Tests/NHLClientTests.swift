import CoreDomain
import Foundation
import Testing
@testable import CoreServices

private final class BundleToken {}

/// Сутки date (yyyy-MM-dd) по Москве.
func moscowDay(_ date: String) -> DateInterval {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
    formatter.dateFormat = "yyyy-MM-dd"
    let start = formatter.date(from: date)!
    return DateInterval(start: start, duration: 24 * 3600)
}

struct NHLClientTests {
    @Test func parsesFixture() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "nhl_score_now", withExtension: "json"))
        let matches = try NHLClient.parse(Data(contentsOf: url))
        let first = try #require(matches.first)
        #expect(first.sport == .hockey)
        #expect(first.competition == Competition(code: "NHL", name: "НХЛ"))
        #expect(first.id.rawValue.hasPrefix("hockey:"))
        #expect(first.home?.abbreviation != nil)
        #expect(first.round == nil)
    }

    @Test(arguments: [
        ("FUT", MatchStatus.scheduled), ("PRE", .scheduled),
        ("LIVE", .live), ("CRIT", .live),
        ("FINAL", .finished), ("OFF", .finished),
        ("PPD", .postponed), ("CNCL", .cancelled),
    ])
    func status(code: String, expected: MatchStatus) {
        #expect(NHLClient.status(code) == expected)
    }

    @Test func datesCoverMoscowDay() {
        #expect(NHLClient.datesToQuery(for: moscowDay("2026-11-19")) == ["2026-11-18", "2026-11-19"])
    }

    @Test func nightGameBelongsToNextMoscowDay() async throws {
        let body = Data("""
        {"games":[{"id":2026020400,"startTimeUTC":"2026-11-20T00:00:00Z","gameState":"FUT",
        "homeTeam":{"name":{"default":"Bruins"},"abbrev":"BOS"},
        "awayTeam":{"name":{"default":"Kings"},"abbrev":"LAK"}}]}
        """.utf8)
        let client = NHLClient { url in
            url.lastPathComponent == "2026-11-19" ? body : Data(#"{"games":[]}"#.utf8)
        }

        #expect(try await client.matches(in: moscowDay("2026-11-19")).isEmpty)
        let night = try await client.matches(in: moscowDay("2026-11-20"))
        #expect(night.map(\.id.rawValue) == ["hockey:2026020400"])
        #expect(night.first?.home == Team(name: "Bruins", abbreviation: "BOS"))
    }
}
