import Combine
import CoreDomain
import Foundation

/// Общая модель мини-плеера и плеера: оба только отражают состояние единственного `AudioPlayer` (D15).
@MainActor
final class PlayerViewModel {
    @Published private(set) var state: PlayerState?

    private let player: AudioPlayer
    /// nil у мини-плеера: кнопки загрузки там нет.
    private let downloads: EpisodeDownloads?
    private let requireSignIn: (SignInReason, @escaping @MainActor () -> Void) -> Void
    private let now: () -> Date
    private var subscriptions: Set<AnyCancellable> = []
    /// Куда тянут ползунок; пока не nil, позиция плеера не двигает бегунок и время.
    private var scrubPosition: TimeInterval?

    /// `requireSignIn` — ворота «Скачать» (D31); у мини-плеера загрузок нет, ворота не нужны.
    init(
        player: AudioPlayer,
        downloads: EpisodeDownloads? = nil,
        requireSignIn: @escaping (SignInReason, @escaping @MainActor () -> Void) -> Void = { $1() },
        now: @escaping () -> Date = Date.init
    ) {
        self.player = player
        self.downloads = downloads
        self.requireSignIn = requireSignIn
        self.now = now
        refresh()
        player.statePublisher.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
        downloads?.itemsPublisher.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }.store(in: &subscriptions)
    }

    private var currentEpisode: (episode: Episode, podcast: Podcast)? {
        guard case let .episode(episode, podcast) = player.state.item else { return nil }
        return (episode, podcast)
    }

    /// Пересчёт по текущему времени: плеер зовёт по таймеру, чтобы «Сон через N мин» не застывал.
    func refresh() {
        let item = currentEpisode.flatMap { downloads?.item($0.episode.id) }
        var artwork: URL?
        if case .downloaded = item?.state { artwork = item?.artworkFile }
        let state = PlayerFormatter.state(player.state, now: now(), scrubPosition: scrubPosition, download: item?.state, localArtwork: artwork)
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

    /// «Скачать»: качаем, только если записи нет или загрузка не удалась; «Скачан» удаляется через подтверждение.
    /// Без входа — лист входа (D31), загрузка — после входа, если выпуск всё ещё не скачивается.
    func didTapDownload() {
        guard let (episode, podcast) = currentEpisode, state?.progress?.download == .download else { return }
        requireSignIn(.download) { [weak self] in
            switch self?.downloads?.item(episode.id)?.state {
            case nil, .failed: self?.downloads?.download(episode, podcast: podcast)
            default: break
            }
        }
    }

    /// «Удалить загрузку?» → «Удалить». Воспроизведение не трогаем, даже если играет этот файл.
    func didConfirmRemoveDownload() {
        guard let (episode, _) = currentEpisode else { return }
        downloads?.remove(episode.id)
    }

    /// «Поделиться»: «<выпуск> — <подкаст>» и ссылка выпуска, если она есть в ленте.
    func shareItems() -> [Any] {
        guard case let .episode(episode, podcast) = player.state.item else { return [] }
        return ["\(episode.title) — \(podcast.title)"] + (episode.link.map { [$0] } ?? [])
    }
}
