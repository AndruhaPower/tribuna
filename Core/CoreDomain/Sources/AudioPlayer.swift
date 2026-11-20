import Combine
import Foundation

public enum PlaybackStatus: Equatable, Sendable {
    case idle, loading, playing, paused
    /// Текст ошибки уже для показа.
    case failed(String)
}

/// Что играет: станция (эфир) или выпуск подкаста.
public enum PlaybackItem: Equatable, Sendable {
    case station(Station)
    case episode(Episode, podcast: Podcast)

    public var title: String {
        switch self {
        case let .station(station): station.name
        case let .episode(episode, _): episode.title
        }
    }

    /// Станция — её подпись, выпуск — название подкаста.
    public var subtitle: String {
        switch self {
        case let .station(station): station.subtitle
        case let .episode(_, podcast): podcast.title
        }
    }

    /// Обложка выпуска или подкаста; у станции нет.
    public var artworkURL: URL? {
        switch self {
        case .station: nil
        case let .episode(episode, podcast): episode.artworkURL ?? podcast.artworkURL
        }
    }

    /// Эфир: без перемотки, скорости и позиции.
    public var isLive: Bool {
        if case .station = self { true } else { false }
    }

    public var station: Station? {
        if case let .station(station) = self { station } else { nil }
    }

    public var episode: Episode? {
        if case let .episode(episode, _) = self { episode } else { nil }
    }
}

public struct PlaybackState: Equatable, Sendable {
    /// Что играет или стоит на паузе; nil — плеер закрыт.
    public var item: PlaybackItem?
    public var status: PlaybackStatus
    /// Когда сработает таймер сна; nil — таймер не задан.
    public var sleepTimerEndsAt: Date?
    /// Позиция выпуска, секунды; у эфира nil.
    public var position: TimeInterval?
    /// Длительность выпуска; nil — у эфира или пока неизвестна.
    public var duration: TimeInterval?
    /// Скорость выпуска; у эфира всегда 1.
    public var rate: Float

    public init(item: PlaybackItem?, status: PlaybackStatus, sleepTimerEndsAt: Date?, position: TimeInterval? = nil, duration: TimeInterval? = nil, rate: Float = 1) {
        self.item = item
        self.status = status
        self.sleepTimerEndsAt = sleepTimerEndsAt
        self.position = position
        self.duration = duration
        self.rate = rate
    }
}

/// Один плеер на приложение (D15): его запускают фичи, мини-плеер и плеер подписаны на состояние.
@MainActor
public protocol AudioPlayer: AnyObject {
    var state: PlaybackState { get }
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    /// Выпуск: прослушанный — с начала, если позиция в последних 5 %; иначе с сохранённого места.
    func play(_ item: PlaybackItem)
    /// Пауза или продолжение; после ошибки — повторное подключение.
    func togglePlayPause()
    /// Останавливает и закрывает плеер: `item` = nil, таймер сна снят.
    func stop()
    /// nil снимает таймер.
    func setSleepTimer(minutes: Int?)
    /// Только выпуск: позиция в пределах [0, длительность]. Эфир не перематывается.
    func seek(to position: TimeInterval)
    /// Только выпуск: −15 / +30 с от текущей позиции.
    func skip(by seconds: TimeInterval)
    /// Только выпуск: 0,75 / 1 / 1,25 / 1,5 / 2; сохраняется для следующих выпусков до перезапуска приложения.
    func setRate(_ rate: Float)
}

public extension AudioPlayer {
    func play(_ station: Station) { play(.station(station)) }
}
