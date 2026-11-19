import Combine
import CoreDomain
import Foundation

/// Общая модель мини-плеера и плеера: оба только отражают состояние единственного `AudioPlayer` (D15).
@MainActor
final class PlayerViewModel {
    @Published private(set) var state: PlayerState?

    private let player: AudioPlayer
    private let now: () -> Date
    private var subscription: AnyCancellable?

    init(player: AudioPlayer, now: @escaping () -> Date = Date.init) {
        self.player = player
        self.now = now
        state = PlayerFormatter.state(player.state, now: now())
        subscription = player.statePublisher.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Пересчёт по текущему времени: плеер зовёт по таймеру, чтобы «Сон через N мин» не застывал.
    func refresh() {
        let state = PlayerFormatter.state(player.state, now: now())
        if state != self.state { self.state = state }
    }

    func didTapPlayPause() {
        player.togglePlayPause()
    }

    /// Крестик мини-плеера: остановка очищает станцию, мини-плеер скрывается, лист плеера закрывается.
    func didTapClose() {
        player.stop()
    }

    /// nil снимает таймер.
    func didSelectSleepTimer(minutes: Int?) {
        player.setSleepTimer(minutes: minutes)
    }
}
