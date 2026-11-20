import Combine
import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

@MainActor
final class FakeReminders: RemindersStore {
    let subject = CurrentValueSubject<Set<MatchID>, Never>([])
    var scheduled: Set<MatchID> { subject.value }
    var scheduledPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }
    func schedule(_ match: Match) async throws -> ReminderResult {
        subject.value.insert(match.id)
        return .scheduled
    }
    func cancel(_ id: MatchID) { subject.value.remove(id) }
    func reconcile(with matches: [Match]) {}
}

@MainActor
final class CountingDownloads: EpisodeDownloads {
    var removeAllCalls = 0
    var items: [DownloadedEpisode] { [] }
    var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { Just([]).eraseToAnyPublisher() }
    var wifiOnly = true
    func download(_ episode: Episode, podcast: Podcast) {}
    func remove(_ id: EpisodeID) {}
    func removeAll() { removeAllCalls += 1 }
    func localFile(for id: EpisodeID) -> URL? { nil }
    func usage() -> (bytes: Int64, count: Int) { (0, 0) }
    func availableCapacity() -> Int64? { nil }
}

@MainActor
struct AccountCleanupTests {
    let defaults: UserDefaults = {
        let name = "AccountCleanupTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }()
    let reminders = FakeReminders()
    let downloads = CountingDownloads()

    func make(_ account: Account) -> AccountCleanup {
        AccountCleanup(account: account, reminders: reminders, downloads: downloads, defaults: defaults)
    }

    @Test func accountCleanupOnSignOut() async {
        let account = FakeAccount(user("a"))
        let cleanup = make(account)
        reminders.subject.value = [MatchID(rawValue: "football:1"), MatchID(rawValue: "football:2")]
        #expect(downloads.removeAllCalls == 0)
        await account.signOut()
        #expect(reminders.scheduled.isEmpty)
        #expect(downloads.removeAllCalls == 1)
        withExtendedLifetime(cleanup) {}
    }

    @Test func accountCleanupOnUserSwitch() {
        let account = FakeAccount(user("a"))
        let cleanup = make(account)
        reminders.subject.value = [MatchID(rawValue: "football:1")]
        account.subject.send(user("a")) // тот же — ничего
        #expect(downloads.removeAllCalls == 0)
        account.subject.send(user("b"))
        #expect(reminders.scheduled.isEmpty)
        #expect(downloads.removeAllCalls == 1)
        withExtendedLifetime(cleanup) {}
    }

    /// Запуск без входа: владельца нет — ничего не трогаем.
    @Test func unknownToSignedOutWithoutOwnerDoesNothing() {
        let account = FakeAccount(.unknown)
        let cleanup = make(account)
        reminders.subject.value = [MatchID(rawValue: "football:1")]
        account.subject.send(.signedOut)
        #expect(reminders.scheduled.count == 1)
        #expect(downloads.removeAllCalls == 0)
        withExtendedLifetime(cleanup) {}
    }

    /// Сессию потеряли, пока приложение не работало: владелец сохранён, состояние разрешилось в `signedOut`.
    /// Напоминания центр отдаёт асинхронно — пришедшие позже тоже снимаются, пока нет входа.
    @Test func launchWithLostSessionCleansUpIncludingLateReminders() {
        _ = make(FakeAccount(user("a"))) // прошлый запуск: вошёл «a»
        let account = FakeAccount(.unknown)
        let cleanup = make(account)
        #expect(downloads.removeAllCalls == 0)
        account.subject.send(.signedOut)
        #expect(downloads.removeAllCalls == 1)
        reminders.subject.value = [MatchID(rawValue: "football:1")]
        #expect(reminders.scheduled.isEmpty)
        // Вошли снова — новые напоминания не трогаем.
        account.subject.send(user("b"))
        reminders.subject.value = [MatchID(rawValue: "football:2")]
        #expect(reminders.scheduled.count == 1)
        withExtendedLifetime(cleanup) {}
    }

    @Test func launchWithSameUserDoesNothing() {
        _ = make(FakeAccount(user("a")))
        let account = FakeAccount(.unknown)
        let cleanup = make(account)
        reminders.subject.value = [MatchID(rawValue: "football:1")]
        account.subject.send(user("a"))
        #expect(reminders.scheduled.count == 1)
        #expect(downloads.removeAllCalls == 0)
        withExtendedLifetime(cleanup) {}
    }
}
