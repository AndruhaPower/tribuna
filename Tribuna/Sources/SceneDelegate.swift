import AppTrackingTransparency
import Combine
import CoreDomain
import CoreRepositories
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
    private var cleanup: AccountCleanup?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Выход или смена пользователя — снять напоминания и удалить загрузки (D31).
        var cleanupDefaults: UserDefaults? = .standard
        #if DEBUG
        if AppDependencies.isProfileMock {
            cleanupDefaults = AppDependencies.profileMockDefaults
        } else if dependencies.account is MockAccount {
            // Моки вёрстки на «вошедшем» `MockAccount`: вход не меняется, а владелец «mock» в настоящем наборе стёр бы данные при обычном запуске.
            cleanupDefaults = nil
        }
        #endif
        cleanup = cleanupDefaults.map {
            AccountCleanup(account: dependencies.account, reminders: dependencies.reminders, downloads: dependencies.downloads, defaults: $0)
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeTabBar()
        window.makeKeyAndVisible()
        self.window = window
        // Напоминания хранилище читает из центра уведомлений асинхронно — пересверяем, когда они появятся.
        launchReconcile = dependencies.reminders.scheduledPublisher
            .first { !$0.isEmpty }
            .sink { [weak self] in self?.reconcileReminders($0) }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Marketing.refreshPermission()
        // Трекинг (D33): спрашиваем один раз и только в активном приложении — иначе iOS молча отвечает «нет».
        // Только с Mindbox (D38): без него трекинга нет, а в Info.plist нет текста запроса.
        // Сразу после активации iOS пропускает запрос без окна — ждём секунду.
        guard Marketing.isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard UIApplication.shared.applicationState == .active,
                  ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        BackgroundRefresh.schedule()
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
                downloads: dependencies.downloads,
                account: dependencies.account
            ),
            output: .init(openPlayer: { [weak self] in self?.openPlayer() }, requireSignIn: { [weak self] in self?.requireSignIn($0, then: $1) })
        )
        let miniPlayer = FeaturePlayer.makeMiniPlayer(player: dependencies.player, onOpen: { [weak self] in self?.openPlayer() })
        let tabBar = MainTabBarController(tabs: [
            .init(item: .init(title: "Сегодня", icon: "tab-today"), root: makeToday()),
            .init(item: .init(title: "Эфир", icon: "tab-radio"), root: radio),
            .init(item: .init(title: "Подкасты", icon: "tab-podcasts"), root: podcasts),
            .init(item: .init(title: "Профиль", icon: "tab-profile"), root: makeProfile()),
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
        if AppDependencies.isProfileMock {
            tabBar.loadViewIfNeeded()
            tabBar.select(3)
        }
        // `-SignInSheet` — лист входа с мотивацией (повод «закладка»), как его откроют ворота.
        if arguments.contains("-SignInSheet") {
            DispatchQueue.main.async { [weak self] in self?.requireSignIn(.bookmark) {} }
        }
        if arguments.contains("-OpenPlayer") {
            DispatchQueue.main.async { [weak self] in self?.openPlayer() }
        }
        #endif
        return tabBar
    }

    private func makeProfile() -> UIViewController {
        let (bookmarks, subscriptions, progress) = (dependencies.bookmarks, dependencies.subscriptions, dependencies.progress)
        return FeatureProfile.make(
            dependencies: .init(account: dependencies.account, bookmarks: bookmarks, subscriptions: subscriptions, downloads: dependencies.downloads),
            output: .init(flushUserData: { await Services.flushUserData(bookmarks: bookmarks, subscriptions: subscriptions, progress: progress) })
        )
    }

    /// Ворота (D31): вошёл — сразу `action`; иначе лист входа поверх верхнего экрана, `action` — только после входа.
    func requireSignIn(_ reason: SignInReason, then action: @escaping @MainActor () -> Void) {
        if case .signedIn = dependencies.account.state { return action() }
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        if FeatureProfile.isSignIn(top) { return }
        // Верхний экран уходит (например, меню или алерт, из которого нажали) — покажем лист, когда уйдёт.
        if top.isBeingDismissed, let transition = top.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] _ in self?.requireSignIn(reason, then: action) }
            return
        }
        let sheet = FeatureProfile.makeSignIn(account: dependencies.account, reason: reason, startAt: .motivation) { signedIn in
            if signedIn { action() }
        }
        top.present(sheet, animated: true)
    }

    /// Плеер (лист) поверх вкладок — из «Эфира», «Подкастов» и мини-плеера.
    private func openPlayer() {
        guard let root = window?.rootViewController, root.presentedViewController == nil else { return }
        let player = FeaturePlayer.makePlayer(player: dependencies.player, downloads: dependencies.downloads,
                                              requireSignIn: { [weak self] in self?.requireSignIn($0, then: $1) })
        root.present(player, animated: true)
    }

    private func makeToday() -> UIViewController {
        weak var today: UIViewController?
        let controller = FeatureToday.make(
            dependencies: .init(matches: dependencies.matches, bookmarks: dependencies.bookmarks),
            output: .init(openMatch: { [weak self] id in
                guard let self, let navigation = today?.navigationController else { return }
                navigation.pushViewController(makeMatch(id), animated: true)
            }, requireSignIn: { [weak self] in self?.requireSignIn($0, then: $1) })
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
            }, requireSignIn: { [weak self] in self?.requireSignIn($0, then: $1) }),
            matchID: id
        )
    }
}
