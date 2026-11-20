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

        public init(
            podcasts: PodcastsRepository,
            episodes: EpisodesRepository,
            subscriptions: SubscriptionsStore,
            progress: ListeningProgressStore,
            player: AudioPlayer,
            downloads: EpisodeDownloads
        ) {
            self.podcasts = podcasts
            self.episodes = episodes
            self.subscriptions = subscriptions
            self.progress = progress
            self.player = player
            self.downloads = downloads
        }
    }

    public struct Output {
        let openPlayer: () -> Void

        public init(openPlayer: @escaping () -> Void) {
            self.openPlayer = openPlayer
        }
    }

    /// Корень вкладки; экран подкаста координатор кладёт в навигацию, в которую приложение обернуло корень.
    @MainActor public static func make(dependencies: Dependencies, output: Output) -> UIViewController {
        PodcastsCoordinator(dependencies: dependencies, output: output).start()
    }
}
