import CoreDomain
import Foundation

/// НХЛ напрямую из NHL Web API: ключ не нужен (D8).
struct NHLClient: MatchesRepository {
    private struct ScoreResponse: Decodable {
        let games: [Game]
    }

    private struct Game: Decodable {
        struct TeamDTO: Decodable {
            struct Name: Decodable { let `default`: String }
            let name: Name
            let abbrev: String
            let score: Int?
        }

        let id: Int
        let startTimeUTC: Date
        let gameState: String
        let gameScheduleState: String?
        let homeTeam: TeamDTO
        let awayTeam: TeamDTO
    }

    static let competition = Competition(code: "NHL", name: "НХЛ")

    private let fetch: @Sendable (URL) async throws -> Data

    init(fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.fetch = fetch
    }

    init(session: URLSession) {
        self.init { url in
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        }
    }

    func matches(in interval: DateInterval) async throws -> [Match] {
        try await withThrowingTaskGroup(of: [Match].self) { group in
            for date in Self.datesToQuery(for: interval) {
                let url = URL(string: "https://api-web.nhle.com/v1/score/\(date)")!
                group.addTask { try Self.parse(await fetch(url)) }
            }
            return try await group.reduce(into: []) { $0 += $1 }
                .filter { $0.kickoff >= interval.start && $0.kickoff < interval.end }
                .sorted { $0.kickoff < $1.kickoff }
        }
    }

    /// Дни НХЛ (по восточному времени США), покрывающие полуоткрытый интервал [start, end).
    static func datesToQuery(for interval: DateInterval) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let last = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        var day = calendar.startOfDay(for: interval.start)
        var dates: [String] = []
        while day <= last {
            dates.append(formatter.string(from: day))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return dates
    }

    static func parse(_ data: Data) throws -> [Match] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScoreResponse.self, from: data).games.map { game in
            Match(
                id: MatchID(sport: .hockey, sourceID: String(game.id)),
                sport: .hockey,
                competition: competition,
                kickoff: game.startTimeUTC,
                status: status(game.gameState, scheduleState: game.gameScheduleState),
                home: Team(name: game.homeTeam.name.default, abbreviation: game.homeTeam.abbrev),
                away: Team(name: game.awayTeam.name.default, abbreviation: game.awayTeam.abbrev),
                homeScore: game.homeTeam.score,
                awayScore: game.awayTeam.score,
                round: nil
            )
        }
    }

    /// Перенесённые и отменённые игры остаются gameState "FUT", поэтому сначала смотрим gameScheduleState.
    static func status(_ code: String, scheduleState: String? = nil) -> MatchStatus {
        switch scheduleState {
        case "PPD", "SUSP": return .postponed
        case "CNCL": return .cancelled
        default: break
        }
        return switch code {
        case "LIVE", "CRIT": .live
        case "FINAL", "OFF": .finished
        case "PPD": .postponed
        case "CNCL": .cancelled
        default: .scheduled // FUT, PRE и неизвестные
        }
    }
}
