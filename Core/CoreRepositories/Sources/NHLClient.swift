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
            let id: Int?
            /// score/{date} отдаёт `name`, gamecenter/{id}/landing — `commonName`.
            let name: Name?
            let commonName: Name?
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

    /// 404 от NHL Web API: такой игры нет.
    struct NotFound: Error {}

    private let fetch: @Sendable (URL) async throws -> Data

    init(fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.fetch = fetch
    }

    init(session: URLSession) {
        self.init { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 404 { throw NotFound() }
            guard status == 200 else { throw URLError(.badServerResponse) }
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

    func match(id: MatchID) async throws -> Match? {
        guard let gameID = Int(id.sourceID) else { return nil }
        let url = URL(string: "https://api-web.nhle.com/v1/gamecenter/\(gameID)/landing")!
        do { return try Self.parseLanding(await fetch(url)) } catch is NotFound { return nil }
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
        try decoder.decode(ScoreResponse.self, from: data).games.map(match(from:))
    }

    /// gamecenter/{id}/landing — одна игра на верхнем уровне.
    static func parseLanding(_ data: Data) throws -> Match {
        match(from: try decoder.decode(Game.self, from: data))
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func match(from game: Game) -> Match {
        func team(_ dto: Game.TeamDTO) -> Team {
            Team(name: (dto.name ?? dto.commonName)?.default ?? dto.abbrev, abbreviation: dto.abbrev)
        }
        return Match(
            id: MatchID(sport: .hockey, sourceID: String(game.id)),
            sport: .hockey,
            competition: competition,
            kickoff: game.startTimeUTC,
            status: status(game.gameState, scheduleState: game.gameScheduleState),
            home: team(game.homeTeam),
            away: team(game.awayTeam),
            homeScore: game.homeTeam.score,
            awayScore: game.awayTeam.score,
            round: nil,
            homeTeamID: game.homeTeam.id.map(String.init),
            awayTeamID: game.awayTeam.id.map(String.init)
        )
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
        case "FINAL", "OFF", "OVER": .finished
        case "PPD": .postponed
        case "CNCL": .cancelled
        default: .scheduled // FUT, PRE и неизвестные
        }
    }
}
