import Combine
import CoreDomain
import Foundation
import Testing
@testable import FeatureProfile

@MainActor
final class FakeBookmarksStore: BookmarksStore {
    let subject = CurrentValueSubject<Set<MatchID>, Never>([])
    var bookmarks: Set<MatchID> { subject.value }
    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }
    func toggle(_ id: MatchID) {
        if subject.value.contains(id) { subject.value.remove(id) } else { subject.value.insert(id) }
    }
}

@MainActor
final class FakeSubscriptionsStore: SubscriptionsStore {
    let subject = CurrentValueSubject<[String: Date], Never>([:])
    var subscriptions: [String: Date] { subject.value }
    var subscriptionsPublisher: AnyPublisher<[String: Date], Never> { subject.eraseToAnyPublisher() }
    func toggle(_ podcastID: String) {
        subject.value[podcastID] = subject.value[podcastID] == nil ? Date() : nil
    }
}

/// `usage()` — по скачанным записям, у каждой `bytes` из состояния.
@MainActor
final class FakeDownloads: EpisodeDownloads {
    let subject = CurrentValueSubject<[DownloadedEpisode], Never>([])
    var wifiOnly = true
    var available: Int64? = 0
    private(set) var capacityCalls = 0

    var items: [DownloadedEpisode] { subject.value }
    var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { subject.eraseToAnyPublisher() }

    func add(_ guid: String, _ state: DownloadState) {
        let episode = Episode(id: EpisodeID(podcastID: "p", guid: guid), podcastID: "p", title: guid, publishedAt: Date(),
                              duration: 60, audioURL: URL(string: "https://example.com/\(guid).mp3")!, artworkURL: nil, link: nil)
        let podcast = Podcast(id: "p", title: "П", author: "А", feedURL: URL(string: "https://example.com/p.xml")!,
                              artworkURL: URL(string: "https://example.com/p.jpg")!, featuredOrder: nil)
        subject.value.append(DownloadedEpisode(episode: episode, podcast: podcast, addedAt: Date(), state: state, artworkFile: nil))
    }

    func download(_ episode: Episode, podcast: Podcast) {}
    func remove(_ id: EpisodeID) { subject.value.removeAll { $0.id == id } }
    func removeAll() { subject.value = [] }
    func localFile(for id: EpisodeID) -> URL? { nil }
    func usage() -> (bytes: Int64, count: Int) {
        items.reduce((0, 0)) { total, item in
            if case let .downloaded(bytes) = item.state { (total.0 + bytes, total.1 + 1) } else { total }
        }
    }
    func availableCapacity() -> Int64? {
        capacityCalls += 1
        return available
    }

    func set(_ guid: String, _ state: DownloadState) {
        if let index = subject.value.firstIndex(where: { $0.id == EpisodeID(podcastID: "p", guid: guid) }) { subject.value[index].state = state }
    }
}

@MainActor
struct ProfileTests {
    let bookmarks = FakeBookmarksStore()
    let subscriptions = FakeSubscriptionsStore()
    let downloads = FakeDownloads()
    let account = FakeAccount(.signedIn(UserProfile(id: "u", name: "Алексей", email: "a@b.ru")))
    let avatars = FakeAvatarStore()
    let log = Box<[String]>([])

    #if FEATURE_PROFILE2
    let settings = FakeProfileSettings()
    let notificationsGranted = Box(true)

    var dependencies: FeatureProfile.Dependencies {
        .init(account: account, bookmarks: bookmarks, subscriptions: subscriptions, downloads: downloads, avatars: avatars,
              settings: settings, competitions: FakeCompetitions(), renaming: account)
    }

    func output(flush: @escaping @MainActor () async -> Void) -> FeatureProfile.Output {
        .init(flushUserData: flush, requestNotifications: { [notificationsGranted] in notificationsGranted.value }, openSettings: {})
    }
    #else
    var dependencies: FeatureProfile.Dependencies {
        .init(account: account, bookmarks: bookmarks, subscriptions: subscriptions, downloads: downloads, avatars: avatars)
    }

    func output(flush: @escaping @MainActor () async -> Void) -> FeatureProfile.Output { .init(flushUserData: flush) }
    #endif

    func makeViewModel() -> ProfileViewModel {
        account.log = { [log] in log.value.append($0) }
        return ProfileViewModel(dependencies: dependencies, output: output { [log] in log.value.append("flush") })
    }

    @Test func signedOutShowsMotivationOnly() {
        account.subject.send(.unknown)
        let viewModel = makeViewModel()
        // Сессия читается — ни мотивации, ни карточки.
        #expect(viewModel.state.account == nil)
        #expect(viewModel.state.isResolving)
        account.subject.send(.signedOut)
        #expect(viewModel.state.account == nil)
        #expect(!viewModel.state.isResolving)
    }

    /// Отправка не слышит отмены и висит — выход всё равно через таймаут.
    @Test func signOutDoesNotWaitForHangingFlush() async {
        let hang = Box<CheckedContinuation<Void, Never>?>(nil)
        let viewModel = ProfileViewModel(
            dependencies: dependencies,
            output: output { await withCheckedContinuation { hang.value = $0 } },
            flushTimeout: 0.05
        )
        await viewModel.didConfirmSignOut()
        #expect(account.calls == ["signOut"])
        #expect(viewModel.state.account == nil)
        hang.value?.resume()
    }

    @Test func signedInShowsAccountCard() {
        let viewModel = makeViewModel()
        #expect(viewModel.state.account == AccountCard(name: "Алексей", email: "a@b.ru", initial: "А"))
        account.subject.send(.signedIn(UserProfile(id: "u", name: "  ", email: "x@y.ru")))
        #expect(viewModel.state.account == AccountCard(name: "Болельщик", email: "x@y.ru", initial: "Б"))
        account.subject.send(.signedIn(UserProfile(id: "u", name: nil, email: "x@y.ru")))
        #expect(viewModel.state.account?.name == "Болельщик")
        account.subject.send(.signedIn(UserProfile(id: "u", name: "ёжик", email: "x@y.ru")))
        #expect(viewModel.state.account?.initial == "Ё")
    }

    @Test func signOutFlushesThenSignsOut() async {
        #expect(ProfileTexts.signOutConfirm == "Выйти из профиля? Загрузки будут удалены с телефона")
        let viewModel = makeViewModel()
        await viewModel.didConfirmSignOut()
        #expect(log.value == ["flush", "signOut"])
        #expect(viewModel.state.account == nil)
    }

    @Test func deleteAccountSucceeds() async {
        #expect(ProfileTexts.deleteConfirm == "Удалить аккаунт? Закладки, подписки и история прослушивания удалятся навсегда")
        let viewModel = makeViewModel()
        let error = await viewModel.didConfirmDelete()
        #expect(error == nil)
        #expect(account.calls == ["deleteAccount"])
        #expect(viewModel.state.account == nil)
    }

    @Test func deleteAccountFailureKeepsSignedIn() async {
        account.errors["deleteAccount"] = .network
        let viewModel = makeViewModel()
        let error = await viewModel.didConfirmDelete()
        #expect(error == "Нет соединения")
        #expect(viewModel.state.account != nil)
        #expect(!viewModel.state.isBusy)
    }

    @Test func countersFollowStores() {
        let viewModel = makeViewModel()
        #expect((viewModel.state.bookmarks, viewModel.state.subscriptions) == ("0", "0"))
        for id in ["a", "b", "c", "d"] { bookmarks.toggle(MatchID(rawValue: id)) }
        for id in ["x", "y", "z"] { subscriptions.toggle(id) }
        #expect((viewModel.state.bookmarks, viewModel.state.subscriptions) == ("4", "3"))
        subscriptions.toggle("x")
        #expect(viewModel.state.subscriptions == "2")
    }

    @Test func usageText() {
        let viewModel = makeViewModel()
        #expect(viewModel.state.usage == "Нет загрузок")
        // Идущая загрузка ещё не занимает места.
        downloads.add("w", .downloading(progress: 0.5))
        #expect(viewModel.state.usage == "Нет загрузок")
        downloads.add("a", .downloaded(bytes: 412_000_000))
        #expect(viewModel.state.usage == "412 МБ · 1 выпуск")
        downloads.add("b", .downloaded(bytes: 0))
        #expect(viewModel.state.usage == "412 МБ · 2 выпуска")
        for guid in ["c", "d", "e"] { downloads.add(guid, .downloaded(bytes: 0)) }
        #expect(viewModel.state.usage == "412 МБ · 5 выпусков")
        #expect(ProfileFormatter.episodes(11) == "11 выпусков")
        #expect(ProfileFormatter.episodes(21) == "21 выпуск")
        #expect(ProfileFormatter.episodes(22) == "22 выпуска")
    }

    @Test func usageFraction() {
        downloads.available = 300
        let viewModel = makeViewModel()
        // Нет загрузок — полоски нет.
        #expect(viewModel.state.usageFraction == nil)
        downloads.add("a", .downloaded(bytes: 100))
        #expect(viewModel.state.usageFraction == 0.25)
        // Свободное место не узнать — полоска пустая.
        downloads.available = nil
        viewModel.didEnterForeground()
        #expect(viewModel.state.usageFraction == 0)
        // Свободное место меняется без загрузок — пересчёт при возврате из фона.
        downloads.available = 100
        viewModel.didEnterForeground()
        #expect(viewModel.state.usageFraction == 0.5)
    }

    /// Тик прогресса не меняет занятое место — система про свободное место не спрашивается.
    @Test func capacityNotQueriedOnProgressTicks() {
        downloads.add("a", .downloaded(bytes: 100))
        let viewModel = makeViewModel()
        let calls = downloads.capacityCalls
        downloads.add("w", .downloading(progress: 0.1))
        downloads.set("w", .downloading(progress: 0.5))
        #expect(downloads.capacityCalls == calls)
        downloads.set("w", .downloaded(bytes: 50))
        #expect(downloads.capacityCalls == calls + 1)
        viewModel.didEnterForeground()
        #expect(downloads.capacityCalls == calls + 2)
        viewModel.didConfirmClear()
        #expect(downloads.capacityCalls >= calls + 3)
    }

    @Test func clearDisabledWhenEmpty() {
        let viewModel = makeViewModel()
        #expect(!viewModel.state.canClear)
        downloads.add("w", .waiting)
        #expect(viewModel.state.canClear)
        viewModel.didConfirmClear()
        #expect(downloads.items.isEmpty)
        #expect(!viewModel.state.canClear)
    }

    @Test func wifiToggleWritesThrough() {
        downloads.wifiOnly = false
        let viewModel = makeViewModel()
        #expect(!viewModel.state.wifiOnly)
        viewModel.didToggleWifiOnly(true)
        #expect(downloads.wifiOnly)
        #expect(viewModel.state.wifiOnly)
    }
}
