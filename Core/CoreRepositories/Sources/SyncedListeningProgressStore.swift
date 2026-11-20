import Combine
import CoreDomain
import Foundation

/// Позиция выпуска с временем изменения: при конфликте побеждает более позднее (D31).
struct ProgressRecord: SyncItem {
    var position: TimeInterval
    var isFinished: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey { case position, isFinished = "is_finished", updatedAt = "updated_at" }

    func supersedes(_ server: ProgressRecord) -> Bool { updatedAt >= server.updatedAt }
}

/// Строка `listening_progress`: колонки значения лежат рядом с `user_id` и `episode_id`.
struct ProgressRow: UserRow {
    static let table = "listening_progress"
    static let keyColumn = "episode_id"
    let userID: String
    let key: String
    let item: ProgressRecord

    enum CodingKeys: String, CodingKey { case userID = "user_id", key = "episode_id" }

    init(userID: String, key: String, item: ProgressRecord) {
        self.userID = userID
        self.key = key
        self.item = item
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        key = try container.decode(String.self, forKey: .key)
        item = try ProgressRecord(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(key, forKey: .key)
        try item.encode(to: encoder)
    }
}

/// Позиция и «прослушано» пользователя (D27, D31): локально — каждый вызов, на сервер — не чаще раза в 60 с
/// и сразу по `flushProgress()` (пауза, смена выпуска, стоп, уход в фон) и `markFinished`.
@MainActor
public final class SyncedListeningProgressStore: ListeningProgressStore {
    static let pushInterval: TimeInterval = 60

    let collection: SyncedCollection<ProgressRecord>
    private let now: () -> Date
    private var lastPush: Date?

    init(defaults: UserDefaults, account: Account, remote: (any UserDataRemote<ProgressRecord>)?,
         notifications: NotificationCenter = .default, now: @escaping () -> Date = Date.init) {
        self.now = now
        collection = SyncedCollection(name: "podcasts.progress", defaults: defaults, account: account, remote: remote,
                                      notifications: notifications, now: now)
    }

    public var progress: [EpisodeID: ListeningProgress] { Self.progress(collection.value) }

    public var progressPublisher: AnyPublisher<[EpisodeID: ListeningProgress], Never> {
        collection.subject.map(Self.progress).eraseToAnyPublisher()
    }

    public func setPosition(_ position: TimeInterval, for id: EpisodeID) {
        update(id) { $0.position = position }
        if lastPush.map({ now().timeIntervalSince($0) >= Self.pushInterval }) ?? true { flushProgress() }
    }

    public func markFinished(_ id: EpisodeID) {
        update(id) { $0.position = 0; $0.isFinished = true }
        flushProgress()
    }

    /// Отправить позицию сейчас, не дожидаясь 60 с.
    public func flushProgress() {
        lastPush = now()
        collection.push()
    }

    func refreshFromServer(force: Bool = false) async { await collection.refresh(force: force) }

    func flush() async { await collection.flush() }

    private func update(_ id: EpisodeID, _ change: (inout ProgressRecord) -> Void) {
        var record = collection.value[id.rawValue] ?? ProgressRecord(position: 0, isFinished: false, updatedAt: now())
        change(&record)
        record.updatedAt = now()
        collection.set(id.rawValue, record, push: false)
    }

    private static func progress(_ value: [String: ProgressRecord]) -> [EpisodeID: ListeningProgress] {
        Dictionary(uniqueKeysWithValues: value.map { (EpisodeID(rawValue: $0.key), ListeningProgress(position: $0.value.position, isFinished: $0.value.isFinished)) })
    }
}
