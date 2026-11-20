import CoreDomain
import Foundation
import MediaPlayer
import Testing
import UIKit
@testable import CorePlayback

@MainActor
struct EpisodePlaybackTests {
    let engine = FakeEngine()
    let session = FakeSession()
    let nowPlaying = FakeNowPlaying()
    let clock = FakeClock()
    let store = FakeProgressStore()
    let notifications = NotificationCenter()
    let player: RadioPlayer
    let first = episode("1")
    let second = episode("2")

    init() {
        player = RadioPlayer(engine: engine, session: session, nowPlaying: nowPlaying, clock: clock, progress: store, notifications: notifications)
    }

    /// Выпуск запущен и играет с позиции `position`.
    private func playing(_ item: Episode? = nil, at position: TimeInterval = 0) {
        player.play(.episode(item ?? first, podcast: derby))
        engine.send(.playing)
        engine.send(.progress(position: position, duration: 1000))
    }

    @Test func playStartsFromBeginningWithFeedDuration() {
        player.play(.episode(first, podcast: derby))
        #expect(engine.startPositions == [0])
        #expect(player.state == PlaybackState(item: .episode(first, podcast: derby), status: .loading, sleepTimerEndsAt: nil, position: 0, duration: 1000, rate: 1))
    }

    @Test func resumesFromStoredPosition() {
        store.setPosition(420, for: first.id)
        player.play(.episode(first, podcast: derby))
        #expect(engine.startPositions == [420])
        #expect(player.state.position == 420)
    }

    @Test func finishedRestartsFromBeginning() {
        store.markFinished(first.id)
        player.play(.episode(first, podcast: derby))
        store.setPosition(960, for: second.id)
        store.markFinished(second.id)
        store.setPosition(960, for: second.id)
        player.play(.episode(second, podcast: derby))
        #expect(engine.startPositions == [0, 0])
        #expect(store.isFinished(second.id))
    }

    @Test func partialReplayOfFinishedContinues() {
        store.markFinished(first.id)
        store.setPosition(500, for: first.id)
        player.play(.episode(first, podcast: derby))
        #expect(engine.startPositions == [500])
        #expect(store.isFinished(first.id))
    }

    @Test func failureBeforePlayingDoesNotCreateProgress() {
        player.play(.episode(first, podcast: derby))
        clock.advance(by: RadioPlayer.connectTimeout)
        #expect(player.state.status == .failed("Не удалось подключиться"))
        #expect(store.position(for: first.id) == nil)
    }

    @Test func switchingBeforeConnectDoesNotCreateProgress() {
        player.play(.episode(first, podcast: derby))
        player.play(.episode(second, podcast: derby))
        player.stop()
        #expect(store.position(for: first.id) == nil)
        #expect(store.position(for: second.id) == nil)
    }

    @Test func finishedWithUnknownDurationRestartsFromBeginning() {
        let open = episode("x", duration: nil)
        store.markFinished(open.id)
        store.setPosition(500, for: open.id)
        player.play(.episode(open, podcast: derby))
        #expect(engine.startPositions == [0])
    }

    @Test func rateIgnoresNonPositiveAndClamps() {
        playing()
        player.setRate(0)
        player.setRate(-1)
        #expect(player.state.rate == 1)
        player.setRate(3)
        #expect(player.state.rate == 2)
        player.setRate(0.25)
        #expect(player.state.rate == 0.5)
        #expect(engine.rate == 0.5)
    }

    @Test func pauseKeepsStreamAndResumesWithoutReconnect() {
        playing(at: 100)
        player.togglePlayPause()
        #expect(player.state.status == .paused)
        #expect(engine.pauseCount == 1)
        #expect(engine.stopCount == 0)
        #expect(store.position(for: first.id) == 100)

        player.togglePlayPause()
        #expect(player.state.status == .loading)
        #expect(engine.resumeCount == 1)
        #expect(engine.played.count == 1)
        #expect(player.state.position == 100)
        engine.send(.playing)
        #expect(player.state.status == .playing)
    }

    @Test func resumeAfterPauseTimesOut() {
        playing()
        player.togglePlayPause()
        player.togglePlayPause()
        clock.advance(by: RadioPlayer.connectTimeout)
        #expect(player.state.status == .failed("Не удалось подключиться"))
    }

    @Test func progressPublishesPositionAndDuration() {
        playing(at: 5)
        engine.send(.progress(position: 6.5, duration: 1010))
        #expect(player.state.position == 6.5)
        #expect(player.state.duration == 1010)
    }

    @Test func seekAndSkipClampToDuration() {
        playing(at: 100)
        player.seek(to: 250)
        #expect(player.state.position == 250)
        player.skip(by: -15)
        #expect(player.state.position == 235)
        player.skip(by: 30)
        #expect(player.state.position == 265)
        player.seek(to: -10)
        #expect(player.state.position == 0)
        player.skip(by: 2000)
        #expect(player.state.position == 1000)
        #expect(engine.seeks == [250, 235, 265, 0, 1000])
    }

    @Test func seekWithoutDurationOnlyClampsBelow() {
        player.play(.episode(episode("x", duration: nil), podcast: derby))
        player.seek(to: 5000)
        #expect(player.state.position == 5000)
        player.skip(by: -6000)
        #expect(player.state.position == 0)
    }

    @Test func rateAppliesAndKeepsAcrossEpisodesButNotRadio() {
        playing()
        player.setRate(1.5)
        #expect(engine.rate == 1.5)
        #expect(player.state.rate == 1.5)

        player.play(.episode(second, podcast: derby))
        #expect(player.state.rate == 1.5)
        #expect(engine.rate == 1.5)

        player.play(sportFM)
        #expect(player.state.rate == 1)
        #expect(engine.rate == 1)
        player.setRate(2)
        #expect(engine.rate == 1)

        player.play(.episode(first, podcast: derby))
        #expect(engine.rate == 1.5)
    }

    @Test func liveIgnoresSeekAndSkip() {
        player.play(sportFM)
        engine.send(.playing)
        engine.send(.progress(position: 30, duration: nil))
        player.seek(to: 10)
        player.skip(by: 30)
        #expect(engine.seeks.isEmpty)
        #expect(player.state.position == nil)
    }

    @Test func savesEveryTenSecondsWhilePlaying() {
        playing(at: 0)
        clock.skip(by: 9)
        engine.send(.progress(position: 9, duration: 1000))
        #expect(store.saved.isEmpty)
        clock.skip(by: 1)
        engine.send(.progress(position: 10, duration: 1000))
        #expect(store.saved == [10])
        clock.skip(by: 5)
        engine.send(.progress(position: 15, duration: 1000))
        #expect(store.saved == [10])
        clock.skip(by: 5)
        engine.send(.progress(position: 20, duration: 1000))
        #expect(store.saved == [10, 20])
    }

    @Test func savesOnSwitchStopAndBackground() {
        playing(at: 50)
        notifications.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(store.position(for: first.id) == 50)

        engine.send(.progress(position: 60, duration: 1000))
        player.play(.episode(second, podcast: derby))
        #expect(store.position(for: first.id) == 60)

        engine.send(.playing)
        engine.send(.progress(position: 70, duration: 1000))
        player.stop()
        #expect(store.position(for: second.id) == 70)
    }

    @Test func interruptionSavesAndResumesInPlace() {
        playing(at: 300)
        session.send(.interruptionBegan)
        #expect(store.position(for: first.id) == 300)
        session.send(.interruptionEnded(shouldResume: true))
        #expect(engine.resumeCount == 1)
        #expect(engine.played.count == 1)
    }

    @Test func ninetyFivePercentMarksFinishedAndKeepsPlaying() {
        playing(at: 940)
        #expect(!store.isFinished(first.id))
        engine.send(.progress(position: 950, duration: 1000))
        #expect(store.isFinished(first.id))
        #expect(player.state.status == .playing)
    }

    @Test func endMarksFinishedAndPausesWithoutAdvance() {
        playing(at: 999)
        engine.send(.ended)
        #expect(store.isFinished(first.id))
        #expect(player.state.status == .paused)
        #expect(player.state.position == 0)
        #expect(player.state.item == .episode(first, podcast: derby))
        #expect(engine.played.count == 1)
        // Повтор — с начала того же выпуска.
        player.togglePlayPause()
        #expect(engine.resumeCount == 1)
    }

    @Test func liveEndIsFailure() {
        player.play(sportFM)
        engine.send(.playing)
        engine.send(.ended)
        #expect(player.state.status == .failed("Не удалось подключиться"))
    }

    @Test func retryAfterFailureContinuesFromLastPosition() {
        playing(at: 200)
        engine.send(.failed)
        #expect(engine.stopCount == 1)
        player.togglePlayPause()
        #expect(engine.startPositions == [0, 200])
    }

    @Test func nowPlayingShowsEpisodeTime() {
        playing(at: 12)
        player.setRate(1.25)
        #expect(nowPlaying.info == NowPlayingInfo(title: "Выпуск 1", artist: "Дерби", isPlaying: true, isLive: false, elapsed: 12, duration: 1000, rate: 1.25))
        let dictionary = nowPlaying.info!.dictionary
        #expect(dictionary[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)
        #expect(dictionary[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 12)
        #expect(dictionary[MPMediaItemPropertyPlaybackDuration] as? Double == 1000)
        #expect(dictionary[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.25)
    }

    @Test func remoteSkipAndSeek() {
        playing(at: 100)
        nowPlaying.send(.skip(-15))
        #expect(player.state.position == 85)
        nowPlaying.send(.skip(30))
        #expect(player.state.position == 115)
        nowPlaying.send(.seek(to: 600))
        #expect(player.state.position == 600)
        #expect(nowPlaying.info?.elapsed == 600)
    }
}
