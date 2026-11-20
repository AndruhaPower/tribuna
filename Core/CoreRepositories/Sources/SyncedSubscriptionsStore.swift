import Combine
import CoreDomain
import Foundation

struct SubscriptionRow: UserRow {
    static let table = "podcast_subscriptions"
    static let keyColumn = "podcast_id"
    let userID: String
    let key: String
    let item: Date

    enum CodingKeys: String, CodingKey { case userID = "user_id", key = "podcast_id", item = "subscribed_at" }
}

/// Подписки пользователя (D31): id подкаста → дата подписки, синхронизируются с таблицей `podcast_subscriptions`.
@MainActor
final class SyncedSubscriptionsStore: SubscriptionsStore {
    let collection: SyncedCollection<Date>
    private let now: () -> Date

    init(defaults: UserDefaults, account: Account, remote: (any UserDataRemote<Date>)?,
         notifications: NotificationCenter = .default, now: @escaping () -> Date = Date.init) {
        self.now = now
        collection = SyncedCollection(name: "podcasts.subscriptions", defaults: defaults, account: account, remote: remote,
                                      notifications: notifications, now: now)
    }

    var subscriptions: [String: Date] { collection.value }

    var subscriptionsPublisher: AnyPublisher<[String: Date], Never> { collection.subject.eraseToAnyPublisher() }

    func toggle(_ podcastID: String) {
        collection.set(podcastID, collection.value[podcastID] == nil ? now() : nil)
    }

    func refreshFromServer(force: Bool = false) async { await collection.refresh(force: force) }

    func flush() async { await collection.flush() }
}
