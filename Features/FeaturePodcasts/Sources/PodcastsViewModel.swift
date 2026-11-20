import Combine
import CoreDomain
import Foundation

/// Вкладка «Подкасты»: «Подборка» (каталог) и «Подписки» (плитки и «Новые выпуски»).
@MainActor
final class PodcastsViewModel {
    @Published private(set) var state: PodcastsState

    /// Текущая загрузка каталога и лент; тесты ждут её `value`.
    private(set) var loadTask: Task<Void, Never>?
    /// Лента только что подписанного подкаста; тесты ждут её `value`.
    private(set) var feedTask: Task<Void, Never>?

    private let repository: PodcastsRepository
    private let episodesRepository: EpisodesRepository
    private let subscriptionsStore: SubscriptionsStore
    private let progressStore: ListeningProgressStore
    private let player: AudioPlayer
    private let onOpenPodcast: (Podcast) -> Void
    private let onOpenPlayer: () -> Void
    private let now: () -> Date
    private let calendar: Calendar

    /// nil — каталог ещё не загружен.
    private var catalog: [Podcast]?
    private var catalogFailed = false
    private var episodes: [String: [Episode]] = [:]
    /// Ленты, которые не загрузились и кеша нет.
    private var failedFeeds: Set<String> = []
    private var subscriptions: [String: Date]
    private var progress: [EpisodeID: ListeningProgress]
    private var playback: PlaybackState
    private var hasAppeared = false
    private var cancellables = Set<AnyCancellable>()

    init(
        podcasts: PodcastsRepository,
        episodes: EpisodesRepository,
        subscriptions: SubscriptionsStore,
        progress: ListeningProgressStore,
        player: AudioPlayer,
        onOpenPodcast: @escaping (Podcast) -> Void,
        onOpenPlayer: @escaping () -> Void,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        repository = podcasts
        episodesRepository = episodes
        subscriptionsStore = subscriptions
        progressStore = progress
        self.player = player
        self.onOpenPodcast = onOpenPodcast
        self.onOpenPlayer = onOpenPlayer
        self.now = now
        self.calendar = calendar
        self.subscriptions = subscriptions.subscriptions
        self.progress = progress.progress
        playback = player.state
        // Подписки на телефоне известны сразу: есть — открываем их, нет — «Подборку».
        state = PodcastsState(segment: subscriptions.subscriptions.isEmpty ? .catalog : .subscriptions, badge: nil, content: .status(.loading))

        subscriptions.subscriptionsPublisher.dropFirst().sink { [weak self] value in
            MainActor.assumeIsolated { self?.subscriptionsChanged(value) }
        }.store(in: &cancellables)
        progress.progressPublisher.dropFirst().sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.progress = value
                self?.render()
            }
        }.store(in: &cancellables)
        player.statePublisher.sink { [weak self] value in
            MainActor.assumeIsolated { self?.playerChanged(value) }
        }.store(in: &cancellables)
    }

    /// Каждый показ обновляет ленты (репозиторий сам не качает их чаще раза в 30 мин); каталог — только если его нет.
    func viewDidAppear() {
        let isFirst = !hasAppeared
        hasAppeared = true
        load(catalog: isFirst || catalog == nil, force: false)
    }

    func didEnterForeground() {
        guard hasAppeared else { return }
        load(catalog: true, force: false)
    }

    func didPullToRefresh() {
        state.isRefreshing = true
        load(catalog: true, force: true)
    }

    func didTapRetry() {
        catalogFailed = false
        failedFeeds = []
        render()
        load(catalog: catalog == nil, force: false)
    }

    func didSelectSegment(_ segment: PodcastsState.Segment) {
        state.segment = segment
        render()
    }

    func didTapPodcast(_ id: String) {
        if let podcast = catalog?.first(where: { $0.id == id }) { onOpenPodcast(podcast) }
    }

    func didTapSubscribe(_ id: String) {
        subscriptionsStore.toggle(id)
    }

    /// Кнопка строки: выпуск в плеере — пауза/продолжение, другой — запуск.
    func didTapEpisodeButton(_ id: EpisodeID) {
        guard let (episode, podcast) = entry(id) else { return }
        player.playOrToggle(episode, podcast: podcast)
    }

    /// Строка: выпуск в плеере — открыть плеер, другой — запуск.
    func didTapEpisode(_ id: EpisodeID) {
        guard let (episode, podcast) = entry(id) else { return }
        if playback.item?.episode?.id == id { onOpenPlayer() } else { player.play(.episode(episode, podcast: podcast)) }
    }

    // MARK: - Загрузка

    private func load(catalog reloadCatalog: Bool, force: Bool) {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            if reloadCatalog {
                do {
                    catalog = try await repository.podcasts()
                    catalogFailed = false
                } catch {
                    // Тихое обновление не затирает уже показанный каталог.
                    if catalog == nil { catalogFailed = true }
                }
                render()
            }
            await loadFeeds(subscribedPodcasts, force: force)
            state.isRefreshing = false
            loadTask = nil
        }
    }

    /// При сбое без кеша репозиторий бросает ошибку; при сбое с кешем отдаёт кеш молча (D27) — показываем его.
    private func loadFeeds(_ podcasts: [Podcast], force: Bool) async {
        guard !podcasts.isEmpty else { return }
        let repository = episodesRepository
        await withTaskGroup(of: (String, [Episode]?).self) { group in
            for podcast in podcasts {
                group.addTask { (podcast.id, try? await repository.episodes(for: podcast, forceRefresh: force)) }
            }
            for await (id, list) in group {
                if let list {
                    episodes[id] = list
                    failedFeeds.remove(id)
                } else if episodes[id] == nil {
                    failedFeeds.insert(id)
                }
                render()
            }
        }
    }

    private func subscriptionsChanged(_ value: [String: Date]) {
        let added = Set(value.keys).subtracting(subscriptions.keys)
        subscriptions = value
        render()
        // Только что подписались — грузим ленту этого подкаста; остальное пересчитываем без запросов.
        let missing = (catalog ?? []).filter { added.contains($0.id) && episodes[$0.id] == nil }
        guard !missing.isEmpty else { return }
        feedTask = Task { [weak self] in await self?.loadFeeds(missing, force: false) }
    }

    private func playerChanged(_ value: PlaybackState) {
        // Позиция меняется дважды в секунду — перерисовываем только при смене выпуска или статуса.
        let changed = value.item != playback.item || value.status != playback.status
        playback = value
        if changed { render() }
    }

    private var subscribedPodcasts: [Podcast] {
        PodcastsFormatter.subscribed(catalog ?? [], subscriptions: subscriptions).map(\.podcast)
    }

    private func entry(_ id: EpisodeID) -> (Episode, Podcast)? {
        for podcast in catalog ?? [] {
            if let episode = episodes[podcast.id]?.first(where: { $0.id == id }) { return (episode, podcast) }
        }
        return nil
    }

    // MARK: - Состояние

    private func render() {
        guard let catalog else {
            state.badge = nil
            state.content = .status(catalogFailed
                ? StatusMessage(message: "Не удалось загрузить подкасты", showsRetry: true)
                : .loading)
            return
        }
        let subscribed = PodcastsFormatter.subscribed(catalog, subscriptions: subscriptions)
        let feed = PodcastsFormatter.feed(subscribed, episodes: episodes, progress: progress)
        let newCount = feed.filter(\.isNew).count
        state.badge = newCount > 0 ? newCount : nil

        switch state.segment {
        case .catalog:
            state.content = .catalog(catalog.map {
                PodcastRow(id: $0.id, title: $0.title, author: $0.author, artworkURL: $0.artworkURL, isSubscribed: subscriptions[$0.id] != nil)
            })
        case .subscriptions:
            let tiles = PodcastsFormatter.tiles(subscribed, episodes: episodes, failed: failedFeeds, progress: progress)
            state.content = .subscriptions(tiles: tiles, episodes: episodesContent(subscribed: subscribed, feed: feed))
        }
    }

    private func episodesContent(
        subscribed: [(podcast: Podcast, since: Date)],
        feed: [(episode: Episode, podcast: Podcast, isNew: Bool)]
    ) -> PodcastsState.EpisodesContent {
        if subscribed.isEmpty {
            return .status(StatusMessage(message: "Подпишитесь на подкасты в «Подборке»", showsRetry: false))
        }
        if !feed.isEmpty {
            let now = now()
            return .rows(feed.enumerated().map { index, item in
                PodcastsFormatter.row(
                    item.episode, podcast: item.podcast, isNew: item.isNew, isFirst: index == 0,
                    progress: progress, playback: playback, now: now, calendar: calendar
                )
            })
        }
        let ids = subscribed.map(\.podcast.id)
        if ids.contains(where: { episodes[$0] == nil && !failedFeeds.contains($0) }) { return .status(.loading) }
        if ids.allSatisfy(failedFeeds.contains) {
            return .status(StatusMessage(message: "Не удалось загрузить выпуски", showsRetry: true))
        }
        return .status(StatusMessage(message: "Новых выпусков нет", showsRetry: false))
    }
}

extension AudioPlayer {
    /// Выпуск в плеере — пауза/продолжение, другой — запуск.
    func playOrToggle(_ episode: Episode, podcast: Podcast) {
        if state.item?.episode?.id == episode.id { togglePlayPause() } else { play(.episode(episode, podcast: podcast)) }
    }
}
