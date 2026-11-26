import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Фоновая сессия поднимается до UI, чтобы система отдала ей события загрузок.
        _ = AppDependencies.backgroundDownloads
        BackgroundRefresh.register()
        Marketing.start(launchOptions: launchOptions)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Marketing.didRegister(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        AppDependencies.backgroundDownloads.handleBackgroundEvents(identifier: identifier, completion: completionHandler)
    }

    /// Без делегата iOS не показывает уведомление, пока приложение на экране.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // shortcut: нажатие на уведомление ничего не открывает (и ссылку из пуша Mindbox тоже); открытие карточки матча — позже.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        nonisolated(unsafe) let response = response
        await MainActor.run { Marketing.didOpen(response) }
    }
}
