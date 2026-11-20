import CoreDomain
import Foundation

/// Готовое к показу состояние карточки матча: контроллер ничего не форматирует.
struct MatchState: Equatable {
    struct TeamItem: Hashable {
        let name: String
        let abbreviation: String?
        var logoURL: URL? = nil
    }

    enum Reminder: Hashable {
        /// Матч начался, завершён, отменён/перенесён или стартует меньше чем через 15 минут.
        case hidden
        case off
        case on
    }

    /// Строка турнирной таблицы.
    struct Row: Hashable, Identifiable {
        /// id команды в источнике.
        let id: String
        let position: String
        let name: String
        let played: String
        let points: String
        /// Команда этого матча.
        let isHighlighted: Bool
        var logoURL: URL? = nil
    }

    struct Card: Hashable {
        /// «АПЛ · 12 тур».
        let header: String
        /// Значок турнира перед заголовком.
        var emblemURL: URL? = nil
        /// «LIVE», «22:00», «Завершён», «Перенесён», «Отменён».
        let statusText: String
        let isLive: Bool
        let home: TeamItem
        let away: TeamItem
        /// «2 : 1»; пусто, пока счёта нет.
        let score: String
        /// Подпись «Счёт обновляется с небольшой задержкой».
        let showsDelayNote: Bool
        let isBookmarked: Bool
        let reminder: Reminder
        /// «ТАБЛИЦА АПЛ».
        let standingsTitle: String
        /// Пусто — блок таблицы скрыт.
        let standings: [Row]
        /// «Ливерпуль — Арсенал, 2 : 1 · АПЛ, 12 тур».
        let shareText: String
    }

    enum Content: Equatable {
        case loading
        case loaded(Card)
        case notFound
        case error(message: String)
    }

    var content: Content
}
