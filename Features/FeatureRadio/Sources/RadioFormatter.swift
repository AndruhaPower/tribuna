import CoreDomain
import Foundation

enum RadioFormatter {
    static func title(_ genre: StationGenre) -> String {
        switch genre {
        case .sport: "Спорт"
        case .football: "Футбол"
        case .hockey: "Хоккей"
        case .news: "Новости"
        }
    }

    static func chips(selected: StationGenre) -> [RadioState.Chip] {
        StationGenre.allCases.map { .init(id: $0, title: title($0), isSelected: $0 == selected) }
    }

    /// Без поиска — «Подборка редакции» жанра по `featuredOrder`; с поиском — все совпадения по названию или жанру, жанр не учитывается.
    static func content(stations: [Station], genre: StationGenre, query: String, playback: PlaybackState) -> RadioState.Content {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        let found: [Station]
        if query.isEmpty {
            title = "ПОДБОРКА РЕДАКЦИИ"
            found = stations
                .filter { $0.featuredOrder != nil && $0.genres.contains(genre) }
                .enumerated()
                .sorted { ($0.element.featuredOrder ?? 0, $0.offset) < ($1.element.featuredOrder ?? 0, $1.offset) }
                .map(\.element)
        } else {
            title = "РЕЗУЛЬТАТЫ ПОИСКА"
            found = stations.filter { station in
                ([station.name] + station.genres.map(Self.title)).contains { $0.range(of: query, options: .caseInsensitive) != nil }
            }
        }
        guard !found.isEmpty else { return .empty(message: "Ничего не нашлось") }
        return .loaded(title: title, rows: found.map { station in
            let status = playback.item?.station?.id == station.id ? playback.status : .idle
            let (value, action): (String?, String) = switch status {
            case .playing: ("играет", "Пауза")
            case .loading: ("подключение", "Остановить")
            default: (nil, "Слушать \(station.name)")
            }
            return .init(
                id: station.id, initials: initials(station.name), name: station.name, subtitle: station.subtitle,
                button: status == .playing ? .pause : status == .loading ? .loading : .play,
                accessibilityLabel: "\(station.name), \(station.subtitle)", accessibilityValue: value, actionLabel: action
            )
        })
    }

    static func nowPlaying(_ playback: PlaybackState) -> RadioState.NowPlaying? {
        guard let station = playback.item?.station else { return nil }
        var subtitle = [station.country, station.bitrate.map { "\($0) кбит/с" }].compactMap { $0 }.joined(separator: " · ")
        var isError = false
        let button: RadioState.Button
        let caption: String
        switch playback.status {
        case .playing: (button, caption) = (.pause, "СЕЙЧАС ИГРАЕТ")
        case .loading: (button, caption) = (.loading, "СЕЙЧАС ИГРАЕТ")
        case .idle, .paused: (button, caption) = (.play, "НА ПАУЗЕ")
        case let .failed(message):
            (button, caption) = (.play, "НЕТ СВЯЗИ")
            subtitle = message
            isError = true
        }
        let actionLabel = switch button {
        case .pause: "Пауза, \(station.name)"
        case .loading: "Остановить, \(station.name)"
        case .play: "Слушать \(station.name)"
        }
        return .init(
            id: station.id, name: station.name, subtitle: subtitle, isError: isError, caption: caption, isCaptionActive: button != .play, button: button,
            actionLabel: actionLabel, isAnimating: playback.status == .playing
        )
    }

    /// Две буквы для значка станции: первые буквы двух первых слов («Голос матча» → «ГМ»), у одного слова — его первые две буквы.
    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.count >= 2 ? String(words[0].prefix(1) + words[1].prefix(1)) : String(words.first?.prefix(2) ?? "")
        return letters.uppercased()
    }
}
