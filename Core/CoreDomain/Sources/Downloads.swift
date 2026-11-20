import Combine
import Foundation

public enum DownloadState: Sendable, Equatable, Codable {
    /// Задача создана, байтов ещё нет (в т.ч. ждёт Wi-Fi).
    case waiting
    case downloading(progress: Double)
    case downloaded(bytes: Int64)
    /// Ошибка (не отмена); повтор — снова `download`.
    case failed
}

/// Выпуск в «Загрузках»: снимки выпуска и подкаста живут, пока пользователь не удалит запись.
public struct DownloadedEpisode: Sendable, Equatable, Codable, Identifiable {
    public var id: EpisodeID { episode.id }
    public let episode: Episode
    public let podcast: Podcast
    public let addedAt: Date
    public var state: DownloadState
    /// Локальная обложка; nil — ещё не скачана или не удалась.
    public var artworkFile: URL?

    public init(episode: Episode, podcast: Podcast, addedAt: Date, state: DownloadState, artworkFile: URL?) {
        self.episode = episode
        self.podcast = podcast
        self.addedAt = addedAt
        self.state = state
        self.artworkFile = artworkFile
    }
}

/// Загрузки выпусков для офлайна.
@MainActor
public protocol EpisodeDownloads: AnyObject {
    /// Новые (по `addedAt`) первыми.
    var items: [DownloadedEpisode] { get }
    var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { get }
    /// Только по Wi-Fi (по умолчанию да); смена перезапускает идущие загрузки.
    var wifiOnly: Bool { get set }
    /// Уже есть и не `.failed` — ничего не делает.
    func download(_ episode: Episode, podcast: Podcast)
    /// Отменяет идущую загрузку или удаляет скачанную.
    func remove(_ id: EpisodeID)
    func removeAll()
    /// Только у `.downloaded` и если файл на месте.
    func localFile(for id: EpisodeID) -> URL?
    /// Место и число только скачанных выпусков.
    func usage() -> (bytes: Int64, count: Int)
    /// Свободно на устройстве (`volumeAvailableCapacityForImportantUsage`); nil — не узнать.
    func availableCapacity() -> Int64?
}

public extension EpisodeDownloads {
    func item(_ id: EpisodeID) -> DownloadedEpisode? { items.first { $0.id == id } }
}
