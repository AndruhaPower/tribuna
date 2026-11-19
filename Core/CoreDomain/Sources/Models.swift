import Foundation

public enum Sport: String, Sendable {
    case football, hockey
}

/// Идентификатор матча вида "football:555081" / "hockey:2025020301".
public struct MatchID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(sport: Sport, sourceID: String) {
        self.rawValue = "\(sport.rawValue):\(sourceID)"
    }
}

public enum MatchStatus: Sendable, Equatable {
    case scheduled, live, paused, finished, postponed, cancelled
}

public struct Team: Sendable, Equatable {
    /// Уже выбрано: name_ru ?? short_name_ru ?? short_name ?? name.
    public let name: String
    public let abbreviation: String?

    public init(name: String, abbreviation: String?) {
        self.name = name
        self.abbreviation = abbreviation
    }
}

public struct Competition: Sendable, Equatable {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public struct Match: Sendable, Equatable, Identifiable {
    public let id: MatchID
    public let sport: Sport
    public let competition: Competition
    public let kickoff: Date
    public let status: MatchStatus
    public let home: Team?
    public let away: Team?
    public let homeScore: Int?
    public let awayScore: Int?
    /// "12 тур" для футбола, nil для НХЛ.
    public let round: String?

    public init(
        id: MatchID,
        sport: Sport,
        competition: Competition,
        kickoff: Date,
        status: MatchStatus,
        home: Team?,
        away: Team?,
        homeScore: Int?,
        awayScore: Int?,
        round: String?
    ) {
        self.id = id
        self.sport = sport
        self.competition = competition
        self.kickoff = kickoff
        self.status = status
        self.home = home
        self.away = away
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.round = round
    }
}
