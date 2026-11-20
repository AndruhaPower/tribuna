import Combine
import Foundation

/// Подкаст каталога (D16): данные редакции из таблицы `podcasts`, выпуски — из RSS-ленты.
public struct Podcast: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let author: String
    public let feedURL: URL
    public let artworkURL: URL
    /// Место в «Подборке»; nil — в конце каталога.
    public let featuredOrder: Int?

    public init(id: String, title: String, author: String, feedURL: URL, artworkURL: URL, featuredOrder: Int?) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.featuredOrder = featuredOrder
    }
}

/// Идентификатор выпуска вида "<id подкаста>:<guid>" — стабилен между загрузками ленты.
public struct EpisodeID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(podcastID: String, guid: String) {
        self.rawValue = "\(podcastID):\(guid)"
    }
}

/// Выпуск подкаста из RSS: только с https-аудио (ATS) и датой публикации.
public struct Episode: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let id: EpisodeID
    public let podcastID: String
    public let title: String
    public let publishedAt: Date
    /// nil — в ленте нет `itunes:duration` или она нечитаема.
    public let duration: TimeInterval?
    public let audioURL: URL
    /// Обложка выпуска; nil — показываем обложку подкаста.
    public let artworkURL: URL?
    public let link: URL?

    public init(id: EpisodeID, podcastID: String, title: String, publishedAt: Date, duration: TimeInterval?, audioURL: URL, artworkURL: URL?, link: URL?) {
        self.id = id
        self.podcastID = podcastID
        self.title = title
        self.publishedAt = publishedAt
        self.duration = duration
        self.audioURL = audioURL
        self.artworkURL = artworkURL
        self.link = link
    }
}

public protocol PodcastsRepository: Sendable {
    /// Только включённые подкасты: по `featuredOrder` (nil — в конце), затем по названию.
    func podcasts() async throws -> [Podcast]
}

public protocol EpisodesRepository: Sendable {
    /// Выпуски, новые первыми. Без `forceRefresh` лента берётся из кеша, если её загружали меньше 30 мин назад;
    /// при сбое сети отдаётся кеш (если есть).
    func episodes(for podcast: Podcast, forceRefresh: Bool) async throws -> [Episode]
}

/// Подписки на телефоне: id подкаста → когда подписались (нужно для «новых» выпусков).
@MainActor
public protocol SubscriptionsStore: AnyObject {
    var subscriptions: [String: Date] { get }
    var subscriptionsPublisher: AnyPublisher<[String: Date], Never> { get }
    /// Подписывает (с текущим временем) или отписывает.
    func toggle(_ podcastID: String)
}

public struct ListeningProgress: Sendable, Equatable, Codable {
    /// Где остановились, секунды.
    public var position: TimeInterval
    /// Дослушан (≥95 %); остаётся прослушанным и при повторном прослушивании.
    public var isFinished: Bool

    public init(position: TimeInterval, isFinished: Bool) {
        self.position = position
        self.isFinished = isFinished
    }
}

/// Позиция прослушивания и «прослушано» на телефоне. Выпуска нет в `progress` — он не начат.
@MainActor
public protocol ListeningProgressStore: AnyObject {
    var progress: [EpisodeID: ListeningProgress] { get }
    var progressPublisher: AnyPublisher<[EpisodeID: ListeningProgress], Never> { get }
    func setPosition(_ position: TimeInterval, for id: EpisodeID)
    /// Отмечает прослушанным и сбрасывает позицию на начало: повторное прослушивание — с начала.
    func markFinished(_ id: EpisodeID)
}

public extension ListeningProgressStore {
    /// nil — выпуск не начат.
    func position(for id: EpisodeID) -> TimeInterval? { progress[id]?.position }

    func isFinished(_ id: EpisodeID) -> Bool { progress[id]?.isFinished ?? false }
}
