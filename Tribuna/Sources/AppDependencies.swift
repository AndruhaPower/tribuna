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
    let stations: StationsRepository

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-TodayMockData") || arguments.contains("-MatchMockData") {
            (matches, standings, bookmarks, reminders, stations) = Self.todayMockData()
            return
        }
        #endif
        (matches, standings, bookmarks, reminders, stations) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
    }
}

#if DEBUG
/// Данные как в макетах «Сегодня» и «Карточка матча» — для сверки вёрстки. Только в отладке.
/// `-TodayMockData` — «Сегодня»; `-MatchMockData` — то же и сразу открытая карточка «Ливерпуль — Арсенал».
private struct MockMatchesRepository: MatchesRepository {
    let matches: [Match]

    func matches(in interval: DateInterval) async throws -> [Match] { matches }

    func match(id: MatchID) async throws -> Match? { matches.first { $0.id == id } }
}

private struct MockStandingsRepository: StandingsRepository {
    func standings(competitionCode: String) async throws -> [StandingRow] {
        guard competitionCode == "PL" else { return [] }
        return [("64", "Ливерпуль", 27), ("65", "Манчестер Сити", 25), ("57", "Арсенал", 23), ("61", "Челси", 21)]
            .enumerated()
            .map { StandingRow(position: $0 + 1, team: Team(name: $1.1, abbreviation: nil), teamID: $1.0, played: 11, points: $1.2) }
    }
}

extension AppDependencies {
    static let mockMatchID = MatchID(rawValue: "football:mock-1")

    /// Матч, который открыть сразу при запуске (`-MatchMockData`).
    static var mockMatchOnLaunch: MatchID? {
        ProcessInfo.processInfo.arguments.contains("-MatchMockData") ? mockMatchID : nil
    }

    private static func todayMockData() -> (MatchesRepository, StandingsRepository, BookmarksStore, RemindersStore, StationsRepository) {
        let day = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        func at(_ hour: Int) -> Date { day.addingTimeInterval(TimeInterval(hour * 3600)) }
        func team(_ name: String, _ abbreviation: String) -> Team { Team(name: name, abbreviation: abbreviation) }
        let pl = Competition(code: "PL", name: "АПЛ")
        let cl = Competition(code: "CL", name: "Лига чемпионов")
        let nhl = Competition(code: "NHL", name: "НХЛ")
        let liverpool = mockMatchID
        let matches = [
            Match(id: liverpool, sport: .football, competition: pl, kickoff: at(20), status: .live,
                  home: team("Ливерпуль", "LIV"), away: team("Арсенал", "ARS"), homeScore: 2, awayScore: 1, round: "12 тур", homeTeamID: "64", awayTeamID: "57"),
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
        return (MockMatchesRepository(matches: matches), MockStandingsRepository(), services.bookmarks, services.reminders, services.stations)
    }
}
#endif
