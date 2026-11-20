import CoreDomain
import Foundation

/// Строка выпуска — общая для «Новых выпусков» и экрана подкаста.
struct EpisodeRow: Hashable, Identifiable {
    /// Кнопка-пилюля под строкой: «Слушать» или «Пауза» (выпуск играет или подключается).
    enum Button: Hashable {
        case listen, pause
    }

    let id: EpisodeID
    let artworkURL: URL
    /// «● Новый · Вне игры» или «Вне игры».
    let caption: String
    /// Новый — подпись светлая с точкой, иначе вторичная.
    let isNew: Bool
    let title: String
    /// «Сегодня · 34 мин», «16 нояб · осталось 12 мин», «2 нояб · прослушано».
    let subtitle: String
    /// nil — без кнопки (она у первой строки и у выпуска в плеере).
    let button: Button?
    /// VoiceOver: «<выпуск>, <подпись>, <дата и длительность>».
    let accessibilityLabel: String
}

/// Плитка подписки: обложка с названием и «2 новых» / «Всё прослушано».
struct SubscriptionTile: Hashable, Identifiable {
    let id: String
    let title: String
    let artworkURL: URL
    let subtitle: String
}

/// Подкаст в «Подборке»: «Подписаться» / «Вы подписаны».
struct PodcastRow: Hashable, Identifiable {
    let id: String
    let title: String
    let author: String
    let artworkURL: URL
    let isSubscribed: Bool
}

/// Сообщение вместо списка: `message == nil` — загрузка.
struct StatusMessage: Hashable {
    let message: String?
    let showsRetry: Bool

    static let loading = StatusMessage(message: nil, showsRetry: false)
}

/// Готовое к показу состояние вкладки «Подкасты».
struct PodcastsState: Equatable {
    enum Segment: Hashable, CaseIterable {
        case catalog, subscriptions
    }

    enum Content: Equatable {
        /// Каталог не загружен (загрузка или ошибка с «Повторить»).
        case status(StatusMessage)
        case catalog([PodcastRow])
        /// Без подписок — `tiles` пусты, `episodes` — сообщение «Подпишитесь…».
        case subscriptions(tiles: [SubscriptionTile], episodes: EpisodesContent)
    }

    enum EpisodesContent: Equatable {
        case rows([EpisodeRow])
        case status(StatusMessage)
    }

    var segment: Segment
    /// Бейдж «Подписки N»; nil — новых нет, бейдж скрыт.
    var badge: Int?
    var content: Content
    var isRefreshing = false
}

/// Готовое к показу состояние экрана подкаста.
struct PodcastState: Equatable {
    struct Header: Hashable {
        let title: String
        let author: String
        let artworkURL: URL
        let isSubscribed: Bool
    }

    var header: Header
    var episodes: PodcastsState.EpisodesContent
    var isRefreshing = false
}
