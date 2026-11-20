import Combine
import CoreDomain
import Foundation

struct BookmarkRow: UserRow {
    static let table = "bookmarks"
    static let keyColumn = "match_id"
    let userID: String
    let key: String
    let item: Date

    enum CodingKeys: String, CodingKey { case userID = "user_id", key = "match_id", item = "created_at" }
}

/// Закладки пользователя (D31): `MatchID.rawValue` → дата добавления, синхронизируются с таблицей `bookmarks`.
@MainActor
final class SyncedBookmarksStore: BookmarksStore {
    let collection: SyncedCollection<Date>
    private let now: () -> Date

    init(defaults: UserDefaults, account: Account, remote: (any UserDataRemote<Date>)?,
         notifications: NotificationCenter = .default, now: @escaping () -> Date = Date.init) {
        self.now = now
        collection = SyncedCollection(name: "bookmarks", defaults: defaults, account: account, remote: remote, notifications: notifications, now: now)
    }

    var bookmarks: Set<MatchID> { Self.ids(collection.value) }

    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { collection.subject.map(Self.ids).eraseToAnyPublisher() }

    func toggle(_ id: MatchID) {
        collection.set(id.rawValue, collection.value[id.rawValue] == nil ? now() : nil)
    }

    func refreshFromServer(force: Bool = false) async { await collection.refresh(force: force) }

    func flush() async { await collection.flush() }

    private static func ids(_ value: [String: Date]) -> Set<MatchID> { Set(value.keys.map(MatchID.init(rawValue:))) }
}
