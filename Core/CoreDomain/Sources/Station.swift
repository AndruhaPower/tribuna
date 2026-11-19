import Foundation

public enum StationGenre: String, Sendable, CaseIterable {
    case sport, football, hockey, news
}

/// Радиостанция каталога (D16, D23): данные редакции из таблицы `stations`.
public struct Station: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let streamURL: URL
    public let country: String
    /// nil — битрейт неизвестен (HLS и часть потоков).
    public let bitrate: Int?
    public let genres: Set<StationGenre>
    public let subtitle: String
    /// Место в «Подборке редакции»; nil — в подборку не входит.
    public let featuredOrder: Int?

    public init(id: String, name: String, streamURL: URL, country: String, bitrate: Int?, genres: Set<StationGenre>, subtitle: String, featuredOrder: Int?) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.country = country
        self.bitrate = bitrate
        self.genres = genres
        self.subtitle = subtitle
        self.featuredOrder = featuredOrder
    }
}

public protocol StationsRepository: Sendable {
    /// Только включённые станции: по `featuredOrder` (nil — в конце), затем по имени.
    func stations() async throws -> [Station]
}
