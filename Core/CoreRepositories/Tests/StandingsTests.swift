import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private final class BundleToken {}

private func rows(_ json: String) throws -> [StandingDTO] {
    try FootballRepository.decoder.decode([StandingDTO].self, from: Data(json.utf8))
}

private func row(_ stage: String, _ group: String?, _ position: Int, team id: Int) -> String {
    """
    {"stage":"\(stage)","group_name":\(group.map { "\"\($0)\"" } ?? "null"),"position":\(position),"team_id":\(id),"played":3,"points":\(10 - position),
    "team":{"tla":"T\(id)","name":"Team \(id) FC","name_ru":null,"short_name":"Team \(id)","short_name_ru":null}}
    """
}

struct StandingsTests {
    @Test func parsesPLFixture() throws {
        // Ответ PostgREST для АПЛ (снят с tribuna_db): standings + teams, по position.
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "football_standings_pl", withExtension: "json"))
        let table = FootballMapping.standings(from: try FootballRepository.decoder.decode([StandingDTO].self, from: Data(contentsOf: url)))
        #expect(table.count == 20)
        #expect(table.map(\.position) == Array(1...20))
        let first = try #require(table.first)
        #expect(first.team == Team(name: "Арсенал", abbreviation: "ARS"))
        #expect(first.teamID == "57")
        #expect(first.played == 10 && first.points == 27)
    }

    @Test func picksLargestTableAndSorts() throws {
        // Две группы: основная — где больше строк; сервер мог отдать их вперемешку.
        let json = "[" + [
            row("GROUP_STAGE", "Group A", 2, team: 2),
            row("REGULAR_SEASON", "Matchday", 3, team: 13),
            row("GROUP_STAGE", "Group A", 1, team: 1),
            row("REGULAR_SEASON", "Matchday", 1, team: 11),
            row("REGULAR_SEASON", "Matchday", 2, team: 12),
        ].joined(separator: ",") + "]"
        let table = FootballMapping.standings(from: try rows(json))
        #expect(table.map(\.teamID) == ["11", "12", "13"])
        #expect(table.first?.team.name == "Team 11")
    }

    @Test func nullGroupCountsAsTable() throws {
        let json = "[" + [row("REGULAR_SEASON", nil, 2, team: 2), row("REGULAR_SEASON", nil, 1, team: 1)].joined(separator: ",") + "]"
        #expect(FootballMapping.standings(from: try rows(json)).map(\.position) == [1, 2])
    }

    @Test func emptyIsEmpty() {
        #expect(FootballMapping.standings(from: []).isEmpty)
    }
}
