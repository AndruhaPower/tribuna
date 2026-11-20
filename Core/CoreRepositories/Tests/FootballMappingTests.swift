import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private func row(
    status: String = "TIMED",
    matchday: Int? = nil,
    competitionNameRu: String? = "АПЛ",
    home: FootballRow.TeamRow? = FootballRow.TeamRow(name: "Arsenal FC", shortName: "Arsenal", tla: "ARS", nameRu: "Арсенал", shortNameRu: nil)
) -> FootballRow {
    FootballRow(
        id: 555081,
        utcDate: Date(timeIntervalSince1970: 1_800_000_000),
        status: status,
        matchday: matchday,
        homeScore: 2,
        awayScore: 1,
        competition: .init(code: "PL", name: "Premier League", nameRu: competitionNameRu, enabled: true),
        home: home,
        away: FootballRow.TeamRow(name: "Liverpool FC", shortName: "Liverpool", tla: "LIV", nameRu: nil, shortNameRu: nil),
        homeTeamID: 57,
        awayTeamID: nil
    )
}

struct FootballMappingTests {
    @Test func mapsBasics() {
        let match = FootballMapping.match(from: row())
        #expect(match.id.rawValue == "football:555081")
        #expect(match.sport == .football)
        #expect(match.competition == Competition(code: "PL", name: "АПЛ"))
        #expect(match.kickoff == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(match.homeScore == 2 && match.awayScore == 1)
        #expect(match.round == nil)
        #expect(match.homeTeamID == "57" && match.awayTeamID == nil)
    }

    @Test func russianNameWins() {
        #expect(FootballMapping.match(from: row()).home == Team(name: "Арсенал", abbreviation: "ARS"))
    }

    @Test func fallsBackToShortName() {
        #expect(FootballMapping.match(from: row()).away?.name == "Liverpool")
    }

    @Test func shortNameRuBeforeShortName() {
        let team = FootballRow.TeamRow(name: "Arsenal FC", shortName: "Arsenal", tla: "ARS", nameRu: nil, shortNameRu: "Арсенал")
        #expect(FootballMapping.match(from: row(home: team)).home?.name == "Арсенал")
    }

    @Test func missingTeam() {
        #expect(FootballMapping.match(from: row(home: nil)).home == nil)
    }

    @Test func round() {
        #expect(FootballMapping.match(from: row(matchday: 12)).round == "12 тур")
    }

    @Test func competitionFallsBackToEnglish() {
        #expect(FootballMapping.match(from: row(competitionNameRu: nil)).competition.name == "Premier League")
    }

    @Test(arguments: [
        ("SCHEDULED", MatchStatus.scheduled), ("TIMED", .scheduled),
        ("IN_PLAY", .live), ("EXTRA_TIME", .live), ("PENALTY_SHOOTOUT", .live),
        ("PAUSED", .paused),
        ("FINISHED", .finished), ("AWARDED", .finished),
        ("POSTPONED", .postponed), ("SUSPENDED", .postponed),
        ("CANCELLED", .cancelled),
    ])
    func status(code: String, expected: MatchStatus) {
        #expect(FootballMapping.match(from: row(status: code)).status == expected)
    }

    @Test func decodesPostgRESTRow() throws {
        // Формат ответа PostgREST с вложенными таблицами (снят с tribuna_db).
        let json = Data("""
        [{"id":565859,"utc_date":"2026-11-20T19:30:00+00:00","status":"TIMED","matchday":10,"home_score":null,"away_score":null,
        "competition":{"code":"BL1","name":"Bundesliga","enabled":true,"name_ru":null},
        "home":{"tla":"FCB","name":"FC Bayern München","name_ru":null,"short_name":"Bayern","short_name_ru":null},
        "away":null}]
        """.utf8)
        let rows = try FootballRepository.decoder.decode([FootballRow].self, from: json)
        let match = FootballMapping.match(from: try #require(rows.first))
        #expect(match.home?.name == "Bayern")
        #expect(match.away == nil)
        #expect(match.kickoff == ISO8601DateFormatter().date(from: "2026-11-20T19:30:00Z"))
    }
}

struct LogoMappingTests {
    @Test func mapsCrestAndEmblem() {
        let home = FootballRow.TeamRow(name: "A", shortName: nil, tla: "ARS", nameRu: nil, shortNameRu: nil, crestURL: "https://crests.football-data.org/57.png")
        let row = FootballRow(
            id: 1, utcDate: Date(), status: "TIMED", matchday: nil, homeScore: nil, awayScore: nil,
            competition: .init(code: "PL", name: "PL", nameRu: nil, enabled: true, emblemURL: "https://crests.football-data.org/PL.png"),
            home: home, away: nil, homeTeamID: 57, awayTeamID: nil
        )
        let match = FootballMapping.match(from: row)
        #expect(match.home?.logoURL == URL(string: "https://crests.football-data.org/57.png"))
        #expect(match.competition.emblemURL == URL(string: "https://crests.football-data.org/PL.png"))
    }

    @Test func missingUrlsAreNil() {
        let match = FootballMapping.match(from: FootballRow(
            id: 1, utcDate: Date(), status: "TIMED", matchday: nil, homeScore: nil, awayScore: nil,
            competition: .init(code: "PL", name: "PL", nameRu: nil, enabled: true),
            home: .init(name: "A", shortName: nil, tla: nil, nameRu: nil, shortNameRu: nil), away: nil, homeTeamID: nil, awayTeamID: nil
        ))
        #expect(match.home?.logoURL == nil && match.competition.emblemURL == nil)
    }

    @Test func decodesCrestFromJSON() throws {
        let json = #"{"name":"A","tla":"ARS","crest_url":"https://x/1.png"}"#
        let row = try JSONDecoder().decode(FootballRow.TeamRow.self, from: Data(json.utf8))
        #expect(row.crestURL == "https://x/1.png")
    }
}

struct LogoSelectTests {
    @Test func selectsCrestAndEmblem() {
        #expect(FootballRepository.columns.contains("emblem_url"))
        #expect(FootballRepository.columns.components(separatedBy: "crest_url").count == 3)
    }
}
