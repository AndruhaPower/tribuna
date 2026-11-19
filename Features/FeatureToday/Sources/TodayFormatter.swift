import CoreDomain
import Foundation

/// Чистые функции форматирования экрана «Сегодня».
enum TodayFormatter {
    static let sectionOrder = ["CL", "PL", "PD", "BL1", "SA", "FL1", "NHL"]
    private static let weekdays = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    /// Неизвестное значение — везде одно длинное тире.
    private static let unknown = "—"

    /// Полоса дней: от вчера до +6.
    static func days(today: Date, selected: Date, calendar: Calendar) -> [TodayState.DayItem] {
        let start = calendar.startOfDay(for: today)
        return (-1...6).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { day in
            TodayState.DayItem(
                id: day,
                weekday: weekday(day, calendar: calendar),
                number: String(calendar.component(.day, from: day)),
                isSelected: calendar.isDate(day, inSameDayAs: selected)
            )
        }
    }

    static func content(matches: [Match], bookmarks: Set<MatchID>, day: Date, calendar: Calendar) -> TodayState.Content {
        guard !matches.isEmpty else { return .empty }
        let sorted = matches.sorted { $0.kickoff < $1.kickoff }
        let events = sorted.filter { bookmarks.contains($0.id) }.map { eventCard($0, calendar: calendar) }
        let groups = Dictionary(grouping: sorted, by: \.competition.code)
        let sections = groups.keys.sorted(by: sectionPrecedes).compactMap { code -> TodayState.Section? in
            guard let group = groups[code], let competition = group.first?.competition else { return nil }
            return TodayState.Section(
                id: code,
                title: competition.name.uppercased(),
                trailing: trailing(code: code, matches: group, day: day, calendar: calendar),
                rows: group.map { row($0, isBookmarked: bookmarks.contains($0.id), calendar: calendar) }
            )
        }
        return .loaded(events: events, sections: sections)
    }

    static func matchCount(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        let word = if (11...14).contains(mod100) {
            "матчей"
        } else if mod10 == 1 {
            "матч"
        } else if (2...4).contains(mod10) {
            "матча"
        } else {
            "матчей"
        }
        return "\(count) \(word)"
    }

    static func leading(_ match: Match, calendar: Calendar) -> String {
        switch match.status {
        case .scheduled: time(match.kickoff, calendar: calendar)
        case .live, .paused: "LIVE \(score(match))"
        case .finished: score(match)
        case .postponed: "Перенесён"
        case .cancelled: "Отменён"
        }
    }

    /// «Ливерпуль — Арсенал».
    static func title(_ match: Match) -> String {
        "\(match.home?.name ?? unknown) — \(match.away?.name ?? unknown)"
    }

    private static func sectionPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = sectionOrder.firstIndex(of: lhs) ?? sectionOrder.count
        let right = sectionOrder.firstIndex(of: rhs) ?? sectionOrder.count
        return (left, lhs) < (right, rhs)
    }

    private static func trailing(code: String, matches: [Match], day: Date, calendar: Calendar) -> String {
        let isNight = matches.allSatisfy { calendar.component(.hour, from: $0.kickoff) < 8 }
        return code == "NHL" && isNight ? "ночь на \(weekday(day, calendar: calendar).lowercased())" : matchCount(matches.count)
    }

    private static func row(_ match: Match, isBookmarked: Bool, calendar: Calendar) -> TodayState.MatchRow {
        TodayState.MatchRow(
            id: match.id,
            leading: leading(match, calendar: calendar),
            home: match.home?.name ?? unknown,
            away: match.away?.name ?? unknown,
            isBookmarked: isBookmarked
        )
    }

    private static func eventCard(_ match: Match, calendar: Calendar) -> TodayState.EventCard {
        TodayState.EventCard(
            id: match.id,
            header: [match.competition.name, match.round].compactMap(\.self).joined(separator: " · "),
            isLive: match.status == .live || match.status == .paused,
            statusText: statusText(match, calendar: calendar),
            home: team(match.home),
            away: team(match.away),
            homeScore: match.homeScore.map(String.init) ?? "",
            awayScore: match.awayScore.map(String.init) ?? ""
        )
    }

    private static func statusText(_ match: Match, calendar: Calendar) -> String {
        switch match.status {
        case .scheduled: time(match.kickoff, calendar: calendar)
        case .live, .paused: "LIVE"
        case .finished: "Завершён"
        case .postponed: "Перенесён"
        case .cancelled: "Отменён"
        }
    }

    private static func team(_ team: Team?) -> TodayState.TeamItem {
        TodayState.TeamItem(name: team?.name ?? unknown, abbreviation: team?.abbreviation)
    }

    private static func score(_ match: Match) -> String {
        "\(match.homeScore.map(String.init) ?? unknown) : \(match.awayScore.map(String.init) ?? unknown)"
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        weekdays[calendar.component(.weekday, from: date) - 1]
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
