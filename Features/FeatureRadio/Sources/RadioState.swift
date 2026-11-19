import CoreDomain

/// Готовое к показу состояние экрана «Эфир»: контроллер ничего не форматирует.
struct RadioState: Equatable {
    /// Что рисовать на кнопке воспроизведения.
    enum Button: Hashable {
        case play, pause
        /// Подключение: индикатор вместо значка, нажатие отменяет.
        case loading
    }

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
        let button: Button
        /// Волна анимируется только при воспроизведении.
        let isAnimating: Bool
    }

    struct Row: Hashable, Identifiable {
        let id: String
        let initials: String
        let name: String
        let subtitle: String
        /// `.pause` у станции, которая играет или подключается.
        let button: Button
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
