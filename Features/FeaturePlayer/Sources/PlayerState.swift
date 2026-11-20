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
    /// Обложка выпуска или подкаста (мини-плеер); у станции nil — значок эфира.
    let artworkURL: URL?
    /// Ползунок, время и скорость выпуска; у эфира nil — плеер радио без них.
    let progress: Progress?

    struct Progress: Equatable {
        /// «18:42».
        let elapsed: String
        /// «−15:28»; пусто, пока длительность неизвестна.
        let remaining: String
        /// Бегунок 0…1; nil — длительность неизвестна, ползунок выключен.
        let fraction: Float?
        /// VoiceOver ползунка: «18 минут 42 секунды из 34 минут».
        let accessibilityValue: String
        /// «1,25×».
        let speed: String
        /// VoiceOver: «Скорость 1,25×».
        let speedLabel: String
        /// Кнопка слева от «Поделиться».
        let download: Download
    }

    /// «Скачать» (нет записи или ошибка), «45 %» (в очереди — «0 %»), «Скачан» (галочка; нажатие — «Удалить загрузку?»).
    enum Download: Equatable {
        case download
        case progress(String)
        case downloaded

        var title: String {
            switch self {
            case .download: "Скачать"
            case let .progress(percent): percent
            case .downloaded: "Скачан"
            }
        }

        /// VoiceOver.
        var accessibilityLabel: String {
            switch self {
            case .download, .downloaded: title
            case let .progress(percent): "Загрузка, \(percent)"
            }
        }
    }
}

enum PlayerFormatter {
    /// Скорости по кругу (D28): 0,75 → 1 → 1,25 → 1,5 → 2 → 0,75.
    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private static let months = ["янв", "февр", "мар", "апр", "мая", "июн", "июл", "авг", "сент", "окт", "нояб", "дек"]

    /// nil — плеер закрыт, мини-плеер скрыт. `scrubPosition` — куда тянут ползунок: пока его держат, время и бегунок
    /// показывают его, а не позицию плеера.
    /// `download` — запись загрузки выпуска в плеере; nil — записи нет.
    static func state(_ playback: PlaybackState, now: Date, scrubPosition: TimeInterval? = nil, download: DownloadState? = nil,
                      calendar: Calendar = .autoupdatingCurrent) -> PlayerState? {
        guard let item = playback.item else { return nil }
        if case let .episode(episode, podcast) = item {
            return episodeState(playback, episode: episode, podcast: podcast, now: now, scrubPosition: scrubPosition,
                                download: download, calendar: calendar)
        }
        let name = item.title
        var subtitle = item.station.map { [$0.country, $0.bitrate.map { "\($0) кбит/с" }].compactMap { $0 }.joined(separator: " · ") } ?? item.subtitle
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
        return PlayerState(
            name: name, header: "Радио · \(name)", caption: item.subtitle.uppercased(),
            status: status, statusTone: tone, subtitle: subtitle, isError: tone == .error, button: button,
            actionLabel: actionLabel(button, name: name), summaryLabel: "\(name), \(status)",
            isAnimating: playback.status == .playing, sleepTimer: sleepTimer(endsAt: playback.sleepTimerEndsAt, now: now),
            artworkURL: nil, progress: nil
        )
    }

    /// Выпуск: в мини-плеере вместо «В эфире» — «<подкаст> · 18:42 из 34:10» (и на паузе — где остановились).
    private static func episodeState(_ playback: PlaybackState, episode: Episode, podcast: Podcast, now: Date,
                                     scrubPosition: TimeInterval?, download: DownloadState?, calendar: Calendar) -> PlayerState {
        let name = episode.title
        let duration = playback.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let position = max(0, min(scrubPosition ?? playback.position ?? 0, duration ?? .infinity))
        let elapsed = time(position)
        let spokenProgress = [spoken(position, genitive: false), duration.map { "из \(spoken($0, genitive: true))" }]
            .compactMap { $0 }.joined(separator: " ")
        var subtitle = "\(podcast.title) · \(day(episode.publishedAt, now: now, calendar: calendar))"
        var progressText = "\(podcast.title) · \(elapsed)"
        if let duration { progressText += " из \(time(duration))" }
        let status: String, tone: PlayerState.Tone, button: PlayControl
        switch playback.status {
        case .playing: (status, tone, button) = (progressText, .secondary, .pause)
        case .loading: (status, tone, button) = ("Подключение…", .secondary, .loading)
        case .idle, .paused: (status, tone, button) = (progressText, .secondary, .play)
        case let .failed(message):
            (status, tone, button) = (message, .error, .play)
            subtitle = message
        }
        let summary = status == progressText ? "\(name), \(podcast.title), \(spokenProgress)" : "\(name), \(status)"
        let speed = speed(playback.rate)
        // Остаток — разность округлённых вниз, чтобы «18:42» и «−15:28» складывались в «34:10».
        let remaining = duration.map { "−" + time(floor($0) - floor(position)) } ?? ""
        let progress = PlayerState.Progress(
            elapsed: elapsed, remaining: remaining, fraction: duration.map { Float(position / $0) },
            accessibilityValue: spokenProgress, speed: speed, speedLabel: "Скорость \(speed.dropLast())",
            download: downloadButton(download)
        )
        return PlayerState(
            name: name, header: "Подкаст · \(podcast.title)", caption: podcast.title.uppercased(),
            status: status, statusTone: tone, subtitle: subtitle, isError: tone == .error, button: button,
            actionLabel: actionLabel(button, name: name), summaryLabel: summary,
            isAnimating: playback.status == .playing, sleepTimer: sleepTimer(endsAt: playback.sleepTimerEndsAt, now: now),
            artworkURL: episode.artworkURL ?? podcast.artworkURL, progress: progress
        )
    }

    private static func downloadButton(_ state: DownloadState?) -> PlayerState.Download {
        switch state {
        case nil, .failed: .download
        case .waiting: .progress("0 %")
        // Вниз: 100 % только у скачанного.
        case let .downloading(progress): .progress("\(Int(max(0, min(progress, 0.99)) * 100)) %")
        case .downloaded: .downloaded
        }
    }

    private static func actionLabel(_ button: PlayControl, name: String) -> String {
        switch button {
        case .pause: "Пауза, \(name)"
        case .loading: "Остановить, \(name)"
        case .play: "Слушать \(name)"
        }
    }

    /// «m:ss» до часа, «h:mm:ss» от часа; секунды вниз, отрицательное и нечисло — «0:00».
    static func time(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let (hours, rest) = total.quotientAndRemainder(dividingBy: 3600)
        let (minutes, secs) = rest.quotientAndRemainder(dividingBy: 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    /// VoiceOver: позиция — «1 час 2 минуты 3 секунды» (нули пропускаем); длительность (`genitive`, после «из») —
    /// до ближайшей минуты: «34 минут», «1 часа 1 минуты».
    static func spoken(_ seconds: TimeInterval, genitive: Bool) -> String {
        let total = seconds.isFinite ? max(0, Int(genitive ? (seconds / 60).rounded() * 60 : seconds)) : 0
        let (hours, rest) = total.quotientAndRemainder(dividingBy: 3600)
        let (minutes, secs) = rest.quotientAndRemainder(dividingBy: 60)
        let parts = genitive
            ? [(hours, ["часа", "часов", "часов"]), (minutes, ["минуты", "минут", "минут"])]
            : [(hours, ["час", "часа", "часов"]), (minutes, ["минута", "минуты", "минут"]), (secs, ["секунда", "секунды", "секунд"])]
        let text = parts.filter { $0.0 > 0 }.map { "\($0.0) \(plural($0.0, $0.1))" }.joined(separator: " ")
        return text.isEmpty ? (genitive ? "0 минут" : "0 секунд") : text
    }

    /// Формы: 1 / 2–4 / 5–20 (21 — как 1, 11–14 — как 5).
    private static func plural(_ count: Int, _ forms: [String]) -> String {
        let (mod10, mod100) = (count % 10, count % 100)
        if mod10 == 1, mod100 != 11 { return forms[0] }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return forms[1] }
        return forms[2]
    }

    /// «1×», «1,25×», «0,75×».
    static func speed(_ rate: Float) -> String {
        var text = String(rate)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text.replacingOccurrences(of: ".", with: ",") + "×"
    }

    /// Дата выпуска в плеере: «18 нояб» (как в макете, без «Сегодня»), в другом году — «18 нояб 2025».
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = "\(parts.day ?? 0) \(months[(parts.month ?? 1) - 1])"
        return parts.year == calendar.component(.year, from: now) ? text : "\(text) \(parts.year ?? 0)"
    }

    /// Минуты округляются вверх: за 24 мин 10 с до срабатывания — «Сон через 25 мин». Истёкший таймер не показываем.
    static func sleepTimer(endsAt: Date?, now: Date) -> String? {
        guard let endsAt, endsAt > now else { return nil }
        return "Сон через \(Int((endsAt.timeIntervalSince(now) / 60).rounded(.up))) мин"
    }
}
