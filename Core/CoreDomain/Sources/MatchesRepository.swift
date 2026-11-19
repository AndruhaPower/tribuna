import Foundation

public protocol MatchesRepository: Sendable {
    func matches(in interval: DateInterval) async throws -> [Match]
}
