import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private final class BundleToken {}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
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

    /// Закладки на матчи НХЛ (D34: хоккей убран) не должны находить футбольный матч с тем же числом.
    @Test func foreignPrefixIsNil() {
        #expect(FootballRepository.footballSourceID(MatchID(rawValue: "hockey:560643")) == nil)
        #expect(FootballRepository.footballSourceID(MatchID(rawValue: "football:560643")) == 560643)
    }
}
