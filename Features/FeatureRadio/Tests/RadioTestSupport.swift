import Combine
import CoreDomain
import Foundation
@testable import FeatureRadio

func station(
    _ id: String,
    _ name: String,
    genres: Set<StationGenre> = [.sport],
    featured: Int? = nil,
    subtitle: String = "Футбол · репортажи",
    bitrate: Int? = 128
) -> Station {
    Station(
        id: id, name: name, streamURL: URL(string: "https://example.com/\(id)")!, country: "Россия",
        bitrate: bitrate, genres: genres, subtitle: subtitle, featuredOrder: featured
    )
}

struct FakeError: Error {}

/// Отдаёт заданный результат и считает запросы.
final class FakeStationsRepository: StationsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<[Station], FakeError>
    private var _calls = 0

    init(_ stations: [Station] = []) { _result = .success(stations) }

    var result: Result<[Station], FakeError> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    var calls: Int { lock.withLock { _calls } }

    func stations() async throws -> [Station] {
        lock.withLock { _calls += 1 }
        return try result.get()
    }
}

@MainActor
final class FakeAudioPlayer: AudioPlayer {
    let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
    private(set) var played: [String] = []
    private(set) var toggles = 0

    var state: PlaybackState { subject.value }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    func set(_ item: Station?, _ status: PlaybackStatus) {
        subject.value = PlaybackState(item: item.map(PlaybackItem.station), status: status, sleepTimerEndsAt: nil)
    }

    func play(_ item: PlaybackItem) { item.station.map { played.append($0.id) } }
    func togglePlayPause() { toggles += 1 }
    func stop() {}
    func setSleepTimer(minutes: Int?) {}
    func seek(to position: TimeInterval) {}
    func skip(by seconds: TimeInterval) {}
    func setRate(_ rate: Float) {}
}
