import CoreDomain
import Foundation

/// Чистые функции форматирования карточки матча.
enum MatchFormatter {
    /// Неизвестное значение — везде одно длинное тире.
    private static let unknown = "—"
    private static let weekdays = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    private static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "нояб", "дек"]
    /// Напоминание приходит за 15 минут до начала — позже его ставить незачем.
    static let reminderLead: TimeInterval = 15 * 60

    static func card(
        _ match: Match,
        standings: [StandingRow],
        isBookmarked: Bool,
        isReminderScheduled: Bool,
        now: Date,
        calendar: Calendar
    ) -> MatchState.Card {
        let isLive = match.status == .live || match.status == .paused
        let score = score(match)
        let status = statusText(match, now: now, calendar: calendar)
        let highlighted = Set([match.homeTeamID, match.awayTeamID].compactMap(\.self))
        let canRemind = match.status == .scheduled && match.kickoff.timeIntervalSince(now) > reminderLead
        return MatchState.Card(
            header: [match.competition.name, match.round].compactMap(\.self).joined(separator: " · "),
            emblemURL: match.competition.emblemURL,
            statusText: status,
            isLive: isLive,
            home: team(match.home),
            away: team(match.away),
            score: score,
            showsDelayNote: match.sport == .football && isLive,
            isBookmarked: isBookmarked,
            reminder: canRemind ? (isReminderScheduled ? .on : .off) : .hidden,
            standingsTitle: "ТАБЛИЦА \(match.competition.name.uppercased())",
            standings: standings.map {
                MatchState.Row(
                    id: $0.teamID,
                    position: String($0.position),
                    name: $0.team.name,
                    played: String($0.played),
                    points: String($0.points),
                    isHighlighted: highlighted.contains($0.teamID),
                    logoURL: $0.team.logoURL
                )
            },
            shareText: "\(match.home?.name ?? unknown) — \(match.away?.name ?? unknown), \(score.isEmpty ? shareWhen(status) : score) · "
                + [match.competition.name, match.round].compactMap(\.self).joined(separator: ", ")
        )
    }

    private static func statusText(_ match: Match, now: Date, calendar: Calendar) -> String {
        switch match.status {
        case .scheduled: kickoff(match.kickoff, now: now, calendar: calendar)
        case .live, .paused: "LIVE"
        case .finished: "Завершён"
        case .postponed: "Перенесён"
        case .cancelled: "Отменён"
        }
    }

    /// «18:00» сегодня, «Завтра, 18:00», иначе «Сб, 21 нояб · 18:00» — по дню в поясе календаря (D17).
    private static func kickoff(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = time(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Завтра, \(time)"
        }
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        return "\(weekdays[(parts.weekday ?? 1) - 1]), \(parts.day ?? 0) \(months[(parts.month ?? 1) - 1]) · \(time)"
    }

    /// В середине фразы «завтра» со строчной.
    private static func shareWhen(_ status: String) -> String {
        status.hasPrefix("Завтра") ? "з" + status.dropFirst() : status
    }

    /// «2 : 1»; пусто, пока счёта нет.
    private static func score(_ match: Match) -> String {
        guard let home = match.homeScore, let away = match.awayScore else { return "" }
        return "\(home) : \(away)"
    }

    private static func team(_ team: Team?) -> MatchState.TeamItem {
        MatchState.TeamItem(name: team?.name ?? unknown, abbreviation: team?.abbreviation, logoURL: team?.logoURL)
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
