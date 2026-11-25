import Combine
import CoreDomain
import Foundation
import PostgREST
import UIKit

/// Значение строки таблицы пользователя (без `user_id` и ключа).
protocol SyncItem: Codable, Equatable, Sendable {
    /// Неотправленное локальное значение важнее серверного? Иначе серверное заменяет его и снимается с очереди.
    func supersedes(_ server: Self) -> Bool
}

extension SyncItem {
    func supersedes(_ server: Self) -> Bool { true }
}

extension Date: SyncItem {}

/// Таблица пользователя на сервере: ключ → значение. Запросы идемпотентны — повтор безопасен.
protocol UserDataRemote<Item>: Sendable {
    associatedtype Item: SyncItem
    func fetch(userID: String) async throws -> [String: Item]
    func upsert(_ items: [String: Item], userID: String) async throws
    func delete(_ keys: [String], userID: String) async throws
}

/// Строка таблицы PostgREST: `user_id`, ключ и значение.
protocol UserRow: Codable, Sendable {
    associatedtype Item: SyncItem
    static var table: String { get }
    static var keyColumn: String { get }
    init(userID: String, key: String, item: Item)
    var key: String { get }
    var item: Item { get }
}

struct PostgrestUserDataRemote<Row: UserRow>: UserDataRemote {
    let client: PostgrestClient

    func fetch(userID: String) async throws -> [String: Row.Item] {
        let rows: [Row] = try await client.from(Row.table).select().eq("user_id", value: userID).execute().value
        return Dictionary(rows.map { ($0.key, $0.item) }, uniquingKeysWith: { first, _ in first })
    }

    func upsert(_ items: [String: Row.Item], userID: String) async throws {
        let rows = items.map { Row(userID: userID, key: $0.key, item: $0.value) }
        try await client.from(Row.table).upsert(rows, onConflict: "user_id,\(Row.keyColumn)", returning: .minimal).execute()
    }

    func delete(_ keys: [String], userID: String) async throws {
        try await client.from(Row.table).delete(returning: .minimal).eq("user_id", value: userID).in(Row.keyColumn, values: keys).execute()
    }
}

/// Коллекция пользователя: локальная копия + очередь отправки в UserDefaults (ключи с `userID`), сервер (D31).
/// Без входа — пусто, запись игнорируется. Вход — загрузка с сервера поверх неотправленной очереди. Выход — копия и очередь стёрты.
@MainActor
final class SyncedCollection<Item: SyncItem> {
    static var refreshInterval: TimeInterval { 5 * 60 }

    /// Изменение, ждущее отправки; nil — удаление.
    struct Pending: Codable, Equatable { var item: Item? }

    let subject = CurrentValueSubject<[String: Item], Never>([:])
    private let name: String
    private let defaults: UserDefaults
    private let remote: (any UserDataRemote<Item>)?
    private let now: () -> Date
    /// Чья копия загружена; сохраняется, чтобы при запуске (`unknown`) показать её без мигания.
    private var owner: String?
    private var isSignedIn = false
    private var pending: [String: Pending] = [:]
    private var lastRefresh: Date?
    /// Идёт загрузка или отправка: одновременно — только одна, вторая отмечается и выполняется после.
    private var isBusy = false
    private var flushAgain = false
    private var refreshAgain = false
    private var running: [UUID: Task<Void, Never>] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    /// `remote` nil — только локально (отладочные моки).
    init(name: String, defaults: UserDefaults, account: Account, remote: (any UserDataRemote<Item>)?,
         notifications: NotificationCenter, now: @escaping () -> Date) {
        self.name = name
        self.defaults = defaults
        self.remote = remote
        self.now = now
        owner = defaults.string(forKey: ownerKey)
        if let owner {
            subject.value = Self.decode([String: Item].self, defaults.data(forKey: copyKey(owner))) ?? [:]
            pending = Self.decode([String: Pending].self, defaults.data(forKey: queueKey(owner))) ?? [:]
        }
        account.statePublisher.sink { [weak self] in self?.apply($0) }.store(in: &subscriptions)
        notifications.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.run { await $0.refresh() } } }
            .store(in: &subscriptions)
    }

    var value: [String: Item] { subject.value }
    var pendingCount: Int { pending.count }

    func apply(_ state: AccountState) {
        switch state {
        case .unknown:
            isSignedIn = false
        case .signedOut:
            isSignedIn = false
            // Был вход (в т.ч. сессия потеряна, пока приложение не работало) — чистим; запуск без входа ничего не трогает.
            if owner != nil { wipe() }
        case let .signedIn(user):
            if user.id != owner {
                wipe()
                owner = user.id
                defaults.set(user.id, forKey: ownerKey)
            }
            isSignedIn = true
            run { await $0.refresh(force: true) }
        }
    }

    /// nil — удалить. Без входа ничего не делает.
    func set(_ key: String, _ item: Item?, push: Bool = true) {
        guard isSignedIn, let owner else { return }
        var value = subject.value
        value[key] = item
        pending[key] = Pending(item: item)
        save(value, owner: owner)
        subject.send(value)
        if push { self.push() }
    }

    func push() {
        run { await $0.flush() }
    }

    /// Загрузить с сервера (не чаще раза в 5 мин без `force`) поверх неотправленной очереди и отправить её.
    func refresh(force: Bool = false) async {
        guard isSignedIn, let owner, let remote else { return }
        if !force, let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.refreshInterval { return await flush() }
        // Идёт отправка — загрузим после неё, иначе устаревший ответ затрёт только что отправленное.
        guard !isBusy else { refreshAgain = true; return }
        isBusy = true
        lastRefresh = now()
        let server = try? await remote.fetch(userID: owner)
        isBusy = false
        // Пока ждали, могли выйти или сменить пользователя. Отправки за это время не было — изменения ещё в очереди.
        if let server, isSignedIn, self.owner == owner {
            var merged = server
            for (key, change) in pending {
                if let item = change.item, let current = server[key], !item.supersedes(current) {
                    pending[key] = nil
                } else {
                    merged[key] = change.item
                }
            }
            save(merged, owner: owner)
            subject.send(merged)
        }
        await flush()
    }

    /// Отправить очередь; сбой — остаётся до следующего раза. Во время загрузки или другой отправки — только отмечает «ещё раз».
    func flush() async {
        guard isSignedIn, let owner, let remote else { return }
        guard !isBusy else { flushAgain = true; return }
        isBusy = true
        await push(owner: owner, remote: remote)
        isBusy = false
        if refreshAgain {
            refreshAgain = false
            await refresh(force: true)
        }
    }

    private func push(owner: String, remote: any UserDataRemote<Item>) async {
        guard !pending.isEmpty else { return }
        repeat {
            flushAgain = false
            let batch = pending
            let upserts = batch.compactMapValues(\.item)
            let deletes = batch.filter { $0.value.item == nil }.map(\.key)
            do {
                if !upserts.isEmpty { try await remote.upsert(upserts, userID: owner) }
                if !deletes.isEmpty { try await remote.delete(deletes, userID: owner) }
            } catch {
                return
            }
            guard self.owner == owner else { return }
            // Изменённое во время отправки остаётся в очереди.
            for (key, change) in batch where pending[key] == change { pending[key] = nil }
            defaults.set(try? JSONEncoder().encode(pending), forKey: queueKey(owner))
        } while flushAgain && !pending.isEmpty
    }

    /// Для тестов: дождаться всех запущенных загрузок и отправок.
    func settle() async {
        while let task = running.values.first { await task.value }
    }

    // MARK: - Внутреннее

    private var ownerKey: String { "\(name).user" }
    private func copyKey(_ user: String) -> String { Self.copyKey(name, user) }
    private static func copyKey(_ name: String, _ user: String) -> String { "\(name).\(user).v1" }

    /// Сохранённая копия последнего вошедшего — без аккаунта и сети, для фоновой задачи без сцены.
    static func storedValue(name: String, defaults: UserDefaults) -> [String: Item] {
        guard let owner = defaults.string(forKey: "\(name).user") else { return [:] }
        return decode([String: Item].self, defaults.data(forKey: copyKey(name, owner))) ?? [:]
    }
    private func queueKey(_ user: String) -> String { "\(name).\(user).queue.v1" }

    private func run(_ work: @escaping @MainActor (SyncedCollection) async -> Void) {
        let id = UUID()
        running[id] = Task { [weak self] in
            if let self { await work(self) }
            self?.running[id] = nil
        }
    }

    // shortcut: пишем всю копию при каждом изменении (позиция — раз в 10 с); выборочная запись — если записей станут тысячи.
    private func save(_ value: [String: Item], owner: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: copyKey(owner))
        defaults.set(try? JSONEncoder().encode(pending), forKey: queueKey(owner))
    }

    private func wipe() {
        if let owner {
            defaults.removeObject(forKey: copyKey(owner))
            defaults.removeObject(forKey: queueKey(owner))
        }
        defaults.removeObject(forKey: ownerKey)
        owner = nil
        pending = [:]
        lastRefresh = nil
        if !subject.value.isEmpty { subject.send([:]) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
