import Combine
import CoreDomain
import Foundation
@testable import CorePlayback

@MainActor
final class FakeEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var played: [URL] = []
    /// Позиции, с которых запускали потоки.
    private(set) var startPositions: [TimeInterval] = []
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var seeks: [TimeInterval] = []
    private(set) var rate: Float = 1
    func play(_ url: URL, from position: TimeInterval) { played.append(url); startPositions.append(position) }
    func stop() { stopCount += 1 }
    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
    func seek(to position: TimeInterval) { seeks.append(position) }
    func setRate(_ rate: Float) { self.rate = rate }
    func send(_ event: PlaybackEngineEvent) { onEvent?(event) }
}

@MainActor
final class FakeSession: AudioSessionControlling {
    var onEvent: ((AudioSessionEvent) -> Void)?
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0
    func activate() throws { activateCount += 1 }
    func deactivate() { deactivateCount += 1 }
    func send(_ event: AudioSessionEvent) { onEvent?(event) }
}

@MainActor
final class FakeNowPlaying: NowPlayingControlling {
    var onCommand: ((RemoteCommand) -> Void)?
    private(set) var info: NowPlayingInfo?
    func update(_ info: NowPlayingInfo?) { self.info = info }
    func send(_ command: RemoteCommand) { onCommand?(command) }
}

@MainActor
final class FakeClock: PlaybackClock {
    // unchecked: флаг пишут только с главного потока или из deinit владельца, когда он уже никому не нужен.
    private final class Job: @unchecked Sendable {
        let fireAt: Date
        let action: @MainActor () -> Void
        var cancelled = false
        init(fireAt: Date, action: @escaping @MainActor () -> Void) { self.fireAt = fireAt; self.action = action }
    }

    private(set) var now = Date(timeIntervalSince1970: 1_000_000)
    private var jobs: [Job] = []
    /// Моделирует гонку: снятая задача всё равно срабатывает.
    var ignoresCancellation = false

    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let job = Job(fireAt: now.addingTimeInterval(seconds), action: action)
        jobs.append(job)
        return AnyCancellable { @Sendable in job.cancelled = true }
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        let due = jobs.filter { (ignoresCancellation || !$0.cancelled) && $0.fireAt <= now }
        jobs.removeAll { $0.cancelled || $0.fireAt <= now }
        due.forEach { $0.action() }
    }

    /// Время идёт, но задачи не срабатывают (приложение спало).
    func skip(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

let matchTV = Station(
    id: "match", name: "Матч ТВ", streamURL: URL(string: "https://example.com/match.mp3")!, country: "RU",
    bitrate: 128, genres: [.sport], subtitle: "Спорт", featuredOrder: 1
)
let sportFM = Station(
    id: "sportfm", name: "Спорт FM", streamURL: URL(string: "http://example.com/sport.aac")!, country: "RU",
    bitrate: nil, genres: [.sport], subtitle: "Спортивное радио", featuredOrder: nil
)

@MainActor
final class FakeProgressStore: ListeningProgressStore {
    let subject = CurrentValueSubject<[EpisodeID: ListeningProgress], Never>([:])
    /// Все сохранения позиции по порядку.
    private(set) var saved: [TimeInterval] = []
    var progress: [EpisodeID: ListeningProgress] { subject.value }
    var progressPublisher: AnyPublisher<[EpisodeID: ListeningProgress], Never> { subject.eraseToAnyPublisher() }

    func setPosition(_ position: TimeInterval, for id: EpisodeID) {
        saved.append(position)
        subject.value[id, default: ListeningProgress(position: 0, isFinished: false)].position = position
    }

    func markFinished(_ id: EpisodeID) { subject.value[id] = ListeningProgress(position: 0, isFinished: true) }
}

let derby = Podcast(
    id: "derby", title: "Дерби", author: "Редакция", feedURL: URL(string: "https://example.com/derby.rss")!,
    artworkURL: URL(string: "https://example.com/derby.jpg")!, featuredOrder: 1
)

func episode(_ guid: String, duration: TimeInterval? = 1000) -> Episode {
    Episode(
        id: EpisodeID(podcastID: derby.id, guid: guid), podcastID: derby.id, title: "Выпуск \(guid)",
        publishedAt: Date(timeIntervalSince1970: 0), duration: duration,
        audioURL: URL(string: "https://example.com/\(guid).mp3")!, artworkURL: nil, link: nil
    )
}
