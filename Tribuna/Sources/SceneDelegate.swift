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

    private func makeTabBar() -> MainTabBarController {
        MainTabBarController(tabs: [
            .init(item: .init(title: "Сегодня", icon: "tab-today"), root: FeatureToday.makeRoot()),
            .init(item: .init(title: "Эфир", icon: "tab-radio"), root: FeatureRadio.makeRoot()),
            .init(item: .init(title: "Подкасты", icon: "tab-podcasts"), root: FeaturePodcasts.makeRoot()),
            .init(item: .init(title: "Профиль", icon: "tab-profile"), root: FeatureProfile.makeRoot()),
        ])
    }
}
