import CoreDomain
import UIKit

/// Мини-плеер и полноэкранный плеер (D15, D25). Оба отражают единственный `AudioPlayer` приложения.
@MainActor
public enum FeaturePlayer {
    /// Мини-плеер для контейнера вкладок: контейнер ставит его над таб-баром и показывает по `onVisibilityChange`.
    public static func makeMiniPlayer(player: AudioPlayer, onOpen: @escaping () -> Void) -> MiniPlayerView {
        MiniPlayerView(viewModel: PlayerViewModel(player: player), onOpen: onOpen)
    }

    /// Плеер (лист); `downloads` — «Скачать» / «Скачан» у выпуска; `requireSignIn` — ворота «Скачать» (D31).
    public static func makePlayer(
        player: AudioPlayer,
        downloads: EpisodeDownloads,
        requireSignIn: @escaping (SignInReason, @escaping @MainActor () -> Void) -> Void
    ) -> UIViewController {
        PlayerViewController(viewModel: PlayerViewModel(player: player, downloads: downloads, requireSignIn: requireSignIn))
    }
}
