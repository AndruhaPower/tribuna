#if FEATURE_WIDGET
import CoreDomain
import Foundation

/// Виджет «Сегодня» (1.1, D40): что показать и когда обновить. Чистые функции — проверяются тестами.
public enum WidgetPlan {
    /// Общий контейнер приложения и виджета: приложение пишет сюда закладки, виджет читает.
    public static let appGroup = "group.com.tribuna.app"
    public static let bookmarksKey = "widget.bookmarks"
    /// Обновления: идёт матч — часто, иначе к началу ближайшего, но не реже раза в полчаса. Бюджет iOS ~40–70 в день.
    static let liveInterval: TimeInterval = 5 * 60
    static let idleInterval: TimeInterval = 30 * 60

    /// До `limit` матчей: сначала закладки; в группе — идущие и будущие раньше завершённых, затем по времени начала.
    public static func pick(_ matches: [Match], bookmarks: Set<MatchID>, limit: Int) -> [Match] {
        func rank(_ match: Match) -> (Int, Int, Date) {
            (bookmarks.contains(match.id) ? 0 : 1, isOver(match) ? 1 : 0, match.kickoff)
        }
        return Array(matches.sorted { rank($0) < rank($1) }.prefix(limit))
    }

    public static func nextRefresh(_ matches: [Match], now: Date) -> Date {
        if matches.contains(where: { $0.status == .live || $0.status == .paused }) { return now.addingTimeInterval(liveInterval) }
        let idle = now.addingTimeInterval(idleInterval)
        let nextKickoff = matches.map(\.kickoff).filter { $0 > now }.min()
        return min(nextKickoff ?? idle, idle)
    }

    private static func isOver(_ match: Match) -> Bool {
        [.finished, .postponed, .cancelled].contains(match.status)
    }
}

extension Services {
    /// Матчи местного дня `now` — для виджета, без аккаунта (каталоги читаются publishable-ключом).
    public static func todayMatches(supabaseURL: URL, supabaseKey: String, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async throws -> [Match] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return try await FootballRepository(client: catalogClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey))
            .matches(in: DateInterval(start: start, end: end))
    }
}
#endif
