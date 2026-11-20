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
        if position > 0 { seek(to: position) }
        player.play()
    }

    func stop() {
        itemObservations = []
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func pause() { player.pause() }

    /// `play()` берёт скорость из `defaultRate`.
    func resume() { player.play() }

    func seek(to position: TimeInterval) {
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
    }
}
