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
    /// Куда тянут ползунок; пока не nil, позиция плеера не двигает бегунок и время.
    private var scrubPosition: TimeInterval?

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
        let state = PlayerFormatter.state(player.state, now: now(), scrubPosition: scrubPosition)
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

    // MARK: - Выпуск

    /// Палец на ползунке: показываем время под пальцем, перемотка — в `endScrubbing`.
    func scrub(to fraction: Float) {
        guard let duration = player.state.duration, duration > 0 else { return }
        scrubPosition = Double(fraction) * duration
        refresh()
    }

    /// Ползунок отпустили — перематываем и снова следуем за плеером.
    func endScrubbing(at fraction: Float) {
        defer { scrubPosition = nil; refresh() }
        guard let duration = player.state.duration, duration > 0 else { return }
        player.seek(to: Double(fraction) * duration)
    }

    /// Жест отменила система (звонок, жест «домой») — без перемотки, снова следуем за плеером.
    func cancelScrubbing() {
        scrubPosition = nil
        refresh()
    }

    /// −15 / +30.
    func didTapSkip(by seconds: TimeInterval) {
        player.skip(by: seconds)
    }

    /// VoiceOver на ползунке: смахивание вверх/вниз — ±15 с.
    func didAdjustAccessibility(forward: Bool) {
        player.skip(by: forward ? 15 : -15)
    }

    /// Следующая скорость по кругу; нестандартная — ближайшая бо́льшая из списка.
    func didTapSpeed() {
        let rate = player.state.rate
        player.setRate(PlayerFormatter.rates.first { $0 > rate } ?? PlayerFormatter.rates[0])
    }

    /// «Поделиться»: «<выпуск> — <подкаст>» и ссылка выпуска, если она есть в ленте.
    func shareItems() -> [Any] {
        guard case let .episode(episode, podcast) = player.state.item else { return [] }
        return ["\(episode.title) — \(podcast.title)"] + (episode.link.map { [$0] } ?? [])
    }
}
