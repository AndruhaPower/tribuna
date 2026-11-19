import Combine
import Foundation

public enum PlaybackStatus: Equatable, Sendable {
    case idle, loading, playing, paused
    /// Текст ошибки уже для показа.
    case failed(String)
}

public struct PlaybackState: Equatable, Sendable {
    /// Что играет или стоит на паузе; nil — плеер закрыт.
    public var item: Station?
    public var status: PlaybackStatus
    /// Когда сработает таймер сна; nil — таймер не задан.
    public var sleepTimerEndsAt: Date?

    public init(item: Station?, status: PlaybackStatus, sleepTimerEndsAt: Date?) {
        self.item = item
        self.status = status
        self.sleepTimerEndsAt = sleepTimerEndsAt
    }
}

/// Один плеер на приложение (D15): его запускают фичи, мини-плеер и плеер подписаны на состояние.
@MainActor
public protocol AudioPlayer: AnyObject {
    var state: PlaybackState { get }
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    func play(_ station: Station)
    /// Пауза или продолжение; после ошибки — повторное подключение.
    func togglePlayPause()
    /// Останавливает и закрывает плеер: `item` = nil, таймер сна снят.
    func stop()
    /// nil снимает таймер.
    func setSleepTimer(minutes: Int?)
}
