import Combine
import Foundation
import MediaPlayer

/// Что сообщает движок о текущем потоке.
enum PlaybackEngineEvent: Equatable {
    case playing
    /// Буферизация или обрыв, движок ждёт данных.
    case waiting
    case failed
}

/// Тонкая обёртка над AVPlayer — в тестах фейк.
@MainActor
protocol PlaybackEngine: AnyObject {
    var onEvent: ((PlaybackEngineEvent) -> Void)? { get set }
    /// Заменяет поток и запускает его.
    func play(_ url: URL)
    /// Останавливает и отпускает поток (соединение закрывается).
    func stop()
}

enum AudioSessionEvent: Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// Пропал аудиовыход (отключили наушники).
    case outputLost
}

@MainActor
protocol AudioSessionControlling: AnyObject {
    var onEvent: ((AudioSessionEvent) -> Void)? { get set }
    func activate() throws
    /// Отпускает звук, чтобы другие приложения могли продолжить.
    func deactivate()
}

enum RemoteCommand: Equatable {
    case play, pause, togglePlayPause
}

/// Данные экрана блокировки / Пункта управления.
struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool

    var dictionary: [String: Any] {
        [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }
}

@MainActor
protocol NowPlayingControlling: AnyObject {
    var onCommand: ((RemoteCommand) -> Void)? { get set }
    /// nil убирает плеер с экрана блокировки.
    func update(_ info: NowPlayingInfo?)
}

@MainActor
protocol PlaybackClock: AnyObject {
    var now: Date { get }
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable
}
