import CoreDomain
import Foundation
import PostgREST

/// Строка `matches` с вложенными турниром и командами (PostgREST embed).
struct FootballRow: Decodable, Sendable {
    struct CompetitionRow: Decodable, Sendable {
        let code: String
        let name: String
        let nameRu: String?
        let enabled: Bool

        enum CodingKeys: String, CodingKey {
            case code, name, enabled
            case nameRu = "name_ru"
        }
    }

    struct TeamRow: Decodable, Sendable {
        let name: String
        let shortName: String?
        let tla: String?
        let nameRu: String?
        let shortNameRu: String?

        enum CodingKeys: String, CodingKey {
            case name, tla
            case shortName = "short_name"
            case nameRu = "name_ru"
            case shortNameRu = "short_name_ru"
        }
    }

    let id: Int
    let utcDate: Date
    let status: String
    let matchday: Int?
    let homeScore: Int?
    let awayScore: Int?
    let competition: CompetitionRow
    let home: TeamRow?
    let away: TeamRow?

    enum CodingKeys: String, CodingKey {
        case id, status, matchday, competition, home, away
        case utcDate = "utc_date"
        case homeScore = "home_score"
        case awayScore = "away_score"
    }
}

enum FootballMapping {
    static func match(from row: FootballRow) -> Match {
        Match(
            id: MatchID(sport: .football, sourceID: String(row.id)),
            sport: .football,
            competition: Competition(code: row.competition.code, name: row.competition.nameRu ?? row.competition.name),
            kickoff: row.utcDate,
            status: status(row.status),
            home: row.home.map(team),
            away: row.away.map(team),
            homeScore: row.homeScore,
            awayScore: row.awayScore,
            round: row.matchday.map { "\($0) тур" }
        )
    }

    static func status(_ code: String) -> MatchStatus {
        switch code {
        case "IN_PLAY", "EXTRA_TIME", "PENALTY_SHOOTOUT": .live
        case "PAUSED": .paused
        case "FINISHED", "AWARDED": .finished
        case "POSTPONED", "SUSPENDED": .postponed
        case "CANCELLED": .cancelled
        default: .scheduled // SCHEDULED, TIMED и неизвестные
        }
    }

    private static func team(_ row: FootballRow.TeamRow) -> Team {
        Team(name: row.nameRu ?? row.shortNameRu ?? row.shortName ?? row.name, abbreviation: row.tla)
    }
}

/// Футбол из таблиц Supabase (D8, D20).
struct FootballRepository: MatchesRepository {
    static let columns = """
        id,utc_date,status,matchday,home_score,away_score,\
        competition:competitions!inner(code,name,name_ru,enabled),\
        home:teams!home_team_id(name,short_name,tla,name_ru,short_name_ru),\
        away:teams!away_team_id(name,short_name,tla,name_ru,short_name_ru)
        """

    /// PostgREST отдаёт timestamptz как "2026-11-20T19:30:00+00:00", иногда с долями секунды.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Неверная дата: \(string)")
        }
        return decoder
    }()

    let client: PostgrestClient

    func matches(in interval: DateInterval) async throws -> [Match] {
        let rows: [FootballRow] = try await client
            .from("matches")
            .select(Self.columns)
            .gte("utc_date", value: interval.start)
            .lt("utc_date", value: interval.end)
            .eq("competition.enabled", value: true) // !inner: строки выключенных турниров сервер не отдаёт
            .execute()
            .value
        return rows.map(FootballMapping.match(from:))
    }
}
