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
        #if FEATURE_PROFILE2
        let settings: ProfileSettings
        let competitions: CompetitionsRepository
        /// nil — имя не меняется (моки вёрстки).
        let renaming: AccountRenaming?

        public init(account: Account, bookmarks: BookmarksStore, subscriptions: SubscriptionsStore, downloads: EpisodeDownloads,
                    avatars: AvatarStore, settings: ProfileSettings, competitions: CompetitionsRepository, renaming: AccountRenaming?) {
            self.account = account
            self.bookmarks = bookmarks
            self.subscriptions = subscriptions
            self.downloads = downloads
            self.avatars = avatars
            self.settings = settings
            self.competitions = competitions
            self.renaming = renaming
        }
        #else
        public init(account: Account, bookmarks: BookmarksStore, subscriptions: SubscriptionsStore, downloads: EpisodeDownloads,
                    avatars: AvatarStore) {
            self.account = account
            self.bookmarks = bookmarks
            self.subscriptions = subscriptions
            self.downloads = downloads
            self.avatars = avatars
        }
        #endif
    }

    public struct Output {
        /// Отправить неотправленные закладки, подписки и позицию — перед выходом (D31).
        let flushUserData: @MainActor () async -> Void
        #if FEATURE_PROFILE2
        /// Системный запрос уведомлений; false — запрещены (тогда переключатель возвращается и предлагаем Настройки).
        let requestNotifications: @MainActor () async -> Bool
        let openSettings: @MainActor () -> Void

        public init(flushUserData: @escaping @MainActor () async -> Void, requestNotifications: @escaping @MainActor () async -> Bool,
                    openSettings: @escaping @MainActor () -> Void) {
            self.flushUserData = flushUserData
            self.requestNotifications = requestNotifications
            self.openSettings = openSettings
        }
        #else
        public init(flushUserData: @escaping @MainActor () async -> Void) {
            self.flushUserData = flushUserData
        }
        #endif
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
