import FeatureBookmarks
import FeaturePodcasts
import FeatureProfile
import FeatureRadio
import FeatureToday
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeTabBar()
        window.makeKeyAndVisible()
        self.window = window
    }

    private func makeTabBar() -> UITabBarController {
        let tabs: [(UIViewController, String, String)] = [
            (FeatureToday.makeRoot(), "Сегодня", "sportscourt"),
            (FeatureBookmarks.makeRoot(), "Закладки", "bookmark"),
            (FeatureRadio.makeRoot(), "Эфир", "dot.radiowaves.left.and.right"),
            (FeaturePodcasts.makeRoot(), "Подкасты", "mic"),
            (FeatureProfile.makeRoot(), "Профиль", "person.crop.circle"),
        ]
        let tabBar = UITabBarController()
        tabBar.viewControllers = tabs.map { root, title, symbol in
            let nav = UINavigationController(rootViewController: root)
            nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: 0)
            return nav
        }
        return tabBar
    }
}
