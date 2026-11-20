import Combine
import CoreDomain
import Foundation
import Testing
import UIKit
@testable import CoreRepositories

@MainActor
final class FakeAccount: Account {
    let subject: CurrentValueSubject<AccountState, Never>
    init(_ state: AccountState) { subject = CurrentValueSubject(state) }
    var state: AccountState { subject.value }
    var statePublisher: AnyPublisher<AccountState, Never> { subject.removeDuplicates().eraseToAnyPublisher() }
    var userID: String? { if case let .signedIn(user) = state { user.id } else { nil } }
    func signUp(name: String, email: String, password: String) async throws {}
    func confirmSignUp(email: String, code: String) async throws {}
    func resendSignUpCode(email: String) async throws {}
    func signIn(email: String, password: String) async throws {}
    func requestPasswordReset(email: String) async throws {}
    func resetPassword(email: String, code: String, newPassword: String) async throws {}
    func signOut() async { subject.send(.signedOut) }
    func deleteAccount() async throws {}
}

func user(_ id: String) -> AccountState { .signedIn(UserProfile(id: id, name: nil, email: "\(id)@example.com")) }

/// Сервер в памяти: строки по пользователям, счётчики запросов.
actor FakeRemote<Item: SyncItem>: UserDataRemote {
    struct Down: Error {}
    var rows: [String: [String: Item]] = [:]
    var fetches = 0, upserts = 0, deletes = 0
    var failing = false
    /// Чтение работает, запись падает.
    var failingWrites = false

    func set(_ rows: [String: Item], for user: String) { self.rows[user] = rows }
    func setFailing(_ failing: Bool) { self.failing = failing }
    func setFailingWrites(_ failing: Bool) { failingWrites = failing }

    func fetch(userID: String) async throws -> [String: Item] {
        fetches += 1
        if failing { throw Down() }
        return rows[userID] ?? [:]
    }

    func upsert(_ items: [String: Item], userID: String) async throws {
        upserts += 1
        if failing || failingWrites { throw Down() }
        rows[userID, default: [:]].merge(items) { $1 }
    }

    func delete(_ keys: [String], userID: String) async throws {
        deletes += 1
        if failing || failingWrites { throw Down() }
        for key in keys { rows[userID]?[key] = nil }
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
struct SyncedStoresTests {
    let suite = "SyncedStoresTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let clock = TestClock()
    let notifications = NotificationCenter()
    let a = MatchID(sport: .football, sourceID: "1")
    let b = MatchID(sport: .football, sourceID: "2")
    let episode = EpisodeID(podcastID: "p1", guid: "g1")

    init() throws { defaults = try #require(UserDefaults(suiteName: suite)) }

    func bookmarks(_ account: Account, _ remote: FakeRemote<Date>?) -> SyncedBookmarksStore {
        SyncedBookmarksStore(defaults: defaults, account: account, remote: remote, notifications: notifications, now: { [clock] in clock.now })
    }

    func subscriptions(_ account: Account, _ remote: FakeRemote<Date>? = nil) -> SyncedSubscriptionsStore {
        SyncedSubscriptionsStore(defaults: defaults, account: account, remote: remote, notifications: notifications, now: { [clock] in clock.now })
    }

    func progress(_ account: Account, _ remote: FakeRemote<ProgressRecord>? = nil) -> SyncedListeningProgressStore {
        SyncedListeningProgressStore(defaults: defaults, account: account, remote: remote, notifications: notifications, now: { [clock] in clock.now })
    }

    func cleanup() { defaults.removePersistentDomain(forName: suite) }

    @Test func signedOutIsEmptyAndIgnoresWrites() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        let store = bookmarks(FakeAccount(.signedOut), remote)
        store.toggle(a)
        await store.collection.settle()
        #expect(store.bookmarks.isEmpty)
        #expect(await remote.upserts == 0)
        #expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("bookmarks") })
    }

    @Test func signInReplacesLocalWithRemote() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        await remote.set([a.rawValue: clock.now], for: "u1")
        let account = FakeAccount(.signedOut)
        let store = bookmarks(account, remote)
        account.subject.send(user("u1"))
        await store.collection.settle()
        #expect(store.bookmarks == [a])
    }

    @Test func unknownShowsCachedCopyThenServerReplacesIt() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        bookmarks(FakeAccount(user("u1")), nil).toggle(b)
        await remote.set([a.rawValue: clock.now], for: "u1")

        let account = FakeAccount(.unknown)
        let store = bookmarks(account, remote)
        #expect(store.bookmarks == [b])
        await store.collection.settle()
        #expect(await remote.fetches == 0)
        account.subject.send(user("u1"))
        await store.collection.settle()
        // Неотправленная закладка b (удалённого источника не было) остаётся поверх серверной a.
        #expect(store.bookmarks == [a, b])
        #expect(await remote.rows["u1"]?.keys.sorted() == [a.rawValue, b.rawValue])
    }

    @Test func launchWithLostSessionWipesCachedCopy() async {
        defer { cleanup() }
        bookmarks(FakeAccount(user("u1")), nil).toggle(a)
        let account = FakeAccount(.unknown)
        let store = bookmarks(account, nil)
        #expect(store.bookmarks == [a])
        account.subject.send(.signedOut)
        #expect(store.bookmarks.isEmpty)
        #expect(bookmarks(FakeAccount(.unknown), nil).bookmarks.isEmpty)
    }

    @Test func toggleWritesLocalAndPushes() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        let store = bookmarks(FakeAccount(user("u1")), remote)
        await store.collection.settle()
        store.toggle(a)
        #expect(store.bookmarks == [a])
        await store.collection.settle()
        #expect(await remote.rows["u1"] == [a.rawValue: clock.now])
        store.toggle(a)
        await store.collection.settle()
        #expect(await remote.rows["u1"] == [:])
        #expect(store.collection.pendingCount == 0)
    }

    @Test func offlineChangeQueuedAndFlushedAfterRelaunch() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        await remote.setFailing(true)
        let store = bookmarks(FakeAccount(user("u1")), remote)
        store.toggle(a)
        await store.collection.settle()
        #expect(store.collection.pendingCount == 1)

        await remote.setFailing(false)
        let relaunched = bookmarks(FakeAccount(.unknown), remote)
        #expect(relaunched.bookmarks == [a])
        await relaunched.flush()
        #expect(await remote.rows["u1"] == nil) // без входа не отправляем
        relaunched.collection.apply(user("u1"))
        await relaunched.collection.settle()
        #expect(await remote.rows["u1"] == [a.rawValue: clock.now])
        #expect(relaunched.collection.pendingCount == 0)
    }

    @Test func signOutWipesEverything() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        await remote.setFailing(true)
        let account = FakeAccount(user("u1"))
        let store = bookmarks(account, remote)
        store.toggle(a)
        await store.collection.settle()
        account.subject.send(.signedOut)
        #expect(store.bookmarks.isEmpty)
        #expect(store.collection.pendingCount == 0)
        #expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("bookmarks") })
    }

    @Test func switchingUserWipesAndLoads() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        await remote.set([b.rawValue: clock.now], for: "u2")
        let account = FakeAccount(user("u1"))
        let store = bookmarks(account, remote)
        store.toggle(a)
        await store.collection.settle()
        account.subject.send(user("u2"))
        await store.collection.settle()
        #expect(store.bookmarks == [b])
        #expect(await remote.rows["u1"] == [a.rawValue: clock.now])
    }

    @Test func refreshKeepsUnsentQueue() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        await remote.set([a.rawValue: clock.now], for: "u1")
        let store = bookmarks(FakeAccount(user("u1")), remote)
        await store.collection.settle()
        #expect(store.bookmarks == [a])

        await remote.setFailingWrites(true)
        store.toggle(a) // удаление
        store.toggle(b) // добавление
        // Сервер ещё со старыми данными; обновление их не откатывает.
        await store.refreshFromServer(force: true)
        #expect(store.bookmarks == [b])
        #expect(store.collection.pendingCount == 2)
        await remote.setFailingWrites(false)
        await store.refreshFromServer(force: true)
        #expect(await remote.rows["u1"] == [b.rawValue: clock.now])
        #expect(store.collection.pendingCount == 0)
    }

    @Test func refreshThrottledFiveMinutes() async {
        defer { cleanup() }
        let remote = FakeRemote<Date>()
        let store = bookmarks(FakeAccount(user("u1")), remote)
        await store.collection.settle()
        #expect(await remote.fetches == 1)
        clock.now += 299
        await store.refreshFromServer()
        #expect(await remote.fetches == 1)
        notifications.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await store.collection.settle()
        #expect(await remote.fetches == 1)
        clock.now += 1
        notifications.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await store.collection.settle()
        #expect(await remote.fetches == 2)
        await store.refreshFromServer(force: true)
        #expect(await remote.fetches == 3)
    }

    @Test func progressPushThrottled() async {
        defer { cleanup() }
        let remote = FakeRemote<ProgressRecord>()
        let store = progress(FakeAccount(user("u1")), remote)
        await store.collection.settle()
        for second in stride(from: 0.0, through: 30, by: 7.5) {
            clock.now += 7.5
            store.setPosition(100 + second, for: episode)
            await store.collection.settle()
        }
        #expect(await remote.upserts == 1)
        #expect(await remote.rows["u1"]?[episode.rawValue]?.position == 100)
        store.flushProgress()
        await store.collection.settle()
        #expect(await remote.upserts == 2)
        #expect(await remote.rows["u1"]?[episode.rawValue]?.position == 130)
        clock.now += 60
        store.setPosition(200, for: episode)
        await store.collection.settle()
        #expect(await remote.upserts == 3)
    }

    @Test func progressConflictLaterWins() async {
        defer { cleanup() }
        let remote = FakeRemote<ProgressRecord>()
        let other = EpisodeID(podcastID: "p1", guid: "g2")
        let store = progress(FakeAccount(user("u1")), remote)
        await store.collection.settle()
        await remote.setFailing(true)
        store.setPosition(50, for: episode) // локально в t
        store.setPosition(70, for: other)
        await store.collection.settle()

        await remote.setFailing(false)
        await remote.set([
            episode.rawValue: ProgressRecord(position: 900, isFinished: false, updatedAt: clock.now + 10), // другой телефон позже
            other.rawValue: ProgressRecord(position: 10, isFinished: false, updatedAt: clock.now - 10), // раньше
        ], for: "u1")
        await store.refreshFromServer(force: true)
        #expect(store.position(for: episode) == 900)
        #expect(store.position(for: other) == 70)
        #expect(await remote.rows["u1"]?[other.rawValue]?.position == 70)
        #expect(await remote.rows["u1"]?[episode.rawValue]?.position == 900)
    }

    // MARK: - Перенесённые тесты локальных хранилищ

    @Test func bookmarksToggleAddsRemovesAndPersists() {
        defer { cleanup() }
        let store = bookmarks(FakeAccount(user("u1")), nil)
        store.toggle(a)
        #expect(store.bookmarks == [a])
        #expect(bookmarks(FakeAccount(user("u1")), nil).bookmarks == [a])
        store.toggle(a)
        #expect(store.bookmarks.isEmpty)
    }

    @Test func bookmarksPublisherSendsNewSet() {
        defer { cleanup() }
        let store = bookmarks(FakeAccount(user("u1")), nil)
        var received: [Set<MatchID>] = []
        let cancellable = store.bookmarksPublisher.sink { received.append($0) }
        store.toggle(a)
        cancellable.cancel()
        #expect(received == [[], [a]])
    }

    @Test func subscriptionsToggleWithDateAndPersist() {
        defer { cleanup() }
        let store = subscriptions(FakeAccount(user("u1")))
        var received: [[String: Date]] = []
        let cancellable = store.subscriptionsPublisher.sink { received.append($0) }
        store.toggle("p1")
        #expect(store.subscriptions == ["p1": clock.now])
        #expect(subscriptions(FakeAccount(user("u1"))).subscriptions == ["p1": clock.now])
        store.toggle("p1")
        cancellable.cancel()
        #expect(store.subscriptions.isEmpty)
        #expect(received == [[:], ["p1": clock.now], [:]])
    }

    @Test func progressNotStartedByDefaultAndPersists() {
        defer { cleanup() }
        let store = progress(FakeAccount(user("u1")))
        #expect(store.position(for: episode) == nil)
        #expect(!store.isFinished(episode))
        store.setPosition(42.5, for: episode)
        store.setPosition(120, for: episode)
        let reopened = progress(FakeAccount(user("u1")))
        #expect(reopened.position(for: episode) == 120)
        #expect(!reopened.isFinished(episode))
    }

    @Test func progressMarkFinishedResetsPositionAndSticks() {
        defer { cleanup() }
        let store = progress(FakeAccount(user("u1")))
        var received: [[EpisodeID: ListeningProgress]] = []
        let cancellable = store.progressPublisher.sink { received.append($0) }
        store.setPosition(1900, for: episode)
        store.markFinished(episode)
        #expect(store.isFinished(episode))
        #expect(store.position(for: episode) == 0)
        store.setPosition(30, for: episode)
        cancellable.cancel()
        #expect(progress(FakeAccount(user("u1"))).progress == [episode: ListeningProgress(position: 30, isFinished: true)])
        #expect(received == [[:], [episode: .init(position: 1900, isFinished: false)], [episode: .init(position: 0, isFinished: true)],
                             [episode: .init(position: 30, isFinished: true)]])
    }

    @Test func progressIgnoresCorruptedStorage() {
        defer { cleanup() }
        defaults.set("u1", forKey: "podcasts.progress.user")
        defaults.set(Data("мусор".utf8), forKey: "podcasts.progress.u1.v1")
        #expect(progress(FakeAccount(user("u1"))).progress.isEmpty)
    }

    @Test func progressRowEncodesFlatColumns() throws {
        let row = ProgressRow(userID: "u1", key: "p1:g1", item: ProgressRecord(position: 12.5, isFinished: true, updatedAt: Date(timeIntervalSince1970: 0)))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try #require(JSONSerialization.jsonObject(with: encoder.encode(row)) as? [String: Any])
        #expect(Set(object.keys) == ["user_id", "episode_id", "position", "is_finished", "updated_at"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProgressRow.self, from: encoder.encode(row))
        #expect(decoded.key == "p1:g1" && decoded.item == row.item)
    }
}
