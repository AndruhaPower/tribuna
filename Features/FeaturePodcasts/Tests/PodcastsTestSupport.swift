import Combine
import CoreDomain
import Foundation
@testable import FeaturePodcasts

/// «Сейчас» тестов — 20 нояб 2026, 12:00 по Москве.
let testNow = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00+03:00")!

var testCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
    return calendar
}

func days(_ count: Double) -> TimeInterval { count * 24 * 3600 }

func podcast(_ id: String, _ title: String, order: Int? = nil) -> Podcast {
    Podcast(
        id: id, title: title, author: "Автор \(id)", feedURL: URL(string: "https://example.com/\(id).xml")!,
        artworkURL: URL(string: "https://example.com/\(id).jpg")!, featuredOrder: order
    )
}

func episode(_ podcastID: String, _ guid: String, _ title: String = "Выпуск", ago: TimeInterval, minutes: Double? = 34) -> Episode {
    Episode(
        id: EpisodeID(podcastID: podcastID, guid: guid), podcastID: podcastID, title: title,
        publishedAt: testNow.addingTimeInterval(-ago), duration: minutes.map { $0 * 60 },
        audioURL: URL(string: "https://example.com/\(podcastID)/\(guid).mp3")!, artworkURL: nil, link: nil
    )
}

struct FakeError: Error {}

final class FakePodcastsRepository: PodcastsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<[Podcast], FakeError>
    private var _calls = 0

    init(_ podcasts: [Podcast]) { _result = .success(podcasts) }

    var result: Result<[Podcast], FakeError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var calls: Int { lock.withLock { _calls } }

    func podcasts() async throws -> [Podcast] {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

/// Ленты по id подкаста; нет ленты — ошибка. Запоминает запросы (id и `forceRefresh`).
final class FakeEpisodesRepository: EpisodesRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _feeds: [String: [Episode]]
    private var _calls: [(String, Bool)] = []

    init(_ feeds: [String: [Episode]]) { _feeds = feeds }

    var feeds: [String: [Episode]] {
        get { lock.withLock { _feeds } }
        set { lock.withLock { _feeds = newValue } }
    }

    var calls: [(id: String, force: Bool)] { lock.withLock { _calls } }

    func episodes(for podcast: Podcast, forceRefresh: Bool) async throws -> [Episode] {
        try lock.withLock {
            _calls.append((podcast.id, forceRefresh))
            guard let feed = _feeds[podcast.id] else { throw FakeError() }
            return feed
        }
    }
}

@MainActor
final class FakeSubscriptionsStore: SubscriptionsStore {
    let subject: CurrentValueSubject<[String: Date], Never>

    init(_ subscriptions: [String: Date] = [:]) { subject = CurrentValueSubject(subscriptions) }

    var subscriptions: [String: Date] { subject.value }
    var subscriptionsPublisher: AnyPublisher<[String: Date], Never> { subject.eraseToAnyPublisher() }

    func toggle(_ podcastID: String) {
        var value = subject.value
        if value.removeValue(forKey: podcastID) == nil { value[podcastID] = testNow }
        subject.send(value)
    }
}

@MainActor
final class FakeProgressStore: ListeningProgressStore {
    let subject: CurrentValueSubject<[EpisodeID: ListeningProgress], Never>

    init(_ progress: [EpisodeID: ListeningProgress] = [:]) { subject = CurrentValueSubject(progress) }

    var progress: [EpisodeID: ListeningProgress] { subject.value }
    var progressPublisher: AnyPublisher<[EpisodeID: ListeningProgress], Never> { subject.eraseToAnyPublisher() }

    func setPosition(_ position: TimeInterval, for id: EpisodeID) {
        subject.value[id, default: ListeningProgress(position: 0, isFinished: false)].position = position
    }

    func markFinished(_ id: EpisodeID) { subject.value[id] = ListeningProgress(position: 0, isFinished: true) }
}

@MainActor
final class FakeAudioPlayer: AudioPlayer {
    let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
    private(set) var played: [EpisodeID] = []
    private(set) var toggles = 0

    var state: PlaybackState { subject.value }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    func set(_ episode: Episode, _ podcast: Podcast, _ status: PlaybackStatus) {
        subject.value = PlaybackState(item: .episode(episode, podcast: podcast), status: status, sleepTimerEndsAt: nil)
    }

    func play(_ item: PlaybackItem) { item.episode.map { played.append($0.id) } }
    func togglePlayPause() { toggles += 1 }
    func stop() {}
    func setSleepTimer(minutes: Int?) {}
    func seek(to position: TimeInterval) {}
    func skip(by seconds: TimeInterval) {}
    func setRate(_ rate: Float) {}
}

/// Загрузки в памяти: новые записи — первыми, как у настоящих. Запоминает вызовы `download` и `remove`.
@MainActor
final class FakeDownloads: EpisodeDownloads {
    let subject: CurrentValueSubject<[DownloadedEpisode], Never>
    var wifiOnly = true
    private(set) var downloaded: [EpisodeID] = []
    private(set) var removed: [EpisodeID] = []

    init(_ items: [DownloadedEpisode] = []) { subject = CurrentValueSubject(items) }

    var items: [DownloadedEpisode] { subject.value }
    var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { subject.eraseToAnyPublisher() }

    func set(_ id: EpisodeID, _ state: DownloadState) {
        if let index = subject.value.firstIndex(where: { $0.id == id }) { subject.value[index].state = state }
    }

    func download(_ episode: Episode, podcast: Podcast) {
        downloaded.append(episode.id)
        subject.value.removeAll { $0.id == episode.id }
        subject.value.insert(DownloadedEpisode(episode: episode, podcast: podcast, addedAt: testNow, state: .waiting, artworkFile: nil), at: 0)
    }

    func remove(_ id: EpisodeID) {
        removed.append(id)
        subject.value.removeAll { $0.id == id }
    }

    func removeAll() { subject.value = [] }
    func localFile(for id: EpisodeID) -> URL? { nil }
    func usage() -> (bytes: Int64, count: Int) { (0, 0) }
    func availableCapacity() -> Int64? { nil }
}

func download(_ episode: Episode, _ podcast: Podcast, _ state: DownloadState, ago: TimeInterval = days(1), artwork: URL? = nil) -> DownloadedEpisode {
    DownloadedEpisode(episode: episode, podcast: podcast, addedAt: testNow.addingTimeInterval(-ago), state: state, artworkFile: artwork)
}

let testUser = UserProfile(id: "user", name: nil, email: "user@example.com")

/// Аккаунт для ворот (D31): только состояние; операции входа фичам не нужны.
@MainActor
final class FakeAccount: Account {
    let subject: CurrentValueSubject<AccountState, Never>

    init(_ state: AccountState = .signedIn(testUser)) { subject = CurrentValueSubject(state) }

    var state: AccountState { subject.value }
    var statePublisher: AnyPublisher<AccountState, Never> { subject.eraseToAnyPublisher() }
    var userID: String? { if case let .signedIn(user) = state { user.id } else { nil } }

    func signUp(name: String, email: String, password: String) async throws {}
    func confirmSignUp(email: String, code: String) async throws {}
    func resendSignUpCode(email: String) async throws {}
    func signIn(email: String, password: String) async throws {}
    func requestPasswordReset(email: String) async throws {}
    func resetPassword(email: String, code: String, newPassword: String) async throws {}
    func signOut() async {}
    func deleteAccount() async throws {}
}

/// Фейковые ворота (D31): вошёл — действие сразу, как у приложения; иначе запоминает повод и ждёт `signIn()` / `cancel()`.
@MainActor
final class FakeSignIn {
    let account: FakeAccount
    private(set) var reasons: [SignInReason] = []
    private var pending: (@MainActor () -> Void)?

    init(_ account: FakeAccount = FakeAccount()) { self.account = account }

    func require(_ reason: SignInReason, then action: @escaping @MainActor () -> Void) {
        if case .signedIn = account.state { return action() }
        reasons.append(reason)
        pending = action
    }

    /// Вход удался: аккаунт во входе, затем действие.
    func signIn() {
        account.subject.send(.signedIn(testUser))
        pending?()
        pending = nil
    }

    /// Лист закрыли без входа.
    func cancel() { pending = nil }
}
