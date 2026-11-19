import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private final class BundleToken {}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

private struct FakeRepository: MatchesRepository {
    let matches: [Match]
    func matches(in interval: DateInterval) async throws -> [Match] { matches }
    func match(id: MatchID) async throws -> Match? { matches.first { $0.id == id } }
}

private func stub(_ id: String) -> Match {
    Match(
        id: MatchID(rawValue: id), sport: .football, competition: Competition(code: "X", name: "X"),
        kickoff: Date(timeIntervalSince1970: 0), status: .scheduled, home: nil, away: nil,
        homeScore: nil, awayScore: nil, round: nil, homeTeamID: nil, awayTeamID: nil
    )
}

struct MatchByIDTests {
    @Test func footballFixtureHasTeamIDs() throws {
        // Ответ PostgREST на select `FootballRepository.columns` с фильтром по id (снят с tribuna_db).
        let rows = try FootballRepository.decoder.decode([FootballRow].self, from: fixture("football_match"))
        let match = FootballMapping.match(from: try #require(rows.first))
        #expect(match.id.rawValue == "football:560643")
        #expect(match.competition == Competition(code: "PL", name: "АПЛ"))
        #expect(match.home?.name == "Man City")
        #expect(match.homeTeamID == "65")
        #expect(match.awayTeamID == "63")
        #expect(match.round == "11 тур")
    }

    @Test func footballColumnsSelectTeamIDs() {
        #expect(FootballRepository.columns.contains("home_team_id,away_team_id"))
    }

    @Test func nhlLandingFixture() throws {
        // gamecenter/2026020344/landing: у команд commonName вместо name.
        let match = try NHLClient.parseLanding(fixture("nhl_landing"))
        #expect(match.id.rawValue == "hockey:2026020344")
        #expect(match.status == .finished)
        #expect(match.home == Team(name: "Red Wings", abbreviation: "DET"))
        #expect(match.away == Team(name: "Bruins", abbreviation: "BOS"))
        #expect(match.homeScore == 1 && match.awayScore == 4)
        #expect(match.homeTeamID == "17" && match.awayTeamID == "6")
        #expect(match.kickoff == ISO8601DateFormatter().date(from: "2026-11-19T00:30:00Z"))
    }

    @Test func nhlScoreHasTeamIDs() throws {
        let matches = try NHLClient.parse(fixture("nhl_score_now"))
        #expect(matches.allSatisfy { $0.homeTeamID != nil && $0.awayTeamID != nil })
    }

    @Test func nhlMatchByIDRequestsLanding() async throws {
        let data = try fixture("nhl_landing")
        let client = NHLClient { url in
            #expect(url.absoluteString == "https://api-web.nhle.com/v1/gamecenter/2026020344/landing")
            return data
        }
        let match = try await client.match(id: MatchID(rawValue: "hockey:2026020344"))
        #expect(match?.id.rawValue == "hockey:2026020344")
    }

    @Test func nhlUnknownGameIsNil() async throws {
        let client = NHLClient { _ in throw NHLClient.NotFound() }
        #expect(try await client.match(id: MatchID(rawValue: "hockey:1")) == nil)
    }

    @Test func nhlOtherErrorsThrow() async {
        let client = NHLClient { _ in throw URLError(.timedOut) }
        await #expect(throws: URLError.self) { try await client.match(id: MatchID(rawValue: "hockey:1")) }
    }

    @Test func combinedRoutesByPrefix() async throws {
        let repo = CombinedMatchesRepository(
            football: FakeRepository(matches: [stub("football:1")]),
            hockey: FakeRepository(matches: [stub("hockey:1")])
        )
        #expect(try await repo.match(id: MatchID(rawValue: "football:1"))?.id.rawValue == "football:1")
        #expect(try await repo.match(id: MatchID(rawValue: "hockey:1"))?.id.rawValue == "hockey:1")
        #expect(try await repo.match(id: MatchID(rawValue: "football:2")) == nil)
        #expect(try await repo.match(id: MatchID(rawValue: "tennis:1")) == nil)
    }
}
