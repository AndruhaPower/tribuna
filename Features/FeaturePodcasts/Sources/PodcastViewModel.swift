import Combine
import CoreDomain
import Foundation

/// Экран подкаста: шапка с «Подписаться» и все выпуски ленты.
@MainActor
final class PodcastViewModel {
    @Published private(set) var state: PodcastState

    /// Текущая загрузка ленты; тесты ждут её `value`.
    private(set) var loadTask: Task<Void, Never>?

    private let podcast: Podcast
    private let repository: EpisodesRepository
    private let subscriptionsStore: SubscriptionsStore
    private let player: AudioPlayer
    private let downloads: EpisodeDownloads
    private let onOpenPlayer: () -> Void
    private let now: () -> Date
    private let calendar: Calendar

    /// nil — лента ещё не загружена.
    private var episodes: [Episode]?
    private var failed = false
    private var subscriptions: [String: Date]
    private var progress: [EpisodeID: ListeningProgress]
    private var playback: PlaybackState
    private var downloadItems: [DownloadedEpisode]
    private var hasAppeared = false
    private var cancellables = Set<AnyCancellable>()

    init(
        podcast: Podcast,
        episodes: EpisodesRepository,
        subscriptions: SubscriptionsStore,
        progress: ListeningProgressStore,
        player: AudioPlayer,
        downloads: EpisodeDownloads,
        onOpenPlayer: @escaping () -> Void,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.podcast = podcast
        repository = episodes
        subscriptionsStore = subscriptions
        self.player = player
        self.downloads = downloads
        self.onOpenPlayer = onOpenPlayer
        self.now = now
        self.calendar = calendar
        self.subscriptions = subscriptions.subscriptions
        self.progress = progress.progress
        playback = player.state
        downloadItems = downloads.items
        state = PodcastState(header: Self.header(podcast, isSubscribed: subscriptions.subscriptions[podcast.id] != nil), episodes: .status(.loading))

        subscriptions.subscriptionsPublisher.dropFirst().sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.subscriptions = value
                self?.render()
            }
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
        downloads.itemsPublisher.dropFirst().sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.downloadItems = value
                self?.render()
            }
        }.store(in: &cancellables)
    }

    private func playerChanged(_ value: PlaybackState) {
        // Позиция меняется дважды в секунду — перерисовываем только при смене выпуска или статуса.
        let changed = value.item != playback.item || value.status != playback.status
        playback = value
        if changed { render() }
    }

    func viewDidAppear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        load(force: false)
    }

    func didEnterForeground() {
        guard hasAppeared else { return }
        load(force: false)
    }

    func didPullToRefresh() {
        state.isRefreshing = true
        load(force: true)
    }

    func didTapRetry() {
        failed = false
        render()
        load(force: false)
    }

    func didTapSubscribe() {
        subscriptionsStore.toggle(podcast.id)
    }

    func didTapEpisodeButton(_ id: EpisodeID) {
        guard let episode = episodes?.first(where: { $0.id == id }) else { return }
        player.playOrToggle(episode, podcast: podcast)
    }

    /// Строка: выпуск в плеере — открыть плеер, другой — запуск.
    func didTapEpisode(_ id: EpisodeID) {
        guard let episode = episodes?.first(where: { $0.id == id }) else { return }
        if playback.item?.episode?.id == id { onOpenPlayer() } else { player.play(.episode(episode, podcast: podcast)) }
    }

    func didTapDownloadAction(_ id: EpisodeID, shown: EpisodeRow.DownloadAction? = nil) {
        downloads.perform(id, entry: episodes?.first { $0.id == id }.map { ($0, podcast) }, shown: shown)
    }

    private func load(force: Bool) {
        guard loadTask == nil else { return }
        let repository = repository
        let podcast = podcast
        loadTask = Task { [weak self] in
            let result = try? await repository.episodes(for: podcast, forceRefresh: force)
            guard let self else { return }
            if let result {
                episodes = result
                failed = false
            } else if episodes == nil {
                // Тихое обновление не затирает уже показанные выпуски.
                failed = true
            }
            state.isRefreshing = false
            loadTask = nil
            render()
        }
    }

    private func render() {
        state.header = Self.header(podcast, isSubscribed: subscriptions[podcast.id] != nil)
        guard let episodes else {
            state.episodes = .status(failed ? StatusMessage(message: "Не удалось загрузить выпуски", showsRetry: true) : .loading)
            return
        }
        guard !episodes.isEmpty else {
            state.episodes = .status(StatusMessage(message: "Выпусков пока нет", showsRetry: false))
            return
        }
        // «Новые» — только у подписанного подкаста.
        let since = subscriptions[podcast.id]
        let now = now()
        state.episodes = .rows(episodes.enumerated().map { index, episode in
            let isNew = since.map { PodcastsFormatter.isNew(episode, subscribedAt: $0, progress: progress) } ?? false
            return PodcastsFormatter.row(
                episode, podcast: podcast, isNew: isNew, isFirst: index == 0, progress: progress, playback: playback,
                download: downloadItems.first { $0.id == episode.id }, wifiOnly: downloads.wifiOnly, now: now, calendar: calendar
            )
        })
    }

    private static func header(_ podcast: Podcast, isSubscribed: Bool) -> PodcastState.Header {
        PodcastState.Header(title: podcast.title, author: podcast.author, artworkURL: podcast.artworkURL, isSubscribed: isSubscribed)
    }
}
