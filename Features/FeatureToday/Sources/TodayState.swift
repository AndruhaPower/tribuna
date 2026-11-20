import CoreDomain
import Foundation

/// Готовое к показу состояние экрана «Сегодня»: контроллер ничего не форматирует.
struct TodayState: Equatable {
    struct DayItem: Hashable, Identifiable {
        /// Начало дня в поясе календаря.
        let id: Date
        let weekday: String
        let number: String
        let isSelected: Bool
    }

    struct TeamItem: Hashable {
        let name: String
        let abbreviation: String?
        var logoURL: URL? = nil
    }

    /// Крупная карточка «Моих событий».
    struct EventCard: Hashable, Identifiable {
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

    struct MatchRow: Hashable, Identifiable {
        let id: MatchID
        let leading: String
        let home: String
        let away: String
        let isBookmarked: Bool
        var homeLogoURL: URL? = nil
        var awayLogoURL: URL? = nil
    }

    struct Section: Equatable, Identifiable {
        /// Код турнира.
        let id: String
        let title: String
        let trailing: String
        var emblemURL: URL? = nil
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
