import AVFoundation
import Combine

/// Движок на AVPlayer. Ошибка — провал элемента или обрыв; конец потока — отдельное событие (у эфира его считают обрывом).
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private let player = AVPlayer()
    private var playerObservation: AnyCancellable?
    private var itemObservations: Set<AnyCancellable> = []
    /// Токен наблюдателя времени: живёт столько же, сколько плеер (движок один на приложение).
    private var timeObserver: Any?
    /// Куда перемотать, когда элемент станет `readyToPlay`: до этого AVPlayer может потерять перемотку и начать с 0.
    private var pendingStart: TimeInterval?
    /// Играть ли после отложенной перемотки (пауза до готовности отменяет).
    private var wantsPlay = false

    init() {
        playerObservation = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    switch status {
                    case .playing: self?.onEvent?(.playing)
                    case .waitingToPlayAtSpecifiedRate: self?.onEvent?(.waiting)
                    case .paused: break
                    @unknown default: break
                    }
                }
            }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.sendProgress(time) }
        }
    }

    func play(_ url: URL, from position: TimeInterval) {
        let item = AVPlayerItem(url: url)
        observe(item)
        // Пауза до замены: иначе у уже играющего плеера timeControlStatus может не смениться и .playing не придёт.
        player.pause()
        player.replaceCurrentItem(with: item)
        wantsPlay = true
        pendingStart = position > 0 ? position : nil
        if pendingStart == nil { player.play() }
    }

    func stop() {
        pendingStart = nil
        wantsPlay = false
        itemObservations = []
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func pause() {
        wantsPlay = false
        player.pause()
    }

    /// `play()` берёт скорость из `defaultRate`.
    func resume() {
        wantsPlay = true
        if pendingStart == nil { player.play() }
    }

    func seek(to position: TimeInterval) {
        if pendingStart != nil {
            pendingStart = position
            return
        }
        // Допуск 1 с: точная перемотка длинного VBR MP3 может читать файл с начала и упереться в таймаут подключения.
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func startWhenReady() {
        guard let start = pendingStart else { return }
        pendingStart = nil
        seek(to: start)
        if wantsPlay { player.play() }
    }

    func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.rate != 0 { player.rate = rate }
    }

    private func sendProgress(_ time: CMTime) {
        guard let item = player.currentItem, time.seconds.isFinite else { return }
        // У эфира длительность .indefinite (seconds = NaN).
        let duration = item.duration.seconds
        onEvent?(.progress(position: time.seconds, duration: duration.isFinite && duration > 0 ? duration : nil))
    }

    private func observe(_ item: AVPlayerItem) {
        itemObservations = []
        let center = NotificationCenter.default
        item.publisher(for: \.status)
            .filter { $0 == .failed }
            .map { _ in PlaybackEngineEvent.failed }
            .merge(with:
                center.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item).map { _ in .failed },
                center.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).map { _ in .ended })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                MainActor.assumeIsolated { self?.onEvent?(event) }
            }
            .store(in: &itemObservations)
        item.publisher(for: \.status)
            .first { $0 == .readyToPlay }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.startWhenReady() }
            }
            .store(in: &itemObservations)
    }
}
