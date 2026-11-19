import CoreDomain
import CoreRepositories
import Foundation

/// Источники данных приложения; создаются один раз и раздаются фичам.
@MainActor
struct AppDependencies {
    let matches: MatchesRepository
    let standings: StandingsRepository
    let bookmarks: BookmarksStore
    let reminders: RemindersStore

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TodayMockData") {
            (matches, standings, bookmarks, reminders) = Self.todayMockData()
            return
        }
        #endif
        (matches, standings, bookmarks, reminders) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
    }
}

#if DEBUG
/// Данные как в макете «Сегодня» — для сверки вёрстки (`-TodayMockData` в аргументах запуска). Только в отладке.
private struct MockMatchesRepository: MatchesRepository {
    let matches: [Match]

    func matches(in interval: DateInterval) async throws -> [Match] { matches }

    func match(id: MatchID) async throws -> Match? { matches.first { $0.id == id } }
}

extension AppDependencies {
    private static func todayMockData() -> (MatchesRepository, StandingsRepository, BookmarksStore, RemindersStore) {
        let day = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        func at(_ hour: Int) -> Date { day.addingTimeInterval(TimeInterval(hour * 3600)) }
        func team(_ name: String, _ abbreviation: String) -> Team { Team(name: name, abbreviation: abbreviation) }
        let pl = Competition(code: "PL", name: "АПЛ")
        let cl = Competition(code: "CL", name: "Лига чемпионов")
        let nhl = Competition(code: "NHL", name: "НХЛ")
        let liverpool = MatchID(rawValue: "football:mock-1")
        let matches = [
            Match(id: liverpool, sport: .football, competition: pl, kickoff: at(20), status: .live,
                  home: team("Ливерпуль", "LIV"), away: team("Арсенал", "ARS"), homeScore: 2, awayScore: 1, round: "12 тур", homeTeamID: nil, awayTeamID: nil),
            Match(id: MatchID(rawValue: "football:mock-2"), sport: .football, competition: cl, kickoff: at(22), status: .scheduled,
                  home: team("Реал Мадрид", "RMA"), away: team("Бавария", "BAY"), homeScore: nil, awayScore: nil, round: nil, homeTeamID: nil, awayTeamID: nil),
            Match(id: MatchID(rawValue: "football:mock-3"), sport: .football, competition: cl, kickoff: at(22), status: .scheduled,
                  home: team("Интер", "INT"), away: team("ПСЖ", "PSG"), homeScore: nil, awayScore: nil, round: nil, homeTeamID: nil, awayTeamID: nil),
            Match(id: MatchID(rawValue: "hockey:mock-4"), sport: .hockey, competition: nhl, kickoff: at(3), status: .scheduled,
                  home: team("Rangers", "NYR"), away: team("Bruins", "BOS"), homeScore: nil, awayScore: nil, round: nil, homeTeamID: nil, awayTeamID: nil),
        ]
        // Закладки — в отдельном наборе UserDefaults, чтобы не трогать настоящие.
        let defaults = UserDefaults(suiteName: "TodayMockData") ?? .standard
        let services = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey, defaults: defaults)
        if !services.bookmarks.bookmarks.contains(liverpool) { services.bookmarks.toggle(liverpool) }
        return (MockMatchesRepository(matches: matches), services.standings, services.bookmarks, services.reminders)
    }
}
#endif
