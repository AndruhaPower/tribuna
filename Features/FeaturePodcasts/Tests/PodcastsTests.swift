import CoreDomain
import Foundation
import Testing
@testable import FeaturePodcasts

struct PodcastsFormatterTests {
    let subscribedAt = testNow.addingTimeInterval(-days(30))

    @Test func newIsNotStartedAndWithinWeekBeforeSubscription() {
        let fresh = episode("a", "1", ago: days(1))
        let boundary = Episode(
            id: EpisodeID(podcastID: "a", guid: "b"), podcastID: "a", title: "", publishedAt: subscribedAt.addingTimeInterval(-days(7)),
            duration: nil, audioURL: URL(string: "https://example.com/b.mp3")!, artworkURL: nil, link: nil
        )
        let tooOld = episode("a", "2", ago: days(38))
        let started = episode("a", "3", ago: days(2))
        let finished = episode("a", "4", ago: days(3))
        let progress = [
            started.id: ListeningProgress(position: 120, isFinished: false),
            finished.id: ListeningProgress(position: 0, isFinished: true),
        ]

        #expect(PodcastsFormatter.isNew(fresh, subscribedAt: subscribedAt, progress: progress))
        #expect(PodcastsFormatter.isNew(boundary, subscribedAt: subscribedAt, progress: progress))
        #expect(!PodcastsFormatter.isNew(tooOld, subscribedAt: subscribedAt, progress: progress))
        #expect(!PodcastsFormatter.isNew(started, subscribedAt: subscribedAt, progress: progress))
        #expect(!PodcastsFormatter.isNew(finished, subscribedAt: subscribedAt, progress: progress))
        #expect(PodcastsFormatter.isInProgress(started, progress: progress))
        #expect(!PodcastsFormatter.isInProgress(finished, progress: progress))
        #expect(!PodcastsFormatter.isInProgress(fresh, progress: progress))
    }

    @Test func pluralsOfNew() {
        let labels = [0, 1, 2, 4, 5, 11, 12, 21, 22, 111].map(PodcastsFormatter.newLabel)
        #expect(labels == [
            "Всё прослушано", "1 новый", "2 новых", "4 новых", "5 новых", "11 новых", "12 новых", "21 новый", "22 новых", "111 новых",
        ])
    }

    @Test func subtitleWithDayDurationAndRemaining() {
        let calendar = testCalendar
        let today = episode("a", "1", ago: 3600, minutes: 34 + 10.0 / 60)
        let yesterday = episode("a", "2", ago: days(1), minutes: 51)
        let older = episode("a", "3", ago: days(4), minutes: 40)
        let lastYear = episode("a", "4", ago: days(400), minutes: 75)
        let noDuration = episode("a", "5", ago: days(4), minutes: nil)

        func subtitle(_ episode: Episode, _ progress: ListeningProgress? = nil) -> String {
            PodcastsFormatter.subtitle(episode, progress: progress, now: testNow, calendar: calendar)
        }
        #expect(subtitle(today) == "Сегодня · 34 мин")
        #expect(subtitle(yesterday) == "Вчера · 51 мин")
        #expect(subtitle(older, ListeningProgress(position: 28 * 60, isFinished: false)) == "16 нояб · осталось 12 мин")
        #expect(subtitle(older, ListeningProgress(position: 0, isFinished: true)) == "16 нояб · прослушано")
        #expect(subtitle(lastYear) == "16 окт 2025 · 1 ч 15 мин")
        #expect(subtitle(noDuration) == "16 нояб")
        #expect(subtitle(older, ListeningProgress(position: 40 * 60 - 5, isFinished: false)) == "16 нояб · осталось 1 мин")
    }
}

@MainActor
struct PodcastsViewModelTests {
    let outOfPlay = podcast("out", "Вне игры", order: 1)
    let puck = podcast("puck", "Шайба", order: 2)
    let review = podcast("review", "Разбор", order: 3)
    let tennis = podcast("tennis", "Теннис", order: 4)

    var catalog: [Podcast] { [outOfPlay, puck, review, tennis] }

    /// Как в макете: «Вне игры» — 2 новых и один начатый, «Шайба» — 1 новый, «Разбор» — всё прослушано.
    var feeds: [String: [Episode]] {
        [
            "out": [
                episode("out", "preview", "Превью 12 тура", ago: 3600),
                episode("out", "transfer", "Трансферы", ago: days(2)),
                episode("out", "results", "Итоги 11 тура", ago: days(4), minutes: 40),
                episode("out", "old", "Старый", ago: days(60)),
            ],
            "puck": [episode("puck", "cup", "Кто заберёт Кубок Стэнли", ago: days(1), minutes: 51)],
            "review": [episode("review", "r1", ago: days(3))],
            "tennis": [episode("tennis", "t1", ago: days(1))],
        ]
    }

    var subscriptions: [String: Date] {
        ["out": testNow.addingTimeInterval(-days(30)), "puck": testNow.addingTimeInterval(-days(10)), "review": testNow.addingTimeInterval(-days(5))]
    }

    var progress: [EpisodeID: ListeningProgress] {
        [
            EpisodeID(podcastID: "out", guid: "results"): ListeningProgress(position: 28 * 60, isFinished: false),
            EpisodeID(podcastID: "review", guid: "r1"): ListeningProgress(position: 0, isFinished: true),
        ]
    }

    struct Setup {
        let viewModel: PodcastsViewModel
        let podcasts: FakePodcastsRepository
        let episodes: FakeEpisodesRepository
        let subscriptions: FakeSubscriptionsStore
        let progress: FakeProgressStore
        let player: FakeAudioPlayer
        let downloads: FakeDownloads
    }

    func make(
        subscriptions: [String: Date]? = nil,
        feeds: [String: [Episode]]? = nil,
        downloads: [DownloadedEpisode] = [],
        onOpenPodcast: @escaping (Podcast) -> Void = { _ in },
        onOpenPlayer: @escaping () -> Void = {}
    ) -> Setup {
        let podcasts = FakePodcastsRepository(catalog)
        let episodes = FakeEpisodesRepository(feeds ?? self.feeds)
        let store = FakeSubscriptionsStore(subscriptions ?? self.subscriptions)
        let progress = FakeProgressStore(self.progress)
        let player = FakeAudioPlayer()
        let fakeDownloads = FakeDownloads(downloads)
        let viewModel = PodcastsViewModel(
            podcasts: podcasts, episodes: episodes, subscriptions: store, progress: progress, player: player, downloads: fakeDownloads,
            onOpenPodcast: onOpenPodcast, onOpenPlayer: onOpenPlayer, now: { testNow }, calendar: testCalendar
        )
        return Setup(viewModel: viewModel, podcasts: podcasts, episodes: episodes, subscriptions: store, progress: progress, player: player, downloads: fakeDownloads)
    }

    func appear(_ viewModel: PodcastsViewModel) async {
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
    }

    func subscriptionsContent(_ viewModel: PodcastsViewModel) -> (tiles: [SubscriptionTile], episodes: PodcastsState.EpisodesContent)? {
        if case let .subscriptions(tiles, episodes) = viewModel.state.content { return (tiles, episodes) }
        return nil
    }

    func rows(_ viewModel: PodcastsViewModel) -> [EpisodeRow] {
        if case let .rows(rows) = subscriptionsContent(viewModel)?.episodes { return rows }
        return []
    }

    func catalogRows(_ viewModel: PodcastsViewModel) -> [PodcastRow] {
        if case let .catalog(rows) = viewModel.state.content { return rows }
        return []
    }

    @Test func defaultSegmentIsSubscriptionsWhenSubscribed() {
        #expect(make().viewModel.state.segment == .subscriptions)
        #expect(make(subscriptions: [:]).viewModel.state.segment == .catalog)
        #expect(make().viewModel.state.content == .status(.loading))
    }

    @Test func tilesBadgeAndListAgree() async throws {
        let setup = make()
        await appear(setup.viewModel)

        let content = try #require(subscriptionsContent(setup.viewModel))
        #expect(content.tiles.map(\.title) == ["Вне игры", "Шайба", "Разбор"])
        #expect(content.tiles.map(\.subtitle) == ["2 новых", "1 новый", "Всё прослушано"])
        #expect(setup.viewModel.state.badge == 3)
        let rows = rows(setup.viewModel)
        // Новые и начатый вместе, по дате; «Вне игры» в списке ровно 2 новых, как на плитке.
        #expect(rows.map(\.title) == ["Превью 12 тура", "Кто заберёт Кубок Стэнли", "Трансферы", "Итоги 11 тура"])
        #expect(rows.filter(\.isNew).count == setup.viewModel.state.badge)
        #expect(rows.map(\.caption) == ["● Новый · Вне игры", "● Новый · Шайба", "● Новый · Вне игры", "Вне игры"])
        #expect(rows.map(\.subtitle) == ["Сегодня · 34 мин", "Вчера · 51 мин", "18 нояб · 34 мин", "16 нояб · осталось 12 мин"])
        // Ленты только подписок, без принудительного обновления.
        #expect(Set(setup.episodes.calls.map(\.id)) == ["out", "puck", "review"])
        #expect(setup.episodes.calls.allSatisfy { !$0.force })
    }

    @Test func badgeHiddenWithoutNew() async {
        let setup = make(subscriptions: ["review": testNow])
        await appear(setup.viewModel)
        #expect(setup.viewModel.state.badge == nil)
        #expect(subscriptionsContent(setup.viewModel)?.episodes == .status(StatusMessage(message: "Новых выпусков нет", showsRetry: false)))
    }

    @Test func listenButtonOnFirstRowAndPauseOnPlayingEpisode() async {
        let setup = make()
        await appear(setup.viewModel)
        #expect(rows(setup.viewModel).map(\.button) == [.listen, nil, nil, nil])

        let results = feeds["out"]![2]
        setup.player.set(results, outOfPlay, .playing)
        #expect(rows(setup.viewModel).map(\.button) == [.listen, nil, nil, .pause])
        setup.player.set(results, outOfPlay, .paused)
        #expect(rows(setup.viewModel).map(\.button) == [.listen, nil, nil, .listen])
        let preview = feeds["out"]![0]
        setup.player.set(preview, outOfPlay, .loading)
        #expect(rows(setup.viewModel).map(\.button) == [.pause, nil, nil, nil])
    }

    @Test func buttonAccessibilityLabelNamesEpisode() async {
        let setup = make()
        await appear(setup.viewModel)
        let first = rows(setup.viewModel)[0]
        #expect(first.buttonAccessibilityLabel == "Слушать, \(first.title)")
        #expect(rows(setup.viewModel)[1].buttonAccessibilityLabel == nil)
        setup.player.set(feeds["out"]![0], outOfPlay, .playing)
        #expect(rows(setup.viewModel)[0].buttonAccessibilityLabel == "Пауза, \(first.title)")
    }

    @Test func buttonTogglesCurrentAndPlaysOther() async {
        var opened = 0
        let setup = make(onOpenPlayer: { opened += 1 })
        await appear(setup.viewModel)
        let preview = feeds["out"]![0]
        let cup = feeds["puck"]![0]

        setup.viewModel.didTapEpisodeButton(preview.id)
        #expect(setup.player.played == [preview.id])
        setup.player.set(preview, outOfPlay, .playing)
        setup.viewModel.didTapEpisodeButton(preview.id)
        #expect(setup.player.toggles == 1)
        // Строка выпуска в плеере открывает плеер, другая — запускает.
        setup.viewModel.didTapEpisode(preview.id)
        #expect(opened == 1)
        setup.viewModel.didTapEpisode(cup.id)
        #expect(setup.player.played == [preview.id, cup.id])
    }

    @Test func subscribeTogglesWithoutRefetch() async {
        let setup = make()
        await appear(setup.viewModel)
        setup.viewModel.didSelectSegment(.catalog)
        #expect(catalogRows(setup.viewModel).map(\.isSubscribed) == [true, true, true, false])
        let feedCalls = setup.episodes.calls.count

        // Отписка — пересчёт без запросов: бейдж без «Шайбы».
        setup.viewModel.didTapSubscribe("puck")
        #expect(catalogRows(setup.viewModel).map(\.isSubscribed) == [true, false, true, false])
        #expect(setup.viewModel.state.badge == 2)
        #expect(setup.viewModel.feedTask == nil)
        // Повторная подписка — лента уже есть, тоже без запросов.
        setup.viewModel.didTapSubscribe("puck")
        #expect(setup.viewModel.feedTask == nil)
        #expect(setup.episodes.calls.count == feedCalls)
        #expect(setup.podcasts.calls == 1)

        // Новая подписка — грузится только её лента.
        setup.viewModel.didTapSubscribe("tennis")
        await setup.viewModel.feedTask?.value
        #expect(setup.episodes.calls.count == feedCalls + 1)
        #expect(setup.episodes.calls.last?.id == "tennis")
        #expect(setup.podcasts.calls == 1)
        #expect(setup.viewModel.state.badge == 4)
    }

    @Test func progressChangeRecountsNew() async {
        let setup = make()
        await appear(setup.viewModel)
        setup.progress.setPosition(60, for: feeds["out"]![0].id)
        #expect(setup.viewModel.state.badge == 2)
        #expect(subscriptionsContent(setup.viewModel)?.tiles.first?.subtitle == "1 новый")
        #expect(rows(setup.viewModel).first?.caption == "Вне игры")
    }

    @Test func emptySubscriptionsAsksToSubscribe() async {
        let setup = make(subscriptions: [:])
        await appear(setup.viewModel)
        #expect(catalogRows(setup.viewModel).map(\.title) == ["Вне игры", "Шайба", "Разбор", "Теннис"])
        setup.viewModel.didSelectSegment(.subscriptions)
        let content = subscriptionsContent(setup.viewModel)
        #expect(content?.tiles == [])
        #expect(content?.episodes == .status(StatusMessage(message: "Подпишитесь на подкасты в «Подборке»", showsRetry: false)))
        #expect(setup.episodes.calls.isEmpty)
    }

    @Test func catalogErrorWithRetry() async {
        let setup = make()
        setup.podcasts.result = .failure(FakeError())
        await appear(setup.viewModel)
        #expect(setup.viewModel.state.content == .status(StatusMessage(message: "Не удалось загрузить подкасты", showsRetry: true)))

        setup.podcasts.result = .success(catalog)
        setup.viewModel.didTapRetry()
        #expect(setup.viewModel.state.content == .status(.loading))
        await setup.viewModel.loadTask?.value
        #expect(setup.viewModel.state.badge == 3)
    }

    @Test func failedFeedsShowErrorAndTiles() async {
        let setup = make(feeds: [:])
        await appear(setup.viewModel)
        let content = subscriptionsContent(setup.viewModel)
        #expect(content?.tiles.map(\.subtitle) == ["Нет связи", "Нет связи", "Нет связи"])
        #expect(content?.episodes == .status(StatusMessage(message: "Не удалось загрузить выпуски", showsRetry: true)))
    }

    @Test func silentRefreshKeepsCatalogAndPullForcesFeeds() async {
        let setup = make()
        await appear(setup.viewModel)
        setup.podcasts.result = .failure(FakeError())
        setup.viewModel.didPullToRefresh()
        #expect(setup.viewModel.state.isRefreshing)
        await setup.viewModel.loadTask?.value
        #expect(!setup.viewModel.state.isRefreshing)
        #expect(setup.viewModel.state.badge == 3)
        #expect(setup.episodes.calls.suffix(3).allSatisfy { $0.force })
    }

    @Test func tileOpensPodcast() async {
        var opened: [String] = []
        let setup = make(onOpenPodcast: { opened.append($0.id) })
        await appear(setup.viewModel)
        setup.viewModel.didTapPodcast("puck")
        #expect(opened == ["puck"])
    }
}

@MainActor
struct PodcastViewModelTests {
    let show = podcast("out", "Вне игры")
    var feed: [Episode] {
        [episode("out", "1", "Превью", ago: 3600), episode("out", "2", "Итоги", ago: days(4), minutes: 40), episode("out", "3", "Старый", ago: days(90))]
    }

    func make(subscribed: Bool, feed: [Episode]? = nil, player: FakeAudioPlayer = FakeAudioPlayer(), downloads: FakeDownloads = FakeDownloads())
        -> (PodcastViewModel, FakeSubscriptionsStore, FakeEpisodesRepository) {
        let store = FakeSubscriptionsStore(subscribed ? ["out": testNow.addingTimeInterval(-days(1))] : [:])
        let episodes = FakeEpisodesRepository(feed.map { ["out": $0] } ?? [:])
        let progress = FakeProgressStore([EpisodeID(podcastID: "out", guid: "2"): ListeningProgress(position: 28 * 60, isFinished: false)])
        let viewModel = PodcastViewModel(
            podcast: show, episodes: episodes, subscriptions: store, progress: progress, player: player, downloads: downloads,
            onOpenPlayer: {}, now: { testNow }, calendar: testCalendar
        )
        return (viewModel, store, episodes)
    }

    func rows(_ viewModel: PodcastViewModel) -> [EpisodeRow] {
        if case let .rows(rows) = viewModel.state.episodes { return rows }
        return []
    }

    @Test func rowsAndSubscribeToggle() async {
        let (viewModel, store, _) = make(subscribed: false, feed: feed)
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
        #expect(!viewModel.state.header.isSubscribed)
        // Без подписки «новых» нет.
        #expect(rows(viewModel).map(\.isNew) == [false, false, false])
        #expect(rows(viewModel).map(\.subtitle) == ["Сегодня · 34 мин", "16 нояб · осталось 12 мин", "22 авг · 34 мин"])
        #expect(rows(viewModel).map(\.button) == [.listen, nil, nil])

        viewModel.didTapSubscribe()
        #expect(store.subscriptions["out"] != nil)
        #expect(viewModel.state.header.isSubscribed)
        #expect(rows(viewModel).map(\.isNew) == [true, false, false])
    }

    @Test func playsEpisodeAndShowsPause() async {
        let player = FakeAudioPlayer()
        let (viewModel, _, _) = make(subscribed: true, feed: feed, player: player)
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
        viewModel.didTapEpisode(feed[2].id)
        #expect(player.played == [feed[2].id])
        player.set(feed[2], show, .playing)
        #expect(rows(viewModel).map(\.button) == [.listen, nil, .pause])
    }

    @Test func errorAndEmpty() async {
        let (failing, _, episodes) = make(subscribed: true)
        failing.viewDidAppear()
        await failing.loadTask?.value
        #expect(failing.state.episodes == .status(StatusMessage(message: "Не удалось загрузить выпуски", showsRetry: true)))
        episodes.feeds = ["out": []]
        failing.didTapRetry()
        await failing.loadTask?.value
        #expect(failing.state.episodes == .status(StatusMessage(message: "Выпусков пока нет", showsRetry: false)))
    }
}
