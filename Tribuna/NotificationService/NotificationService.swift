import MindboxNotifications
import UserNotifications

/// Пуши Mindbox (D36): SDK догружает картинку, ставит кнопки и отмечает доставку. Остальные пуши — как пришли.
final class NotificationService: UNNotificationServiceExtension {
    private lazy var mindbox = MindboxNotificationService()

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        mindbox.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        mindbox.serviceExtensionTimeWillExpire()
    }
}
