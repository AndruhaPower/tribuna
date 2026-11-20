import CoreDomain
import UIKit

/// Переходы фичи (D21: в фиче больше одного экрана): вкладка → экран подкаста.
/// Живёт, пока жив корень: его держит замыкание модели вкладки.
@MainActor
final class PodcastsCoordinator {
    private let dependencies: FeaturePodcasts.Dependencies
    private let output: FeaturePodcasts.Output
    private weak var root: UIViewController?

    init(dependencies: FeaturePodcasts.Dependencies, output: FeaturePodcasts.Output) {
        self.dependencies = dependencies
        self.output = output
    }

    func start() -> UIViewController {
        let controller = PodcastsViewController(viewModel: PodcastsViewModel(
            podcasts: dependencies.podcasts,
            episodes: dependencies.episodes,
            subscriptions: dependencies.subscriptions,
            progress: dependencies.progress,
            player: dependencies.player,
            downloads: dependencies.downloads,
            account: dependencies.account,
            onOpenPodcast: { [self] in openPodcast($0) },
            onOpenPlayer: output.openPlayer,
            requireSignIn: output.requireSignIn
        ))
        root = controller
        return controller
    }

    private func openPodcast(_ podcast: Podcast) {
        let controller = PodcastViewController(viewModel: PodcastViewModel(
            podcast: podcast,
            episodes: dependencies.episodes,
            subscriptions: dependencies.subscriptions,
            progress: dependencies.progress,
            player: dependencies.player,
            downloads: dependencies.downloads,
            onOpenPlayer: output.openPlayer,
            requireSignIn: output.requireSignIn
        ))
        root?.navigationController?.pushViewController(controller, animated: true)
    }
}
