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
struct SupabasePodcastsRepository: PodcastsRepository {
    let client: PostgrestClient

    func podcasts() async throws -> [Podcast] {
        let rows: [PodcastDTO] = try await client
            .from("podcasts")
            .select("id,title,author,feed_url,artwork_url,featured_order,enabled")
            .execute()
            .value
        return PodcastsMapping.podcasts(from: rows)
    }
}
