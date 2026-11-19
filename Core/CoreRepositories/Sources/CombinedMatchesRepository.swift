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

    /// По префиксу id: "football:…" и "hockey:…"; чужой префикс — nil.
    func match(id: MatchID) async throws -> Match? {
        if id.rawValue.hasPrefix("\(Sport.football.rawValue):") { return try await football.match(id: id) }
        if id.rawValue.hasPrefix("\(Sport.hockey.rawValue):") { return try await hockey.match(id: id) }
        return nil
    }

    private static func load(_ source: any MatchesRepository, _ interval: DateInterval) async -> Result<[Match], any Error> {
        do { return .success(try await source.matches(in: interval)) } catch { return .failure(error) }
    }
}

extension MatchID {
    /// Id матча в источнике: "football:555081" → "555081".
    var sourceID: String { rawValue.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "" }
}
