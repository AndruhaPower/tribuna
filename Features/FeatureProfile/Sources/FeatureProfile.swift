import CoreDomain
import UIKit

@MainActor
public enum FeatureProfile {
    public struct Dependencies {
        let bookmarks: BookmarksStore
        let subscriptions: SubscriptionsStore
        let downloads: EpisodeDownloads

        public init(bookmarks: BookmarksStore, subscriptions: SubscriptionsStore, downloads: EpisodeDownloads) {
            self.bookmarks = bookmarks
            self.subscriptions = subscriptions
            self.downloads = downloads
        }
    }

    /// Корень вкладки «Профиль» (D21): счётчики закладок и подписок, настройки загрузок.
    public static func make(dependencies: Dependencies) -> UIViewController {
        ProfileViewController(viewModel: ProfileViewModel(dependencies: dependencies))
    }
}
