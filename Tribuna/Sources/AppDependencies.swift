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
    /// Загрузки выпусков; одни и те же и для отладочных моков, кроме `-PodcastsMockData`.
    private(set) var downloads: EpisodeDownloads = Self.backgroundDownloads

    /// Единственная фоновая сессия загрузок: `Services.make` моки зовут несколько раз, поэтому не там.
    /// Статическая — `AppDelegate` передаёт ей события сессии и при запуске в фоне, без сцены.
    static let backgroundDownloads = BackgroundEpisodeDownloads.make()

    /// Единственный аккаунт и PostgREST таблиц пользователя (D31): по той же причине, что и загрузки, — не в `Services.make`.
    static let account = Services.makeAccount(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)

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
            (podcasts, episodes, subscriptions, progress, player, downloads) = mock
            return
        }
        #endif
        (matches, standings, bookmarks, reminders, stations, podcasts, episodes, subscriptions, progress) = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey)
        player = RadioPlayer(progress: progress, localFile: { Self.backgroundDownloads.localFile(for: $0) })
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

    init(state: PlaybackState) {
        subject = CurrentValueSubject(state)
    }

    var state: PlaybackState { subject.value }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }
    func play(_ item: PlaybackItem) { subject.value = PlaybackState(item: item, status: .playing, sleepTimerEndsAt: nil) }
    func togglePlayPause() { subject.value.status = subject.value.status == .playing ? .paused : .playing }
    func stop() { subject.value = PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil) }
    func setSleepTimer(minutes: Int?) { subject.value.sleepTimerEndsAt = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) } }
    func seek(to position: TimeInterval) {
        guard let duration = subject.value.duration else { return }
        subject.value.position = min(max(position, 0), duration)
    }
    func skip(by seconds: TimeInterval) { seek(to: (subject.value.position ?? 0) + seconds) }
    func setRate(_ rate: Float) { if subject.value.item?.isLive == false { subject.value.rate = rate } }
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
/// Вкладка «Подкасты» как в макете (`-PodcastsMockData`): подписки «Вне игры» (2 новых), «Шайба» (1 новый), «Разбор» (всё прослушано),
/// начатый «Итоги 11 тура». Подписки и позиция — в отдельном наборе UserDefaults, плеер без звука. Только в отладке.
/// `-PodcastPlayerMock` — в плеере «Превью 12 тура», 18:42 из 34:10, 1,25×, скачан (макет «Плеер»); `-OpenPlayer` — сразу открыть плеер.
/// `-PodcastsRealFeeds` — каталог из пяти подкастов миграции, ленты и плеер настоящие.
private struct MockPodcastsRepository: PodcastsRepository {
    let podcasts: [Podcast]

    func podcasts() async throws -> [Podcast] { podcasts }
}

private struct MockEpisodesRepository: EpisodesRepository {
    let feeds: [String: [Episode]]

    func episodes(for podcast: Podcast, forceRefresh: Bool) async throws -> [Episode] { feeds[podcast.id] ?? [] }
}

/// Загрузки в памяти: «Скачать» сразу даёт скачанный выпуск (48 МБ), файлов нет — плеер играет по сети.
private final class MockEpisodeDownloads: EpisodeDownloads {
    private let subject: CurrentValueSubject<[DownloadedEpisode], Never>
    var wifiOnly = true

    init(items: [DownloadedEpisode]) { subject = CurrentValueSubject(items) }

    var items: [DownloadedEpisode] { subject.value }
    var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { subject.eraseToAnyPublisher() }

    func download(_ episode: Episode, podcast: Podcast) {
        subject.value.removeAll { $0.id == episode.id }
        subject.value.insert(DownloadedEpisode(episode: episode, podcast: podcast, addedAt: Date(), state: .downloaded(bytes: 48_000_000), artworkFile: nil), at: 0)
    }

    func remove(_ id: EpisodeID) { subject.value.removeAll { $0.id == id } }
    func removeAll() { subject.value = [] }
    func localFile(for id: EpisodeID) -> URL? { nil }

    func usage() -> (bytes: Int64, count: Int) {
        subject.value.reduce((0, 0)) { total, item in
            if case let .downloaded(bytes) = item.state { (total.0 + bytes, total.1 + 1) } else { total }
        }
    }

    func availableCapacity() -> Int64? { 64_000_000_000 }
}

extension AppDependencies {
    /// `-PodcastsMockData` или `-PodcastsRealFeeds`: открыть вкладку «Подкасты».
    static var isPodcastsMock: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-PodcastsMockData") || arguments.contains("-PodcastsRealFeeds")
    }

    fileprivate static func podcastsMock()
        -> (PodcastsRepository, EpisodesRepository, SubscriptionsStore, ListeningProgressStore, AudioPlayer, EpisodeDownloads)? {
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
        let preview = episode("out", "preview", "Превью 12 тура: дерби на Энфилде", daysAgo: 0, minutes: 34 + 10.0 / 60)
        let results = episode("out", "results", "Итоги 11 тура", daysAgo: max(2.5, -daysToNov16), minutes: 40)
        let feeds = [
            "out": [preview,
                    episode("out", "transfers", "Трансферное окно: кого ждать", daysAgo: 2, minutes: 45), results],
            "puck": [episode("puck", "cup", "Кто заберёт Кубок Стэнли", daysAgo: 1, minutes: 51)],
            "review": [episode("review", "r1", "Разбор тура", daysAgo: 3, minutes: 30)],
            "tennis": [episode("tennis", "t1", "Итоги сезона", daysAgo: 5, minutes: 60)],
            "run": [episode("run", "m1", "Как пробежать первый марафон", daysAgo: 6, minutes: 42)],
        ]
        for id in ["out", "puck", "review"] { services.subscriptions.toggle(id) }
        services.progress.setPosition(28 * 60, for: results.id)
        services.progress.markFinished(EpisodeID(podcastID: "review", guid: "r1"))
        let player = arguments.contains("-PodcastPlayerMock")
            ? MockAudioPlayer(state: PlaybackState(item: .episode(preview, podcast: catalog[0]), status: .playing, sleepTimerEndsAt: nil,
                                                   position: 18 * 60 + 42, duration: 34 * 60 + 10, rate: 1.25))
            : MockAudioPlayer(playing: nil)
        // Загрузки как в макете: «Кто заберёт Кубок Стэнли» качается (60 %), «Итоги 11 тура» скачан.
        let cup = feeds["puck"]![0]
        var items = [
            DownloadedEpisode(episode: cup, podcast: catalog[1], addedAt: now, state: .downloading(progress: 0.6), artworkFile: nil),
            DownloadedEpisode(episode: results, podcast: catalog[0], addedAt: now.addingTimeInterval(-3600), state: .downloaded(bytes: 48_000_000), artworkFile: nil),
        ]
        // Плеер макета — «Скачан».
        if arguments.contains("-PodcastPlayerMock") {
            items.append(DownloadedEpisode(episode: preview, podcast: catalog[0], addedAt: now.addingTimeInterval(-7200),
                                           state: .downloaded(bytes: 33_000_000), artworkFile: nil))
        }
        let downloads = MockEpisodeDownloads(items: items)
        return (MockPodcastsRepository(podcasts: catalog), MockEpisodesRepository(feeds: feeds), services.subscriptions, services.progress, player, downloads)
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
    private static func realFeedsMock()
        -> (PodcastsRepository, EpisodesRepository, SubscriptionsStore, ListeningProgressStore, AudioPlayer, EpisodeDownloads) {
        let defaults = UserDefaults(suiteName: "PodcastsRealFeeds") ?? .standard
        let services = Services.make(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey, defaults: defaults)
        return (MockPodcastsRepository(podcasts: realCatalog), services.episodes, services.subscriptions, services.progress,
                RadioPlayer(progress: services.progress, localFile: { backgroundDownloads.localFile(for: $0) }), backgroundDownloads)
    }
}
#endif
