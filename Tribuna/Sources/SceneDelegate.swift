import Combine
import CoreDomain
import FeatureMatch
import FeaturePlayer
import FeaturePodcasts
import FeatureProfile
import FeatureRadio
import FeatureToday
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let dependencies = AppDependencies()
    private var launchReconcile: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeTabBar()
        window.makeKeyAndVisible()
        self.window = window
        // Напоминания хранилище читает из центра уведомлений асинхронно — пересверяем, когда они появятся.
        launchReconcile = dependencies.reminders.scheduledPublisher
            .first { !$0.isEmpty }
            .sink { [weak self] in self?.reconcileReminders($0) }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        reconcileReminders(dependencies.reminders.scheduled)
    }

    /// Пересверка напоминаний с актуальным временем матчей (перенос, отмена). Не на критическом пути:
    /// матчи, которые не загрузились, просто не пересверяются.
    private func reconcileReminders(_ ids: Set<MatchID>) {
        guard !ids.isEmpty else { return }
        let matches = dependencies.matches
        let reminders = dependencies.reminders
        Task {
            let loaded = await withTaskGroup(of: Match?.self) { group in
                for id in ids { group.addTask { try? await matches.match(id: id) } }
                var loaded: [Match] = []
                for await match in group { if let match { loaded.append(match) } }
                return loaded
            }
            reminders.reconcile(with: loaded)
        }
    }

    private func makeTabBar() -> MainTabBarController {
        let radio = FeatureRadio.make(
            dependencies: .init(stations: dependencies.stations, player: dependencies.player),
            output: .init(openPlayer: { [weak self] in self?.openPlayer() })
        )
        let podcasts = FeaturePodcasts.make(
            dependencies: .init(
                podcasts: dependencies.podcasts,
                episodes: dependencies.episodes,
                subscriptions: dependencies.subscriptions,
                progress: dependencies.progress,
                player: dependencies.player,
                downloads: dependencies.downloads
            ),
            output: .init(openPlayer: { [weak self] in self?.openPlayer() })
        )
        let miniPlayer = FeaturePlayer.makeMiniPlayer(player: dependencies.player, onOpen: { [weak self] in self?.openPlayer() })
        let tabBar = MainTabBarController(tabs: [
            .init(item: .init(title: "Сегодня", icon: "tab-today"), root: makeToday()),
            .init(item: .init(title: "Эфир", icon: "tab-radio"), root: radio),
            .init(item: .init(title: "Подкасты", icon: "tab-podcasts"), root: podcasts),
            .init(item: .init(title: "Профиль", icon: "tab-profile"), root: FeatureProfile.makeRoot()),
        ], miniPlayer: miniPlayer)
        #if DEBUG
        // `-RadioMockData` открывает «Эфир», если не сверяем «Сегодня» или карточку матча.
        let arguments = ProcessInfo.processInfo.arguments
        if AppDependencies.isRadioMock, !arguments.contains("-TodayMockData"), !arguments.contains("-MatchMockData") {
            tabBar.loadViewIfNeeded()
            tabBar.select(1)
        }
        if AppDependencies.isPodcastsMock {
            tabBar.loadViewIfNeeded()
            tabBar.select(2)
        }
        if arguments.contains("-OpenPlayer") {
            DispatchQueue.main.async { [weak self] in self?.openPlayer() }
        }
        #endif
        return tabBar
    }

    /// Плеер (лист) поверх вкладок — из «Эфира», «Подкастов» и мини-плеера.
    private func openPlayer() {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        root.present(FeaturePlayer.makePlayer(player: dependencies.player), animated: true)
    }

    private func makeToday() -> UIViewController {
        weak var today: UIViewController?
        let controller = FeatureToday.make(
            dependencies: .init(matches: dependencies.matches, bookmarks: dependencies.bookmarks),
            output: .init(openMatch: { [weak self] id in
                guard let self, let navigation = today?.navigationController else { return }
                navigation.pushViewController(makeMatch(id), animated: true)
            })
        )
        today = controller
        #if DEBUG
        if let id = AppDependencies.mockMatchOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                today?.navigationController?.pushViewController(makeMatch(id), animated: false)
            }
        }
        #endif
        return controller
    }

    private func makeMatch(_ id: MatchID) -> UIViewController {
        FeatureMatch.make(
            dependencies: .init(
                matches: dependencies.matches,
                standings: dependencies.standings,
                bookmarks: dependencies.bookmarks,
                reminders: dependencies.reminders
            ),
            output: .init(openSettings: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }),
            matchID: id
        )
    }
}
