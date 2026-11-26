import Mindbox
import UIKit

/// Mindbox (D36): пуши, события, гарантированная доставка. Без endpoint (`AppConfig.mindboxEndpoint`) ничего не делает.
@MainActor
enum Marketing {
    static var isEnabled: Bool { !AppConfig.mindboxEndpoint.isEmpty }

    /// Только из `didFinishLaunching`: фоновые задачи SDK регистрируются до конца запуска. Порядок — как в `MindboxAppDelegate`.
    static func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard isEnabled else { return }
        Mindbox.shared.registerBGTasks()
        Mindbox.shared.track(.launch(launchOptions))
        do {
            let configuration = try MBConfiguration(endpoint: AppConfig.mindboxEndpoint, domain: AppConfig.mindboxDomain)
            Mindbox.shared.initialization(configuration: configuration)
        } catch {
            assertionFailure("Mindbox: \(error)")
            return
        }
        // Токен APNs без окна разрешения; показывать ли пуши, человек решает в запросе уведомлений (напоминания, D22).
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func didRegister(deviceToken: Data) {
        guard isEnabled else { return }
        Mindbox.shared.apnsTokenUpdate(deviceToken: deviceToken)
    }

    /// При каждой активации: разрешение могли выдать в запросе или отозвать в Настройках.
    static func refreshPermission() {
        guard isEnabled else { return }
        Mindbox.shared.refreshNotificationPermissionStatus()
    }

    static func didOpen(_ response: UNNotificationResponse) {
        guard isEnabled, Mindbox.shared.isMindboxPush(userInfo: response.notification.request.content.userInfo) else { return }
        Mindbox.shared.pushClicked(response: response)
        Mindbox.shared.track(.push(response))
    }
}
