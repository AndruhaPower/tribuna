import CoreDomain
import Foundation

/// Футбол и НХЛ параллельно. Упал один источник — отдаём другой; упали оба — первая ошибка.
struct CombinedMatchesRepository: MatchesRepository {
    let football: any MatchesRepository
    let hockey: any MatchesRepository

    func matches(in interval: DateInterval) async throws -> [Match] {
        async let footballResult = Self.load(football, interval)
        async let hockeyResult = Self.load(hockey, interval)
        let results = await [footballResult, hockeyResult]

        let loaded = results.compactMap { try? $0.get() }
        if loaded.isEmpty, case let .failure(error) = results[0] { throw error }
        return loaded.flatMap { $0 }
    }

    private static func load(_ source: any MatchesRepository, _ interval: DateInterval) async -> Result<[Match], any Error> {
        do { return .success(try await source.matches(in: interval)) } catch { return .failure(error) }
    }
}
