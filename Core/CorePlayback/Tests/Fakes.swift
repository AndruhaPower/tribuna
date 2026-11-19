import Combine
import CoreDomain
import Foundation
@testable import CorePlayback

@MainActor
final class FakeEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private(set) var played: [URL] = []
    private(set) var stopCount = 0
    func play(_ url: URL) { played.append(url) }
    func stop() { stopCount += 1 }
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
