import Combine
import CoreDomain
import Foundation
import UIKit

/// Плеер эфира и выпусков подкастов: один на приложение (D15, D23, D28).
/// У эфира пауза закрывает соединение, а продолжение подключается заново — эфир всегда «сейчас», без отставания.
/// У выпуска пауза настоящая; позиция сохраняется в `ListeningProgressStore`.
@MainActor
public final class RadioPlayer: AudioPlayer {
    static let connectTimeout: TimeInterval = 30
    static let failureMessage = "Не удалось подключиться"
    /// Как часто сохраняем позицию играющего выпуска.
    static let saveInterval: TimeInterval = 10
    /// С этой доли выпуск считается прослушанным.
    static let finishedFraction = 0.95

    private let engine: PlaybackEngine
    private let session: AudioSessionControlling
    private let nowPlaying: NowPlayingControlling
    private let clock: PlaybackClock
    private let progress: ListeningProgressStore?
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState(item: nil, status: .idle, sleepTimerEndsAt: nil))
    private var connectTimeout: AnyCancellable?
    /// Номер попытки подключения: таймаут прошлой попытки ничего не делает, даже если снятие опоздало.
    private var connectAttempt = 0
    private var sleepTimer: AnyCancellable?
    /// Играли, когда началось прерывание (звонок, Siri) — после него можно продолжить.
    private var resumeAfterInterruption = false
    /// Скорость выпусков: переходит на следующие выпуски до перезапуска приложения, у эфира всегда 1.
    private var episodeRate: Float = 1
    private var lastSavedAt: Date
    private var backgroundObservation: AnyCancellable?

    public var state: PlaybackState { subject.value }
    public var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    /// nil — позиция выпусков не сохраняется (отладочные сборки только с эфиром).
    public convenience init(progress: ListeningProgressStore? = nil) {
        self.init(engine: AVPlayerEngine(), session: SystemAudioSession(), nowPlaying: SystemNowPlaying(), clock: SystemClock(), progress: progress, notifications: .default)
    }

    init(engine: PlaybackEngine, session: AudioSessionControlling, nowPlaying: NowPlayingControlling, clock: PlaybackClock,
         progress: ListeningProgressStore?, notifications: NotificationCenter) {
        self.engine = engine
        self.session = session
        self.nowPlaying = nowPlaying
        self.clock = clock
        self.progress = progress
        lastSavedAt = clock.now
        engine.onEvent = { [weak self] in self?.handle($0) }
        session.onEvent = { [weak self] in self?.handle($0) }
        nowPlaying.onCommand = { [weak self] in self?.handle($0) }
        // Из фона приложение могут выгрузить — позицию сохраняем сразу.
        backgroundObservation = notifications.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.savePosition() }
            }
    }

    public func play(_ item: PlaybackItem) {
        savePosition()
        resumeAfterInterruption = false
        // Без активной сессии звук может не пойти в фоне, но играть всё равно пробуем.
        try? session.activate()
        let start: TimeInterval?
        let url: URL
        switch item {
        case let .station(station):
            (start, url) = (nil, station.streamURL)
        case let .episode(episode, _):
            // Прослушанный — с начала, если позиция в хвосте (≥95 %); недослушанный повтор продолжается. «Прослушано» не снимаем (D27).
            let stored = progress?.position(for: episode.id) ?? 0
            // Длительность неизвестна — прослушанный начинаем с нуля.
            let atEnd = episode.duration.map { stored >= $0 * Self.finishedFraction } ?? true
            start = progress?.isFinished(episode.id) == true && atEnd ? 0 : stored
            url = episode.audioURL
        }
        let rate = item.isLive ? 1 : episodeRate
        engine.setRate(rate)
        engine.play(url, from: start ?? 0)
        lastSavedAt = clock.now
        update {
            $0.item = item
            $0.status = .loading
            $0.position = start
            $0.duration = item.episode?.duration
            $0.rate = rate
        }
        startConnectTimeout()
    }

    public func togglePlayPause() {
        switch state.status {
        case .playing, .loading: pause()
        case .paused, .failed, .idle: resume()
        }
    }

    public func stop() {
        savePosition()
        engine.stop()
        connectTimeout = nil
        sleepTimer = nil
        resumeAfterInterruption = false
        session.deactivate()
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

    public func seek(to position: TimeInterval) {
        guard state.item?.isLive == false else { return }
        let position = min(max(position, 0), state.duration ?? .infinity)
        engine.seek(to: position)
        update { $0.position = position }
        markFinishedIfNeeded()
    }

    public func skip(by seconds: TimeInterval) {
        seek(to: (state.position ?? 0) + seconds)
    }

    public func setRate(_ rate: Float) {
        guard state.item?.isLive == false, rate > 0 else { return }
        let rate = min(max(rate, 0.5), 2)
        episodeRate = rate
        engine.setRate(rate)
        update { $0.rate = rate }
    }

    // MARK: - Внутреннее

    private var isActive: Bool { state.status == .playing || state.status == .loading }

    private func pause() {
        guard isActive else { return }
        if state.item?.isLive == false { engine.pause() } else { engine.stop() }
        connectTimeout = nil
        update { $0.status = .paused }
        savePosition()
    }

    private func resume() {
        guard let item = state.item else { return }
        // Таймер сна мог истечь, пока приложение спало, — не даём ему сработать после продолжения.
        if let endsAt = state.sleepTimerEndsAt, endsAt <= clock.now {
            sleepTimer = nil
            update { $0.sleepTimerEndsAt = nil }
        }
        guard !item.isLive, state.status == .paused else { return play(item) }
        // Выпуск на паузе: поток не отпускали, продолжаем с того же места.
        try? session.activate()
        engine.resume()
        update { $0.status = .loading }
        startConnectTimeout()
    }

    private func fail() {
        engine.stop()
        connectTimeout = nil
        update { $0.status = .failed(Self.failureMessage) }
        savePosition()
    }

    /// Выпуск доиграл: прослушан, пауза на начале; следующий сам не запускается.
    private func finish() {
        engine.pause()
        engine.seek(to: 0)
        connectTimeout = nil
        update { $0.status = .paused; $0.position = 0 }
        if let episode = state.item?.episode { progress?.markFinished(episode.id) }
    }

    private func savePosition() {
        guard let episode = state.item?.episode, let position = state.position else { return }
        // Не начатый выпуск (позиция 0, записи нет) не помечаем начатым: сбой или смена до подключения.
        guard position > 0 || progress?.position(for: episode.id) != nil else { return }
        lastSavedAt = clock.now
        progress?.setPosition(position, for: episode.id)
    }

    private func markFinishedIfNeeded() {
        guard let episode = state.item?.episode, let position = state.position, let duration = state.duration, duration > 0,
              position >= duration * Self.finishedFraction, progress?.isFinished(episode.id) == false else { return }
        progress?.markFinished(episode.id)
    }

    private func handleProgress(position: TimeInterval, duration: TimeInterval?) {
        // Только пока играет: при подключении движок может отдать 0 до перемотки на сохранённое место.
        guard state.item?.isLive == false, state.status == .playing else { return }
        let durationChanged = duration != nil && duration != state.duration
        // Экран блокировки сам ведёт время по скорости — обновляем его, только если сменилась длительность.
        update(refreshNowPlaying: durationChanged) {
            $0.position = position
            if let duration { $0.duration = duration }
        }
        markFinishedIfNeeded()
        if clock.now.timeIntervalSince(lastSavedAt) >= Self.saveInterval { savePosition() }
    }

    private func startConnectTimeout() {
        connectAttempt += 1
        let attempt = connectAttempt
        connectTimeout = clock.schedule(after: Self.connectTimeout) { [weak self] in
            guard self?.connectAttempt == attempt, self?.state.status == .loading else { return }
            self?.fail()
        }
    }

    private func handle(_ event: PlaybackEngineEvent) {
        if case let .progress(position, duration) = event { return handleProgress(position: position, duration: duration) }
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
        case .ended:
            if state.item?.isLive == false { finish() } else { fail() }
        case .progress:
            break
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
        case let .skip(seconds): skip(by: seconds)
        case let .seek(position): seek(to: position)
        }
    }

    private func update(refreshNowPlaying: Bool = true, _ change: (inout PlaybackState) -> Void) {
        var new = state
        change(&new)
        guard new != state else { return }
        subject.send(new)
        guard refreshNowPlaying else { return }
        nowPlaying.update(new.item.map {
            NowPlayingInfo(title: $0.title, artist: $0.subtitle, isPlaying: new.status == .playing, isLive: $0.isLive,
                           elapsed: new.position, duration: new.duration, rate: new.rate)
        })
    }
}
