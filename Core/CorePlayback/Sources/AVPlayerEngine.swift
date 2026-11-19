import AVFoundation
import Combine

/// Движок на AVPlayer. Ошибкой считаем провал элемента, обрыв и конец потока (у эфира конца нет).
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onEvent: ((PlaybackEngineEvent) -> Void)?
    private let player = AVPlayer()
    private var playerObservation: AnyCancellable?
    private var itemObservations: Set<AnyCancellable> = []

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
    }

    func play(_ url: URL) {
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func stop() {
        itemObservations = []
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func observe(_ item: AVPlayerItem) {
        itemObservations = []
        let center = NotificationCenter.default
        item.publisher(for: \.status)
            .filter { $0 == .failed }
            .map { _ in () }
            .merge(with:
                center.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item).map { _ in () },
                center.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item).map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.onEvent?(.failed) }
            }
            .store(in: &itemObservations)
    }
}
