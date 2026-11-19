import CoreDomain
import CoreUI

/// Готовое к показу состояние экрана «Эфир»: контроллер ничего не форматирует.
struct RadioState: Equatable {
    /// Что рисовать на кнопке воспроизведения (общая с плеером, CoreUI).
    typealias Button = PlayControl

    struct Chip: Hashable, Identifiable {
        let id: StationGenre
        let title: String
        let isSelected: Bool
    }

    /// Карточка «Сейчас играет».
    struct NowPlaying: Hashable {
        let id: String
        let name: String
        /// «Россия · 128 кбит/с» или текст ошибки.
        let subtitle: String
        let isError: Bool
        /// «СЕЙЧАС ИГРАЕТ» (играет, подключение), «НА ПАУЗЕ» или «НЕТ СВЯЗИ».
        let caption: String
        /// Точка и подпись акцентные при игре/подключении, иначе вторичные.
        let isCaptionActive: Bool
        let button: Button
        /// VoiceOver: «Пауза, <станция>», «Остановить, <станция>» или «Слушать <станция>».
        let actionLabel: String
        /// Волна анимируется только при воспроизведении.
        let isAnimating: Bool
    }

    struct Row: Hashable, Identifiable {
        let id: String
        let initials: String
        let name: String
        let subtitle: String
        /// `.pause` у играющей станции, `.loading` у подключающейся.
        let button: Button
        /// VoiceOver: «<станция>, <подпись>».
        let accessibilityLabel: String
        /// VoiceOver: «играет», «подключение» или nil.
        let accessibilityValue: String?
        /// VoiceOver, действие кнопки: «Пауза», «Остановить» или «Слушать <станция>».
        let actionLabel: String
    }

    enum Content: Equatable {
        case loading
        case loaded(title: String, rows: [Row])
        case empty(message: String)
        case error(message: String)
    }

    var query = ""
    var chips: [Chip]
    var nowPlaying: NowPlaying?
    var content: Content
}
