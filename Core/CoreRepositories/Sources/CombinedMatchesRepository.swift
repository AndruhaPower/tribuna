import CoreDomain
import Foundation

/// Футбол и НХЛ параллельно. Упал один источник — отдаём другой; пусто и есть ошибка — первая ошибка.
struct CombinedMatchesRepository: MatchesRepository {
    let football: any MatchesRepository
    let hockey: any MatchesRepository

    func matches(in interval: DateInterval) async throws -> [Match] {
        async let footballResult = Self.load(football, interval)
        async let hockeyResult = Self.load(hockey, interval)
        let results = await [footballResult, hockeyResult]

        let combined = results.compactMap { try? $0.get() }.flatMap { $0 }
        // Пусто при упавшем источнике — не «матчей нет», а ошибка (экран покажет «Повторить»).
        if combined.isEmpty, let error = results.compactMap({ if case let .failure(e) = $0 { e } else { nil } }).first { throw error }
        return combined
    }

    private static func load(_ source: any MatchesRepository, _ interval: DateInterval) async -> Result<[Match], any Error> {
        do { return .success(try await source.matches(in: interval)) } catch { return .failure(error) }
    }
}
