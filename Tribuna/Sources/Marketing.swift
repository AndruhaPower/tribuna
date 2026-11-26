#if canImport(Mindbox)
import Mindbox
#endif
import UIKit

/// Mindbox (D36, D38): пуши, события, гарантированная доставка. SDK в сборке только с endpoint (`mindboxEndpoint`
/// в `Project.swift` → Info.plist `MindboxEndpoint`); без него все методы — пустые.
@MainActor
enum Marketing {
    private static let endpoint = Bundle.main.object(forInfoDictionaryKey: "MindboxEndpoint") as? String ?? ""

    #if canImport(Mindbox)
    static var isEnabled: Bool { !endpoint.isEmpty }
    #else
    static let isEnabled = false
    #endif

    /// Только из `didFinishLaunching`: фоновые задачи SDK регистрируются до конца запуска. Порядок — как в `MindboxAppDelegate`.
    static func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        #if canImport(Mindbox)
        guard isEnabled else { return }
        Mindbox.shared.registerBGTasks()
        Mindbox.shared.track(.launch(launchOptions))
        do {
            Mindbox.shared.initialization(configuration: try MBConfiguration(endpoint: endpoint, domain: "api.mindbox.ru"))
        } catch {
            assertionFailure("Mindbox: \(error)")
            return
        }
        // Токен APNs без окна разрешения; показывать ли пуши, человек решает в запросе уведомлений (напоминания, D22).
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func didRegister(deviceToken: Data) {
        #if canImport(Mindbox)
        guard isEnabled else { return }
        Mindbox.shared.apnsTokenUpdate(deviceToken: deviceToken)
        #endif
    }

    /// При каждой активации: разрешение могли выдать в запросе или отозвать в Настройках.
    static func refreshPermission() {
        #if canImport(Mindbox)
        guard isEnabled else { return }
        Mindbox.shared.refreshNotificationPermissionStatus()
        #endif
    }

    static func didOpen(_ response: UNNotificationResponse) {
        #if canImport(Mindbox)
        guard isEnabled, Mindbox.shared.isMindboxPush(userInfo: response.notification.request.content.userInfo) else { return }
        Mindbox.shared.pushClicked(response: response)
        Mindbox.shared.track(.push(response))
        #endif
    }
}
