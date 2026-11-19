import Combine
import CoreDomain
import Foundation

/// Плеер эфира: один на приложение (D15).
/// Пауза закрывает соединение, а продолжение подключается заново — эфир всегда «сейчас», без отставания.
@MainActor
public final class RadioPlayer: AudioPlayer {
    static let connectTimeout: TimeInterval = 15
    static let failureMessage = "Не удалось подключиться"

    private let engine: PlaybackEngine
    private let session: AudioSessionControlling
    private let nowPlaying: NowPlayingControlling
    private let clock: PlaybackClock
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
    private var connectTimeout: AnyCancellable?
    private var sleepTimer: AnyCancellable?
    /// Играли, когда началось прерывание (звонок, Siri) — после него можно продолжить.
    private var resumeAfterInterruption = false

    public var state: PlaybackState { subject.value }
    public var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    public convenience init() {
        self.init(engine: AVPlayerEngine(), session: SystemAudioSession(), nowPlaying: SystemNowPlaying(), clock: SystemClock())
    }

    init(engine: PlaybackEngine, session: AudioSessionControlling, nowPlaying: NowPlayingControlling, clock: PlaybackClock) {
        self.engine = engine
        self.session = session
        self.nowPlaying = nowPlaying
        self.clock = clock
        engine.onEvent = { [weak self] in self?.handle($0) }
        session.onEvent = { [weak self] in self?.handle($0) }
        nowPlaying.onCommand = { [weak self] in self?.handle($0) }
    }

    public func play(_ station: Station) {
        resumeAfterInterruption = false
        // Без активной сессии звук может не пойти в фоне, но играть всё равно пробуем.
        try? session.activate()
        engine.play(station.streamURL)
        update { $0.item = station; $0.status = .loading }
        startConnectTimeout()
    }

    public func togglePlayPause() {
        switch state.status {
        case .playing, .loading: pause()
        case .paused, .failed, .idle: resume()
        }
    }

    public func stop() {
        engine.stop()
        connectTimeout = nil
        sleepTimer = nil
        resumeAfterInterruption = false
        update { $0 = PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil) }
    }

    public func setSleepTimer(minutes: Int?) {
        guard let minutes else {
            sleepTimer = nil
            update { $0.sleepTimerEndsAt = nil }
            return
        }
        let seconds = TimeInterval(minutes * 60)
        sleepTimer = clock.schedule(after: seconds) { [weak self] in
            self?.sleepTimer = nil
            self?.pause()
            self?.update { $0.sleepTimerEndsAt = nil }
        }
        update { $0.sleepTimerEndsAt = clock.now.addingTimeInterval(seconds) }
    }

    // MARK: - Внутреннее

    private var isActive: Bool { state.status == .playing || state.status == .loading }

    private func pause() {
        guard isActive else { return }
        engine.stop()
        connectTimeout = nil
        update { $0.status = .paused }
    }

    private func resume() {
        guard let item = state.item else { return }
        play(item)
    }

    private func fail() {
        engine.stop()
        connectTimeout = nil
        update { $0.status = .failed(Self.failureMessage) }
    }

    private func startConnectTimeout() {
        connectTimeout = clock.schedule(after: Self.connectTimeout) { [weak self] in
            guard self?.state.status == .loading else { return }
            self?.fail()
        }
    }

    private func handle(_ event: PlaybackEngineEvent) {
        // События остановленного потока (после паузы, ошибки, stop) не учитываем.
        guard isActive else { return }
        switch event {
        case .playing:
            connectTimeout = nil
            update { $0.status = .playing }
        case .waiting:
            guard state.status == .playing else { return }
            update { $0.status = .loading }
            startConnectTimeout()
        case .failed:
            fail()
        }
    }

    private func handle(_ event: AudioSessionEvent) {
        switch event {
        case .interruptionBegan:
            resumeAfterInterruption = isActive
            pause()
        case let .interruptionEnded(shouldResume):
            if resumeAfterInterruption && shouldResume { resume() }
            resumeAfterInterruption = false
        case .outputLost:
            pause()
        }
    }

    private func handle(_ command: RemoteCommand) {
        switch command {
        case .play: if !isActive { resume() }
        case .pause: pause()
        case .togglePlayPause: togglePlayPause()
        }
    }

    private func update(_ change: (inout PlaybackState) -> Void) {
        var new = state
        change(&new)
        guard new != state else { return }
        subject.send(new)
        nowPlaying.update(new.item.map { NowPlayingInfo(title: $0.name, artist: $0.subtitle, isPlaying: new.status == .playing) })
    }
}
