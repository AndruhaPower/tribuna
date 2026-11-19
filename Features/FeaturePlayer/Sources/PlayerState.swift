import CoreDomain
import CoreUI
import Foundation

/// Готовое к показу состояние мини-плеера и плеера: представления ничего не форматируют.
struct PlayerState: Equatable {
    /// Цвет строки статуса мини-плеера.
    enum Tone: Equatable {
        /// Акцент и точка перед текстом: «● В эфире».
        case live
        case secondary
        /// Ошибка: «Не удалось подключиться».
        case error
    }

    let name: String
    /// Шапка плеера: «Радио · <станция>».
    let header: String
    /// Подпись над волной в карточке плеера: подпись станции заглавными.
    let caption: String
    /// Мини-плеер: «В эфире» (с точкой, `Tone.live`), «Подключение…», «На паузе» или текст ошибки.
    let status: String
    let statusTone: Tone
    /// Плеер: «Россия · 128 кбит/с» или текст ошибки.
    let subtitle: String
    let isError: Bool
    let button: PlayControl
    /// VoiceOver, кнопка: «Пауза, <станция>», «Остановить, <станция>» или «Слушать <станция>».
    let actionLabel: String
    /// VoiceOver, мини-плеер: «<станция>, <статус>».
    let summaryLabel: String
    /// Волна анимируется только при воспроизведении.
    let isAnimating: Bool
    /// «Сон через 25 мин»; nil — таймер не задан.
    let sleepTimer: String?
}

enum PlayerFormatter {
    /// nil — плеер закрыт, мини-плеер скрыт.
    static func state(_ playback: PlaybackState, now: Date) -> PlayerState? {
        guard let station = playback.item else { return nil }
        var subtitle = [station.country, station.bitrate.map { "\($0) кбит/с" }].compactMap { $0 }.joined(separator: " · ")
        let status: String, tone: PlayerState.Tone, button: PlayControl
        switch playback.status {
        case .playing:
            (status, tone, button) = ("В эфире", .live, .pause)
        case .loading:
            (status, tone, button) = ("Подключение…", .secondary, .loading)
        case .idle, .paused:
            (status, tone, button) = ("На паузе", .secondary, .play)
        case let .failed(message):
            (status, tone, button) = (message, .error, .play)
            subtitle = message
        }
        let actionLabel = switch button {
        case .pause: "Пауза, \(station.name)"
        case .loading: "Остановить, \(station.name)"
        case .play: "Слушать \(station.name)"
        }
        return PlayerState(
            name: station.name, header: "Радио · \(station.name)", caption: station.subtitle.uppercased(),
            status: status, statusTone: tone, subtitle: subtitle, isError: tone == .error, button: button,
            actionLabel: actionLabel, summaryLabel: "\(station.name), \(status)",
            isAnimating: playback.status == .playing, sleepTimer: sleepTimer(endsAt: playback.sleepTimerEndsAt, now: now)
        )
    }

    /// Минуты округляются вверх: за 24 мин 10 с до срабатывания — «Сон через 25 мин». Истёкший таймер не показываем.
    static func sleepTimer(endsAt: Date?, now: Date) -> String? {
        guard let endsAt, endsAt > now else { return nil }
        return "Сон через \(Int((endsAt.timeIntervalSince(now) / 60).rounded(.up))) мин"
    }
}
