import Combine
import CoreDomain
import CorePlayback
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
    let podcasts: PodcastsRepository
    let episodes: EpisodesRepository
    let subscriptions: SubscriptionsStore
    let progress: ListeningProgressStore
    /// Единственный плеер приложения (D15): «Эфир», мини-плеер и плеер подписаны на него.
    let player: AudioPlayer

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-TodayMockData") || arguments.contains("-MatchMockData") {
            (matches, standings, bookmarks, reminders, stations) = Self.todayMockData()
            (_, _, _, _, _, podcasts, episodes, subscriptions, progress) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
            // С `-RadioMockData` — ещё и мини-плеер со «Стадион FM», как на макете «Сегодня».
            player = Self.radioMock()?.player ?? RadioPlayer()
            return
        }
        if let radio = Self.radioMock() {
            (matches, standings, bookmarks, reminders, _, podcasts, episodes, subscriptions, progress) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
            (stations, player) = radio
            return
        }
        if let mock = Self.podcastsMock() {
            (matches, standings, bookmarks, reminders, stations, _, _, _, _) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
            (podcasts, episodes, subscriptions, progress, player) = mock
            return
        }
        #endif
        (matches, standings, bookmarks, reminders, stations, podcasts, episodes, subscriptions, progress) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
        player = RadioPlayer(progress: progress)
        #if DEBUG
        Self.debugEpisode(player: player, episodes: episodes)
        #endif
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
/// Каталог и плеер как в макете «Эфир» (`-RadioMockData`): играет «Стадион FM». Только в отладке.
/// `-RadioRealPlayer` — вместо фейка настоящий `RadioPlayer`, сразу подключается к потоку «Вести FM» из каталога.
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

    init(playing station: Station?) {
        subject = CurrentValueSubject(PlaybackState(item: station.map(PlaybackItem.station), status: station == nil ? .idle : .playing, sleepTimerEndsAt: nil))
    }

    var state: PlaybackState { subject.value }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }
    func play(_ item: PlaybackItem) { subject.value = PlaybackState(item: item, status: .playing, sleepTimerEndsAt: nil) }
    func togglePlayPause() { subject.value.status = subject.value.status == .playing ? .paused : .playing }
    func stop() { subject.value = PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil) }
    func setSleepTimer(minutes: Int?) { subject.value.sleepTimerEndsAt = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) } }
    func seek(to position: TimeInterval) {}
    func skip(by seconds: TimeInterval) {}
    func setRate(_ rate: Float) {}
}

extension AppDependencies {
    /// `-RadioMockData`: «Эфир» на данных макета, мини-плеер со «Стадион FM».
    static var isRadioMock: Bool { ProcessInfo.processInfo.arguments.contains("-RadioMockData") }

    fileprivate static func radioMock() -> (stations: StationsRepository, player: AudioPlayer)? {
        guard isRadioMock else { return nil }
        guard ProcessInfo.processInfo.arguments.contains("-RadioRealPlayer") else {
            let stadion = Station(id: "stadion", name: "Стадион FM", streamURL: URL(string: "https://example.com/stadion")!,
                                  country: "Россия", bitrate: 128, genres: [.sport, .football], subtitle: "Футбол · эфир", featuredOrder: nil)
            return (MockStationsRepository(), MockAudioPlayer(playing: stadion))
        }
        let vesti = Station(id: "vesti-fm", name: "Вести FM", streamURL: URL(string: "https://icecast-vgtrk.cdnvideo.ru/vestifm_mp3_192kbps")!,
                            country: "Россия", bitrate: 192, genres: [.news], subtitle: "Новости · разговорное радио", featuredOrder: nil)
        let player = RadioPlayer()
        player.play(vesti)
        return (MockStationsRepository(), player)
    }
}
#endif

#if DEBUG
extension AppDependencies {
    /// `-PodcastEpisodeDebug` — сразу играет последний выпуск «Дерби» (лента из каталога) и раз в 5 с печатает позицию;
    /// `-PodcastSeek 600` — ещё и перематывает туда через 5 с. Проверка продолжения с места, пока нет экрана подкастов.
    fileprivate static func debugEpisode(player: AudioPlayer, episodes: EpisodesRepository) {
        guard ProcessInfo.processInfo.arguments.contains("-PodcastEpisodeDebug") else { return }
        let podcast = Podcast(id: "debug", title: "Отладка", author: "", feedURL: URL(string: "https://podster.fm/rss.xml?pid=100138")!,
                              artworkURL: URL(string: "https://example.com/a.jpg")!, featuredOrder: nil)
        let seek = UserDefaults.standard.double(forKey: "PodcastSeek")
        Task { @MainActor in
            guard let episode = try? await episodes.episodes(for: podcast, forceRefresh: false).first else { return print("[PodcastDebug] нет ленты") }
            player.play(.episode(episode, podcast: podcast))
            for tick in 1... {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if tick == 1, seek > 0 { player.seek(to: seek) }
                print("[PodcastDebug] \(player.state.status) position=\(player.state.position ?? -1) duration=\(player.state.duration ?? -1)")
            }
        }
    }
}
#endif

#if DEBUG
/// Вкладка «Подкасты» как в макете (`-PodcastsMockData`): подписки «Вне игры» (2 новых), «Шайба» (1 новый), «Разбор» (всё прослушано),
/// начатый «Итоги 11 тура». Подписки и позиция — в отдельном наборе UserDefaults, плеер без звука. Только в отладке.
/// `-PodcastsRealFeeds` — каталог из пяти подкастов миграции (таблицы `podcasts` на `tribuna_db` ещё нет), ленты и плеер настоящие.
private struct MockPodcastsRepository: PodcastsRepository {
    let podcasts: [Podcast]

    func podcasts() async throws -> [Podcast] { podcasts }
}

private struct MockEpisodesRepository: EpisodesRepository {
    let feeds: [String: [Episode]]

    func episodes(for podcast: Podcast, forceRefresh: Bool) async throws -> [Episode] { feeds[podcast.id] ?? [] }
}

extension AppDependencies {
    /// `-PodcastsMockData` или `-PodcastsRealFeeds`: открыть вкладку «Подкасты».
    static var isPodcastsMock: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-PodcastsMockData") || arguments.contains("-PodcastsRealFeeds")
    }

    fileprivate static func podcastsMock()
        -> (PodcastsRepository, EpisodesRepository, SubscriptionsStore, ListeningProgressStore, AudioPlayer)? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PodcastsRealFeeds") { return realFeedsMock() }
        guard arguments.contains("-PodcastsMockData") else { return nil }
        let defaults = UserDefaults(suiteName: "PodcastsMockData") ?? .standard
        defaults.removePersistentDomain(forName: "PodcastsMockData")
        let services = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey, defaults: defaults)
        // Обложки нет — плитки и строки остаются плашками `surfaceRaised`, как в макете.
        func podcast(_ id: String, _ title: String, _ author: String, _ order: Int) -> Podcast {
            Podcast(id: id, title: title, author: author, feedURL: URL(string: "https://example.com/\(id).xml")!,
                    artworkURL: URL(string: "https://example.invalid/\(id).jpg")!, featuredOrder: order)
        }
        let catalog = [
            podcast("out", "Вне игры", "Tribuna", 1), podcast("puck", "Шайба", "Хоккейный подкаст", 2),
            podcast("review", "Разбор", "Футбол без воды", 3), podcast("tennis", "Больше, чем теннис", "Теннисный клуб", 4),
            podcast("run", "Бегущий город", "Про бег и марафоны", 5),
        ]
        let now = Date()
        func episode(_ podcast: String, _ guid: String, _ title: String, daysAgo: Double, minutes: Double) -> Episode {
            Episode(id: EpisodeID(podcastID: podcast, guid: guid), podcastID: podcast, title: title,
                    publishedAt: now.addingTimeInterval(-daysAgo * 86400 - 60), duration: minutes * 60,
                    audioURL: URL(string: "https://example.com/\(guid).mp3")!, artworkURL: nil, link: nil)
        }
        let calendar = Calendar.autoupdatingCurrent
        let daysToNov16 = Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                         to: calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!).day ?? 0)
        let results = episode("out", "results", "Итоги 11 тура", daysAgo: max(2.5, -daysToNov16), minutes: 40)
        let feeds = [
            "out": [episode("out", "preview", "Превью 12 тура: дерби на Энфилде", daysAgo: 0, minutes: 34),
                    episode("out", "transfers", "Трансферное окно: кого ждать", daysAgo: 2, minutes: 45), results],
            "puck": [episode("puck", "cup", "Кто заберёт Кубок Стэнли", daysAgo: 1, minutes: 51)],
            "review": [episode("review", "r1", "Разбор тура", daysAgo: 3, minutes: 30)],
            "tennis": [episode("tennis", "t1", "Итоги сезона", daysAgo: 5, minutes: 60)],
            "run": [episode("run", "m1", "Как пробежать первый марафон", daysAgo: 6, minutes: 42)],
        ]
        for id in ["out", "puck", "review"] { services.subscriptions.toggle(id) }
        services.progress.setPosition(28 * 60, for: results.id)
        services.progress.markFinished(EpisodeID(podcastID: "review", guid: "r1"))
        return (MockPodcastsRepository(podcasts: catalog), MockEpisodesRepository(feeds: feeds), services.subscriptions, services.progress, MockAudioPlayer(playing: nil))
    }

    /// Пять подкастов из начального списка миграции `20261120100000_podcasts.sql` — пока таблицы нет на `tribuna_db`.
    private static var realCatalog: [Podcast] {
        [
            Podcast(id: "skvoz-sport", title: "Сквозь Спорт", author: "Алексей Бибиков", feedURL: URL(string: "https://podster.fm/rss.xml?pid=100138")!,
                    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/ae/fe/42/aefe420e-f011-e07e-5991-815550cbdae5/mza_16765462091896871357.jpg/600x600bb.jpg")!, featuredOrder: 1),
            Podcast(id: "kp-sport-news", title: "Новости спорта", author: "Радио «Комсомольская правда»", feedURL: URL(string: "https://cloud.mave.digital/36130")!,
                    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/69/f4/37/69f437a4-6199-6ff6-faec-c1ed59c041ed/mza_11842677910032958963.jpg/600x600bb.jpg")!, featuredOrder: 2),
            Podcast(id: "four-four-two", title: "4-4-2", author: "Фёдор Замыцкий", feedURL: URL(string: "https://cloud.mave.digital/32729")!,
                    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/f7/84/79/f7847917-4e5d-e619-9488-05c7899dc892/mza_3324083100343931127.jpg/600x600bb.jpg")!, featuredOrder: 8),
            Podcast(id: "shaibovorot", title: "Шайбоворот Ткачева", author: "Александр Ткачев", feedURL: URL(string: "https://cloud.mave.digital/54729")!,
                    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/c6/dd/0c/c6dd0c2b-174a-5e10-0046-2642f7e7b1c5/mza_17234498207233401191.jpg/600x600bb.jpg")!, featuredOrder: 13),
            Podcast(id: "okko-tennis", title: "Выход к сетке", author: "Okko Tennis", feedURL: URL(string: "https://cloud.mave.digital/36633")!,
                    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/f7/01/a3/f701a339-2042-3b9c-e403-9c421e9fe320/mza_2192722762668020214.jpg/600x600bb.jpg")!, featuredOrder: 14),
        ]
    }

    /// Каталог — пять настоящих лент из начального списка (D27), выпуски и плеер настоящие; подписки и позиция — отдельный набор UserDefaults.
    private static func realFeedsMock() -> (PodcastsRepository, EpisodesRepository, SubscriptionsStore, ListeningProgressStore, AudioPlayer) {
        let defaults = UserDefaults(suiteName: "PodcastsRealFeeds") ?? .standard
        let services = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey, defaults: defaults)
        return (MockPodcastsRepository(podcasts: realCatalog), services.episodes, services.subscriptions, services.progress,
                RadioPlayer(progress: services.progress))
    }
}
#endif
