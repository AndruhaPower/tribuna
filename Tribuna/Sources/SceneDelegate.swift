import FeatureMatch
import FeaturePodcasts
import FeatureProfile
import FeatureRadio
import FeatureToday
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let dependencies = AppDependencies()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeTabBar()
        window.makeKeyAndVisible()
        self.window = window
    }

    private func makeTabBar() -> MainTabBarController {
        MainTabBarController(tabs: [
            .init(item: .init(title: "Сегодня", icon: "tab-today"), root: makeToday()),
            .init(item: .init(title: "Эфир", icon: "tab-radio"), root: FeatureRadio.makeRoot()),
            .init(item: .init(title: "Подкасты", icon: "tab-podcasts"), root: FeaturePodcasts.makeRoot()),
            .init(item: .init(title: "Профиль", icon: "tab-profile"), root: FeatureProfile.makeRoot()),
        ])
    }

    private func makeToday() -> UIViewController {
        weak var today: UIViewController?
        let controller = FeatureToday.make(
            dependencies: .init(matches: dependencies.matches, bookmarks: dependencies.bookmarks),
            output: .init(openMatch: { _, title in
                today?.navigationController?.pushViewController(FeatureMatch.make(title: title), animated: true)
            })
        )
        today = controller
        return controller
    }
}
