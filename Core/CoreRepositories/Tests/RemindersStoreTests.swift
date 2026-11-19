import Combine
import CoreDomain
import Foundation
import Testing
import UserNotifications
@testable import CoreRepositories

@MainActor
final class FakeCenter: UserNotificationCenter {
    var granted = true
    var authorizationRequests = 0
    var pending: [UNNotificationRequest] = []
    /// Задержать ответы до `release…()`: так воспроизводим гонки с настоящим (асинхронным) центром.
    var holdAuthorization = false
    var holdLoads = false
    private var authorizationGate: CheckedContinuation<Void, Never>?
    private var loadGate: CheckedContinuation<Void, Never>?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests += 1
        if holdAuthorization { await withCheckedContinuation { authorizationGate = $0 } }
        return granted
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        let snapshot = pending // снимок до ожидания, как у настоящего центра
        if holdLoads { await withCheckedContinuation { loadGate = $0 } }
        return snapshot
    }

    func releaseAuthorization() async {
        await waitUntil { self.authorizationGate != nil }
        holdAuthorization = false
        authorizationGate?.resume()
        authorizationGate = nil
    }

    func releaseLoad() async {
        await waitUntil { self.loadGate != nil }
        holdLoads = false
        loadGate?.resume()
        loadGate = nil
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    /// Абсолютный момент срабатывания; nil, если триггер «плавающий» (без часового пояса).
    func fireDate(_ id: String) -> Date? {
        guard let trigger = pending.first(where: { $0.identifier == id })?.trigger as? UNCalendarNotificationTrigger,
              trigger.dateComponents.timeZone != nil else { return nil }
        return trigger.nextTriggerDate()
    }
}

@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
    #expect(condition())
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func match(_ id: String = "football:1", in minutes: Double = 60, status: MatchStatus = .scheduled) -> Match {
    Match(
        id: MatchID(rawValue: id), sport: .football, competition: Competition(code: "PL", name: "АПЛ"),
        kickoff: now.addingTimeInterval(minutes * 60), status: status,
        home: Team(name: "Ливерпуль", abbreviation: "LIV"), away: Team(name: "Арсенал", abbreviation: "ARS"),
        homeScore: nil, awayScore: nil, round: "12 тур", homeTeamID: "64", awayTeamID: "57"
    )
}

@MainActor
struct RemindersStoreTests {
    let center = FakeCenter()

    func makeStore() async -> LocalRemindersStore {
        let store = LocalRemindersStore(center: center, now: { now })
        await store.idle()
        return store
    }

    @Test func schedulesFifteenMinutesBefore() async throws {
        let store = await makeStore()
        #expect(center.authorizationRequests == 0) // при создании разрешение не спрашиваем

        #expect(try await store.schedule(match()) == .scheduled)
        #expect(center.authorizationRequests == 1)
        #expect(store.scheduled == [MatchID(rawValue: "football:1")])
        let request = try #require(center.pending.first)
        #expect(request.identifier == "football:1")
        #expect(request.content.title == "Скоро матч")
        #expect(request.content.body == "Ливерпуль — Арсенал через 15 минут")
        #expect(center.fireDate("football:1") == now.addingTimeInterval(45 * 60))
    }

    @Test func deniedKeepsSetUnchanged() async throws {
        center.granted = false
        let store = await makeStore()
        var received: [Set<MatchID>] = []
        let cancellable = store.scheduledPublisher.sink { received.append($0) }

        #expect(try await store.schedule(match()) == .denied)
        cancellable.cancel()
        #expect(store.scheduled.isEmpty)
        #expect(center.pending.isEmpty)
        #expect(received == [[]])
    }

    @Test func tooLateWithinFifteenMinutes() async throws {
        let store = await makeStore()
        #expect(try await store.schedule(match(in: 10)) == .tooLate)
        #expect(try await store.schedule(match(status: .live)) == .tooLate)
        #expect(center.authorizationRequests == 0)
        #expect(store.scheduled.isEmpty)
    }

    @Test func tooLateExactlyFifteenMinutes() async throws {
        #expect(try await makeStore().schedule(match(in: 15)) == .tooLate)
    }

    @Test func triggerIsAbsoluteInstant() async throws {
        let store = await makeStore()
        _ = try await store.schedule(match())
        let trigger = try #require(center.pending.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.timeZone != nil)
        #expect(trigger.nextTriggerDate() == now.addingTimeInterval(45 * 60))
    }

    @Test func cancelDuringHeldLoadWins() async throws {
        let store = await makeStore()
        _ = try await store.schedule(match())
        center.holdLoads = true
        store.reconcile(with: [])             // загрузка снимает снимок с напоминанием и ждёт
        await waitUntil { center.holdLoads && center.pending.count == 1 }
        store.cancel(MatchID(rawValue: "football:1"))
        #expect(store.scheduled.isEmpty)
        await center.releaseLoad()
        await store.idle()
        #expect(store.scheduled.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func scheduleSurvivesConcurrentReconcile() async throws {
        let store = await makeStore()
        center.holdAuthorization = true
        center.holdLoads = true
        let scheduling = Task { try await store.schedule(match()) }
        await waitUntil { center.authorizationRequests == 1 }
        store.reconcile(with: [])             // загрузка не должна затереть напоминание, которое ещё ставится
        await center.releaseAuthorization()
        await center.releaseLoad()
        #expect(try await scheduling.value == .scheduled)
        await store.idle()
        #expect(store.scheduled == [MatchID(rawValue: "football:1")])
    }

    @Test func cancelWhileSchedulingWins() async throws {
        let store = await makeStore()
        center.holdAuthorization = true
        let scheduling = Task { try await store.schedule(match()) }
        await waitUntil { center.authorizationRequests == 1 }
        store.cancel(MatchID(rawValue: "football:1"))
        await center.releaseAuthorization()
        _ = try await scheduling.value
        await store.idle()
        #expect(store.scheduled.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func cancelRemovesRequest() async throws {
        let store = await makeStore()
        _ = try await store.schedule(match())
        store.cancel(MatchID(rawValue: "football:1"))
        await store.idle()
        #expect(store.scheduled.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func survivesRelaunch() async throws {
        _ = try await makeStore().schedule(match())
        let relaunched = await makeStore()
        #expect(relaunched.scheduled == [MatchID(rawValue: "football:1")])
    }

    @Test func reconcileMovesTime() async throws {
        let store = await makeStore()
        _ = try await store.schedule(match())
        store.reconcile(with: [match(in: 120)])
        await store.idle()
        #expect(store.scheduled == [MatchID(rawValue: "football:1")])
        #expect(center.pending.count == 1)
        #expect(center.fireDate("football:1") == now.addingTimeInterval(105 * 60))
    }

    @Test(arguments: [MatchStatus.live, .paused, .finished, .cancelled, .postponed])
    func reconcileDropsStartedOrCancelled(status: MatchStatus) async throws {
        let store = await makeStore()
        _ = try await store.schedule(match())
        store.reconcile(with: [match(status: status)])
        await store.idle()
        #expect(store.scheduled.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func reconcileDropsMovedTooEarly() async throws {
        let store = await makeStore()
        _ = try await store.schedule(match())
        store.reconcile(with: [match(in: 5)])
        await store.idle()
        #expect(store.scheduled.isEmpty)
    }

    @Test func reconcileIgnoresOthersAndPicksUpFired() async throws {
        let store = await makeStore()
        _ = try await store.schedule(match("football:1"))
        _ = try await store.schedule(match("football:2"))
        center.pending.removeAll { $0.identifier == "football:2" } // уведомление уже показано
        store.reconcile(with: [match("football:3")])
        await store.idle()
        #expect(store.scheduled == [MatchID(rawValue: "football:1")])
        #expect(center.pending.map(\.identifier) == ["football:1"])
    }
}
