import CoreDomain
import UIKit

@MainActor
public enum FeatureProfile {
    public struct Dependencies {
        let account: Account
        let bookmarks: BookmarksStore
        let subscriptions: SubscriptionsStore
        let downloads: EpisodeDownloads
        /// Фото профиля (D43).
        let avatars: AvatarStore

        public init(account: Account, bookmarks: BookmarksStore, subscriptions: SubscriptionsStore, downloads: EpisodeDownloads,
                    avatars: AvatarStore) {
            self.account = account
            self.bookmarks = bookmarks
            self.subscriptions = subscriptions
            self.downloads = downloads
            self.avatars = avatars
        }
    }

    public struct Output {
        /// Отправить неотправленные закладки, подписки и позицию — перед выходом (D31).
        let flushUserData: @MainActor () async -> Void

        public init(flushUserData: @escaping @MainActor () async -> Void) {
            self.flushUserData = flushUserData
        }
    }

    /// Корень вкладки «Профиль» (D21): без входа — мотивация; со входом — аккаунт, счётчики, загрузки, «Удалить аккаунт».
    public static func make(dependencies: Dependencies, output: Output) -> UIViewController {
        ProfileViewController(viewModel: ProfileViewModel(dependencies: dependencies, output: output), account: dependencies.account)
    }

    /// Лист входа (`.pageSheet`, навигация внутри). `completion(true)` — вошёл, `false` — закрыли.
    /// Это лист входа (ворота не открывают второй поверх первого).
    public static func isSignIn(_ controller: UIViewController) -> Bool { controller is SignInCoordinator }

    public static func makeSignIn(account: Account, reason: SignInReason, startAt: SignInStart,
                                  completion: @escaping @MainActor (Bool) -> Void) -> UIViewController {
        SignInCoordinator(model: SignInModel(account: account, reason: reason, start: startAt), completion: completion)
    }
}
