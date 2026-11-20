import Combine
import CoreDomain
import Foundation
import MediaPlayer
import Testing
@testable import CorePlayback

@MainActor
struct RadioPlayerTests {
    let engine = FakeEngine()
    let session = FakeSession()
    let nowPlaying = FakeNowPlaying()
    let clock = FakeClock()
    let player: RadioPlayer

    init() {
        player = RadioPlayer(engine: engine, session: session, nowPlaying: nowPlaying, clock: clock, progress: FakeProgressStore(), notifications: NotificationCenter())
    }

    /// Станция запущена и играет.
    private func playing(_ station: Station = matchTV) {
        player.play(station)
        engine.send(.playing)
    }

    @Test func startsIdle() {
        #expect(player.state == PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
    }

    @Test func playLoadsThenPlays() {
        player.play(matchTV)
        #expect(player.state.item == .station(matchTV))
        #expect(player.state.status == .loading)
        #expect(engine.played == [matchTV.streamURL])
        #expect(session.activateCount == 1)

        engine.send(.playing)
        #expect(player.state.status == .playing)
    }

    @Test func publisherSendsChanges() {
        var received: [PlaybackStatus] = []
        let cancellable = player.statePublisher.sink { received.append($0.status) }
        playing()
        cancellable.cancel()
        #expect(received == [.idle, .loading, .playing])
    }

    @Test func engineFailureFails() {
        player.play(matchTV)
        engine.send(.failed)
        #expect(player.state.status == .failed("Не удалось подключиться"))
        #expect(player.state.item == .station(matchTV))
        #expect(engine.stopCount == 1)
    }

    @Test func noResponseTimesOut() {
        player.play(matchTV)
        clock.advance(by: RadioPlayer.connectTimeout - 1)
        #expect(player.state.status == .loading)
        clock.advance(by: 1)
        #expect(player.state.status == .failed("Не удалось подключиться"))
    }

    @Test func stallRecoversOrTimesOut() {
        playing()
        engine.send(.waiting)
        #expect(player.state.status == .loading)
        engine.send(.playing)
        #expect(player.state.status == .playing)
        clock.advance(by: 60)
        #expect(player.state.status == .playing)

        engine.send(.waiting)
        clock.advance(by: RadioPlayer.connectTimeout)
        #expect(player.state.status == .failed("Не удалось подключиться"))
    }

    @Test func staleConnectTimeoutIgnored() {
        clock.ignoresCancellation = true
        player.play(matchTV)
        clock.advance(by: RadioPlayer.connectTimeout * 2 / 3)
        player.play(sportFM)
        clock.advance(by: RadioPlayer.connectTimeout / 3)
        #expect(player.state.status == .loading)
        clock.advance(by: RadioPlayer.connectTimeout * 2 / 3)
        #expect(player.state.status == .failed("Не удалось подключиться"))
    }

    @Test func toggleRetriesAfterFailure() {
        player.play(matchTV)
        engine.send(.failed)
        player.togglePlayPause()
        #expect(player.state.status == .loading)
        #expect(engine.played == [matchTV.streamURL, matchTV.streamURL])
    }

    @Test func togglePausesAndResumesLive() {
        playing()
        player.togglePlayPause()
        #expect(player.state.status == .paused)
        #expect(engine.stopCount == 1)
        // Поздние события остановленного потока не меняют паузу.
        engine.send(.playing)
        #expect(player.state.status == .paused)

        player.togglePlayPause()
        #expect(player.state.status == .loading)
        #expect(engine.played.count == 2)
    }

    @Test func switchingStationLoadsNew() {
        playing()
        player.play(sportFM)
        #expect(player.state.item == .station(sportFM))
        #expect(player.state.status == .loading)
        #expect(engine.played.last == sportFM.streamURL)
    }

    @Test func interruptionPausesAndResumes() {
        playing()
        session.send(.interruptionBegan)
        #expect(player.state.status == .paused)
        session.send(.interruptionEnded(shouldResume: true))
        #expect(player.state.status == .loading)
        #expect(engine.played.count == 2)
    }

    @Test func interruptionWithoutShouldResumeStaysPaused() {
        playing()
        session.send(.interruptionBegan)
        session.send(.interruptionEnded(shouldResume: false))
        #expect(player.state.status == .paused)
        #expect(engine.played.count == 1)
    }

    @Test func interruptionDoesNotResumeUserPause() {
        playing()
        player.togglePlayPause()
        session.send(.interruptionBegan)
        session.send(.interruptionEnded(shouldResume: true))
        #expect(player.state.status == .paused)
        #expect(engine.played.count == 1)
    }

    @Test func headphonesUnpluggedPauses() {
        playing()
        session.send(.outputLost)
        #expect(player.state.status == .paused)
        #expect(player.state.item == .station(matchTV))
    }

    @Test func sleepTimerPausesAndClears() {
        playing()
        player.setSleepTimer(minutes: 30)
        #expect(player.state.sleepTimerEndsAt == clock.now.addingTimeInterval(1800))
        clock.advance(by: 1799)
        #expect(player.state.status == .playing)
        clock.advance(by: 1)
        #expect(player.state == PlaybackState(item: .station(matchTV), status: .paused, sleepTimerEndsAt: nil))
        #expect(engine.stopCount == 1)
    }

    @Test func sleepTimerCancels() {
        playing()
        player.setSleepTimer(minutes: 30)
        player.setSleepTimer(minutes: nil)
        #expect(player.state.sleepTimerEndsAt == nil)
        clock.advance(by: 3600)
        #expect(player.state.status == .playing)
    }

    @Test func sleepTimerReplacesPrevious() {
        playing()
        player.setSleepTimer(minutes: 10)
        player.setSleepTimer(minutes: 30)
        clock.advance(by: 600)
        #expect(player.state.status == .playing)
        #expect(player.state.sleepTimerEndsAt == clock.now.addingTimeInterval(1200))
    }

    @Test func expiredSleepTimerClearedOnResume() {
        playing()
        player.setSleepTimer(minutes: 10)
        player.togglePlayPause()
        clock.skip(by: 700)
        player.togglePlayPause()
        #expect(player.state.sleepTimerEndsAt == nil)
        engine.send(.playing)
        clock.advance(by: 1)
        #expect(player.state.status == .playing)
    }

    @Test func sleepTimerSurvivesStationChange() {
        playing()
        player.setSleepTimer(minutes: 15)
        let endsAt = player.state.sleepTimerEndsAt
        player.play(sportFM)
        engine.send(.playing)
        #expect(player.state.sleepTimerEndsAt == endsAt)
        clock.advance(by: 900)
        #expect(player.state.status == .paused)
        #expect(player.state.item == .station(sportFM))
    }

    @Test func stopClosesPlayer() {
        playing()
        player.setSleepTimer(minutes: 15)
        player.stop()
        #expect(player.state == PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
        #expect(nowPlaying.info == nil)
        #expect(session.deactivateCount == 1)
        clock.advance(by: 900)
        #expect(player.state.status == .idle)
    }

    @Test func nowPlayingFollowsState() {
        player.play(matchTV)
        #expect(nowPlaying.info == NowPlayingInfo(title: "Матч ТВ", artist: "Спорт", isPlaying: false))
        engine.send(.playing)
        #expect(nowPlaying.info?.isPlaying == true)
        player.togglePlayPause()
        #expect(nowPlaying.info?.isPlaying == false)
    }

    @Test func nowPlayingDictionaryIsLive() {
        let dictionary = NowPlayingInfo(title: "Матч ТВ", artist: "Спорт", isPlaying: true).dictionary
        #expect(dictionary[MPMediaItemPropertyTitle] as? String == "Матч ТВ")
        #expect(dictionary[MPMediaItemPropertyArtist] as? String == "Спорт")
        #expect(dictionary[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(dictionary[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
    }

    @Test func remoteCommands() {
        playing()
        nowPlaying.send(.pause)
        #expect(player.state.status == .paused)
        nowPlaying.send(.play)
        #expect(player.state.status == .loading)
        engine.send(.playing)
        nowPlaying.send(.togglePlayPause)
        #expect(player.state.status == .paused)
        nowPlaying.send(.togglePlayPause)
        #expect(player.state.status == .loading)
    }

    @Test func remotePlayWhilePlayingDoesNothing() {
        playing()
        nowPlaying.send(.play)
        #expect(player.state.status == .playing)
        #expect(engine.played.count == 1)
    }
}
