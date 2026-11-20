import CoreDomain
import UIKit

public enum FeaturePodcasts {
    public struct Dependencies {
        let podcasts: PodcastsRepository
        let episodes: EpisodesRepository
        let subscriptions: SubscriptionsStore
        let progress: ListeningProgressStore
        let player: AudioPlayer
        let downloads: EpisodeDownloads
        /// Без входа «Подписки» и «Загрузки» — приглашение войти; вход и выход перерисовывают вкладку (D31).
        let account: Account

        public init(
            podcasts: PodcastsRepository,
            episodes: EpisodesRepository,
            subscriptions: SubscriptionsStore,
            progress: ListeningProgressStore,
            player: AudioPlayer,
            downloads: EpisodeDownloads,
            account: Account
        ) {
            self.podcasts = podcasts
            self.episodes = episodes
            self.subscriptions = subscriptions
            self.progress = progress
            self.player = player
            self.downloads = downloads
            self.account = account
        }
    }

    public struct Output {
        let openPlayer: () -> Void
        /// Ворота (D31): вошёл — сразу действие, иначе лист входа и действие после входа.
        let requireSignIn: (SignInReason, @escaping @MainActor () -> Void) -> Void

        public init(openPlayer: @escaping () -> Void, requireSignIn: @escaping (SignInReason, @escaping @MainActor () -> Void) -> Void) {
            self.openPlayer = openPlayer
            self.requireSignIn = requireSignIn
        }
    }

    /// Корень вкладки; экран подкаста координатор кладёт в навигацию, в которую приложение обернуло корень.
    @MainActor public static func make(dependencies: Dependencies, output: Output) -> UIViewController {
        PodcastsCoordinator(dependencies: dependencies, output: output).start()
    }
}
