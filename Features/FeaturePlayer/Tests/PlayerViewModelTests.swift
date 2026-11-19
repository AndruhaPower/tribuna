import Combine
import CoreDomain
import Foundation
import Testing
@testable import FeaturePlayer

@MainActor
final class FakeAudioPlayer: AudioPlayer {
    let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
    private(set) var toggles = 0
    private(set) var sleepTimers: [Int?] = []

    var state: PlaybackState { subject.value }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    func set(_ item: Station?, _ status: PlaybackStatus, sleepTimerEndsAt: Date? = nil) {
        subject.value = PlaybackState(item: item, status: status, sleepTimerEndsAt: sleepTimerEndsAt)
    }

    func play(_ station: Station) {}
    func togglePlayPause() { toggles += 1 }
    func stop() {}
    func setSleepTimer(minutes: Int?) { sleepTimers.append(minutes) }
}

@MainActor
struct PlayerViewModelTests {
    let stadion = Station(
        id: "stadion", name: "Стадион FM", streamURL: URL(string: "https://example.com/s")!, country: "Россия",
        bitrate: 128, genres: [.sport], subtitle: "Футбол · эфир", featuredOrder: nil
    )
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func hiddenWithoutItemAndShownWithIt() throws {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        #expect(viewModel.state == nil)

        player.set(stadion, .playing)
        let state = try #require(viewModel.state)
        #expect(state.name == "Стадион FM")
        #expect(state.header == "Радио · Стадион FM")
        #expect(state.caption == "ФУТБОЛ · ЭФИР")

        player.set(nil, .idle)
        #expect(viewModel.state == nil)
    }

    @Test func statusTexts() throws {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)

        player.set(stadion, .playing)
        var state = try #require(viewModel.state)
        #expect((state.status, state.statusTone, state.button) == ("В эфире", .live, .pause))
        #expect(state.summaryLabel == "Стадион FM, В эфире")
        #expect(state.actionLabel == "Пауза, Стадион FM")
        #expect(state.isAnimating)

        player.set(stadion, .loading)
        state = try #require(viewModel.state)
        #expect((state.status, state.statusTone, state.button) == ("Подключение…", .secondary, .loading))
        #expect(state.actionLabel == "Остановить, Стадион FM")
        #expect(!state.isAnimating)

        player.set(stadion, .paused)
        state = try #require(viewModel.state)
        #expect((state.status, state.statusTone, state.button) == ("На паузе", .secondary, .play))
        #expect(state.actionLabel == "Слушать Стадион FM")

        player.set(stadion, .failed("Не удалось подключиться"))
        state = try #require(viewModel.state)
        #expect((state.status, state.statusTone, state.button) == ("Не удалось подключиться", .error, .play))
        #expect(state.subtitle == "Не удалось подключиться")
        #expect(state.isError)
    }

    @Test func subtitleOmitsUnknownBitrate() throws {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        player.set(stadion, .playing)
        #expect(viewModel.state?.subtitle == "Россия · 128 кбит/с")

        let hls = Station(id: "h", name: "BBC", streamURL: stadion.streamURL, country: "Великобритания",
                          bitrate: nil, genres: [.sport], subtitle: "Спорт", featuredOrder: nil)
        player.set(hls, .playing)
        #expect(viewModel.state?.subtitle == "Великобритания")
    }

    @Test func sleepTimerTextRoundsUpAndRefreshesWithTime() {
        let player = FakeAudioPlayer()
        var now = start
        let viewModel = PlayerViewModel(player: player, now: { now })
        player.set(stadion, .playing, sleepTimerEndsAt: start.addingTimeInterval(25 * 60))
        #expect(viewModel.state?.sleepTimer == "Сон через 25 мин")

        now = start.addingTimeInterval(50)
        viewModel.refresh()
        #expect(viewModel.state?.sleepTimer == "Сон через 25 мин")

        now = start.addingTimeInterval(61)
        viewModel.refresh()
        #expect(viewModel.state?.sleepTimer == "Сон через 24 мин")

        now = start.addingTimeInterval(25 * 60)
        viewModel.refresh()
        #expect(viewModel.state?.sleepTimer == nil)

        player.set(stadion, .playing)
        #expect(viewModel.state?.sleepTimer == nil)
    }

    @Test func actionsGoToPlayer() {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        viewModel.didTapPlayPause()
        viewModel.didSelectSleepTimer(minutes: 30)
        viewModel.didSelectSleepTimer(minutes: nil)
        #expect(player.toggles == 1)
        #expect(player.sleepTimers == [30, nil])
    }
}
