import CoreUI
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
            (FeatureToday.makeRoot(), "Сегодня", "calendar"),
            (FeatureRadio.makeRoot(), "Эфир", "dot.radiowaves.left.and.right"),
            (FeaturePodcasts.makeRoot(), "Подкасты", "mic"),
            (FeatureProfile.makeRoot(), "Профиль", "person"),
        ]
        let tabBar = UITabBarController()
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.tabBar
        appearance.shadowColor = Palette.tabBarBorder
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = Palette.textSecondary
            item.normal.titleTextAttributes = [.foregroundColor: Palette.textSecondary]
            item.selected.iconColor = Palette.textPrimary
            item.selected.titleTextAttributes = [.foregroundColor: Palette.textPrimary]
        }
        tabBar.tabBar.standardAppearance = appearance
        tabBar.tabBar.scrollEdgeAppearance = appearance
        tabBar.viewControllers = tabs.map { root, title, symbol in
            let nav = UINavigationController(rootViewController: root)
            nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: 0)
            return nav
        }
        return tabBar
    }
}
