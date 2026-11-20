import CoreDomain
import Foundation
import PostgREST

/// Строка таблицы `podcasts`.
struct PodcastDTO: Decodable, Sendable {
    let id: String
    let title: String
    let author: String
    let feedURL: String
    let artworkURL: String
    let featuredOrder: Int?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, author, enabled
        case feedURL = "feed_url"
        case artworkURL = "artwork_url"
        case featuredOrder = "featured_order"
    }
}

enum PodcastsMapping {
    /// Отбрасывает выключенные и с не-https лентой или обложкой (ATS); сортирует по featured_order (nil — в конце), затем по названию.
    static func podcasts(from rows: [PodcastDTO]) -> [Podcast] {
        func https(_ text: String) -> URL? {
            guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
            return url
        }
        return rows.compactMap { row -> Podcast? in
            guard row.enabled, let feed = https(row.feedURL), let artwork = https(row.artworkURL) else { return nil }
            return Podcast(id: row.id, title: row.title, author: row.author, feedURL: feed, artworkURL: artwork, featuredOrder: row.featuredOrder)
        }
        .sorted { ($0.featuredOrder ?? .max, $0.title) < ($1.featuredOrder ?? .max, $1.title) }
    }
}

/// Каталог подкастов из Supabase (D16): RLS отдаёт клиенту только enabled.
/// Как `FeedRepository` (D27): успех пишет кеш, сбой отдаёт кеш, нет кеша — ошибка. Всегда сначала сеть.
struct SupabasePodcastsRepository: PodcastsRepository {
    let cacheFile: URL?
    let fetch: @Sendable () async throws -> [Podcast]

    init(client: PostgrestClient, cacheFile: URL? = nil) {
        self.init(cacheFile: cacheFile) {
            let rows: [PodcastDTO] = try await client
                .from("podcasts")
                .select("id,title,author,feed_url,artwork_url,featured_order,enabled")
                .execute()
                .value
            return PodcastsMapping.podcasts(from: rows)
        }
    }

    init(cacheFile: URL?, fetch: @escaping @Sendable () async throws -> [Podcast]) {
        self.cacheFile = cacheFile
        self.fetch = fetch
    }

    func podcasts() async throws -> [Podcast] {
        do {
            let result = try await fetch()
            if let cacheFile {
                try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(result).write(to: cacheFile, options: .atomic)
            }
            return result
        } catch {
            if let cacheFile, let data = try? Data(contentsOf: cacheFile), let cached = try? JSONDecoder().decode([Podcast].self, from: data) {
                return cached
            }
            throw error
        }
    }
}
