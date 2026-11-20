import CoreDomain
import Foundation

/// Выпуски из RSS-ленты с кешем на диске (`Caches/feeds`, JSON выпусков и время загрузки).
/// Обновляем по своему расписанию, без условных запросов (см. «Грабли» про ETag).
struct FeedRepository: EpisodesRepository {
    static let refreshInterval: TimeInterval = 30 * 60

    private struct Cache: Codable {
        let feedURL: URL
        let fetchedAt: Date
        let episodes: [Episode]
    }

    let directory: URL
    let fetch: @Sendable (URL) async throws -> Data
    let now: @Sendable () -> Date

    init(directory: URL, fetch: @escaping @Sendable (URL) async throws -> Data, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.fetch = fetch
        self.now = now
    }

    /// Загрузка по сети: ответ не 2xx — ошибка.
    static func fetch(session: URLSession) -> @Sendable (URL) async throws -> Data {
        { url in
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    // shortcut: параллельные вызовы для одной ленты могут скачать её дважды; склеивать, если появится много одновременных обновлений.
    func episodes(for podcast: Podcast, forceRefresh: Bool) async throws -> [Episode] {
        let file = directory.appendingPathComponent(fileName(podcast.id))
        let cached = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            .flatMap { $0.feedURL == podcast.feedURL ? $0 : nil }
        if !forceRefresh, let cached, now().timeIntervalSince(cached.fetchedAt) < Self.refreshInterval {
            return cached.episodes
        }
        do {
            let data = try await fetch(podcast.feedURL)
            let episodes = try RSSParser.episodes(from: data, podcastID: podcast.id)
            let cache = Cache(feedURL: podcast.feedURL, fetchedAt: now(), episodes: episodes)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(cache).write(to: file, options: .atomic)
            return episodes
        } catch {
            // Нет сети или лента сломалась — показываем, что было; время загрузки не трогаем, повторим в следующий раз.
            guard let cached else { throw error }
            return cached.episodes
        }
    }

    private func fileName(_ podcastID: String) -> String {
        (podcastID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? podcastID) + ".json"
    }
}
