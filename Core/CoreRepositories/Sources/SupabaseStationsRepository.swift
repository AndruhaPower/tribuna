import CoreDomain
import Foundation
import PostgREST

/// Строка таблицы `stations`.
struct StationDTO: Decodable, Sendable {
    let id: String
    let name: String
    let streamURL: String
    let country: String
    let bitrate: Int?
    let genres: [String]
    let subtitle: String
    let featuredOrder: Int?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, country, bitrate, genres, subtitle, enabled
        case streamURL = "stream_url"
        case featuredOrder = "featured_order"
    }
}

enum StationsMapping {
    /// Отбрасывает выключенные и с битым URL, неизвестные жанры; сортирует по featured_order (nil — в конце), затем по имени.
    static func stations(from rows: [StationDTO]) -> [Station] {
        rows.compactMap { row -> Station? in
            guard row.enabled, let url = URL(string: row.streamURL), url.scheme != nil else { return nil }
            return Station(
                id: row.id, name: row.name, streamURL: url, country: row.country, bitrate: row.bitrate,
                genres: Set(row.genres.compactMap(StationGenre.init(rawValue:))), subtitle: row.subtitle, featuredOrder: row.featuredOrder
            )
        }
        .sorted { ($0.featuredOrder ?? .max, $0.name) < ($1.featuredOrder ?? .max, $1.name) }
    }
}

/// Каталог станций из Supabase (D16): RLS отдаёт клиенту только enabled.
struct SupabaseStationsRepository: StationsRepository {
    let client: PostgrestClient

    func stations() async throws -> [Station] {
        let rows: [StationDTO] = try await client
            .from("stations")
            .select("id,name,stream_url,country,bitrate,genres,subtitle,featured_order,enabled")
            .execute()
            .value
        return StationsMapping.stations(from: rows)
    }
}
