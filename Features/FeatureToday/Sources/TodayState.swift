import CoreDomain
import Foundation

/// Готовое к показу состояние экрана «Сегодня»: контроллер ничего не форматирует.
struct TodayState: Equatable {
    struct DayItem: Equatable, Identifiable {
        /// Начало дня в поясе календаря.
        let id: Date
        let weekday: String
        let number: String
        let isSelected: Bool
    }

    struct TeamItem: Equatable {
        let name: String
        let abbreviation: String?
    }

    /// Крупная карточка «Моих событий».
    struct EventCard: Equatable, Identifiable {
        let id: MatchID
        let header: String
        let isLive: Bool
        /// «LIVE», «22:00», «Завершён», «Перенесён», «Отменён».
        let statusText: String
        let home: TeamItem
        let away: TeamItem
        /// Пусто, пока матч не начался.
        let homeScore: String
        let awayScore: String
    }

    struct MatchRow: Equatable, Identifiable {
        let id: MatchID
        let leading: String
        let home: String
        let away: String
        let isBookmarked: Bool
    }

    struct Section: Equatable, Identifiable {
        /// Код турнира.
        let id: String
        let title: String
        let trailing: String
        let rows: [MatchRow]
    }

    enum Content: Equatable {
        case loading
        case loaded(events: [EventCard], sections: [Section])
        case empty
        case error(message: String)
    }

    var days: [DayItem]
    var content: Content
    /// Идёт запрос, начатый pull-to-refresh.
    var isRefreshing = false
}
