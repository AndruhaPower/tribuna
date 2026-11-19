import Foundation

public protocol MatchesRepository: Sendable {
    func matches(in interval: DateInterval) async throws -> [Match]
    /// nil — матча с таким id нет.
    func match(id: MatchID) async throws -> Match?
}

public protocol StandingsRepository: Sendable {
    /// Основная таблица турнира по `position`; пусто — таблицы нет.
    func standings(competitionCode: String) async throws -> [StandingRow]
}
