import Combine
import Foundation
import MediaPlayer

/// Что сообщает движок о текущем потоке.
enum PlaybackEngineEvent: Equatable {
    case playing
    /// Буферизация или обрыв, движок ждёт данных.
    case waiting
    case failed
    /// Поток доиграл до конца (у эфира конца нет — это обрыв).
    case ended
    /// Позиция и длительность (nil — неизвестна или эфир), раз в 0,5 с и после перемотки.
    case progress(position: TimeInterval, duration: TimeInterval?)
}

/// Тонкая обёртка над AVPlayer — в тестах фейк.
@MainActor
protocol PlaybackEngine: AnyObject {
    var onEvent: ((PlaybackEngineEvent) -> Void)? { get set }
    /// Заменяет поток и запускает его с позиции `position` (0 — с начала).
    func play(_ url: URL, from position: TimeInterval)
    /// Останавливает и отпускает поток (соединение закрывается).
    func stop()
    /// Настоящая пауза: поток остаётся, `resume()` продолжает с того же места.
    func pause()
    func resume()
    func seek(to position: TimeInterval)
    /// Скорость и для текущего, и для следующих потоков.
    func setRate(_ rate: Float)
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
    /// Перемотка на ±секунды (−15 / +30).
    case skip(TimeInterval)
    case seek(to: TimeInterval)
}

/// Данные экрана блокировки / Пункта управления.
struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool
    /// Эфир: без времени, перемотки и скорости.
    var isLive = true
    var elapsed: TimeInterval?
    var duration: TimeInterval?
    var rate: Float = 1

    var dictionary: [String: Any] {
        var dictionary: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
        ]
        if !isLive {
            dictionary[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)
            dictionary[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            dictionary[MPMediaItemPropertyPlaybackDuration] = duration
        }
        return dictionary
    }
}

@MainActor
protocol NowPlayingControlling: AnyObject {
    var onCommand: ((RemoteCommand) -> Void)? { get set }
    /// nil убирает плеер с экрана блокировки. Перемотка включена, только пока на экране выпуск.
    func update(_ info: NowPlayingInfo?)
}

@MainActor
protocol PlaybackClock: AnyObject {
    var now: Date { get }
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable
}
