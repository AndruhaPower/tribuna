import Combine
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

#if DEBUG
/// Каталог и плеер как в макете «Эфир» (`-RadioMockData`): играет «Стадион FM». Только в отладке, до сборки плеера в приложении.
private struct MockStationsRepository: StationsRepository {
    func stations() async throws -> [Station] {
        func station(_ id: String, _ name: String, _ genres: Set<StationGenre>, _ subtitle: String, _ featured: Int?) -> Station {
            Station(id: id, name: name, streamURL: URL(string: "https://example.com/\(id)")!, country: "Россия",
                    bitrate: 128, genres: genres, subtitle: subtitle, featuredOrder: featured)
        }
        return [
            station("golos", "Голос матча", [.sport, .football], "Футбол · репортажи", 1),
            station("hockey", "Хоккей Радио", [.sport, .hockey], "Хоккей · ток-шоу", 2),
            station("news", "Спорт Новости 24", [.sport, .news], "Новости · каждые 30 мин", 3),
            station("stadion", "Стадион FM", [.sport, .football], "Футбол · эфир", nil),
        ]
    }
}

/// Плеер без звука: только меняет состояние.
@MainActor
private final class MockAudioPlayer: AudioPlayer {
    private let subject: CurrentValueSubject<PlaybackState, Never>

    init(playing station: Station) {
        subject = CurrentValueSubject(PlaybackState(item: station, status: .playing, sleepTimerEndsAt: nil))
    }

    var state: PlaybackState { subject.value }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }
    func play(_ station: Station) { subject.value = PlaybackState(item: station, status: .playing, sleepTimerEndsAt: nil) }
    func togglePlayPause() { subject.value.status = subject.value.status == .playing ? .paused : .playing }
    func stop() { subject.value = PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil) }
    func setSleepTimer(minutes: Int?) {}
}

extension AppDependencies {
    /// `-RadioMockData`: «Эфир» на данных макета вместо заглушки вкладки.
    static func radioMock() -> (stations: StationsRepository, player: AudioPlayer)? {
        guard ProcessInfo.processInfo.arguments.contains("-RadioMockData") else { return nil }
        let stadion = Station(id: "stadion", name: "Стадион FM", streamURL: URL(string: "https://example.com/stadion")!,
                              country: "Россия", bitrate: 128, genres: [.sport, .football], subtitle: "Футбол · эфир", featuredOrder: nil)
        return (MockStationsRepository(), MockAudioPlayer(playing: stadion))
    }
}
#endif
