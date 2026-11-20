import Combine
import CoreDomain
import Foundation

@MainActor
final class RadioViewModel {
    @Published private(set) var state: RadioState

    /// Текущий запрос; тесты ждут его `value`.
    private(set) var loadTask: Task<Void, Never>?

    private let repository: StationsRepository
    private let player: AudioPlayer
    private let onOpenPlayer: () -> Void

    private var stations: [Station] = []
    private var isLoaded = false
    private var playback: PlaybackState
    private var genre: StationGenre = .sport
    private var hasAppeared = false
    private var playerSubscription: AnyCancellable?

    init(stations: StationsRepository, player: AudioPlayer, onOpenPlayer: @escaping () -> Void) {
        repository = stations
        self.player = player
        self.onOpenPlayer = onOpenPlayer
        playback = player.state
        state = RadioState(chips: RadioFormatter.chips(selected: .sport), nowPlaying: RadioFormatter.nowPlaying(player.state), content: .loading)
        playerSubscription = player.statePublisher.sink { [weak self] playback in
            MainActor.assumeIsolated { self?.playerChanged(playback) }
        }
    }

    /// Каталог грузится при первом показе; дальше — по возврату из фона и «Повторить».
    func viewDidAppear() {
        guard !hasAppeared else { return }
        hasAppeared = true
        load()
    }

    func didEnterForeground() {
        guard hasAppeared else { return }
        load()
    }

    func didTapRetry() {
        state.content = .loading
        load()
    }

    func didSelectGenre(_ genre: StationGenre) {
        self.genre = genre
        state.chips = RadioFormatter.chips(selected: genre)
        render()
    }

    func didChangeQuery(_ query: String) {
        state.query = query
        render()
    }

    /// Строка и её кнопка: текущая станция — пауза/продолжение, другая — запуск.
    func didTapStation(_ id: String) {
        if playback.item?.station?.id == id {
            player.togglePlayPause()
        } else if let station = stations.first(where: { $0.id == id }) {
            player.play(station)
        }
    }

    func didTapNowPlayingButton() {
        player.togglePlayPause()
    }

    func didTapNowPlaying() {
        onOpenPlayer()
    }

    private func load() {
        guard loadTask == nil else { return }
        let repository = repository
        loadTask = Task { [weak self] in
            let result: Result<[Station], Error>
            do {
                result = .success(try await repository.stations())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            loadTask = nil
            switch result {
            case let .success(stations):
                self.stations = stations
                isLoaded = true
                render()
            case .failure:
                // Тихое обновление не затирает уже показанные станции.
                if stations.isEmpty { state.content = .error(message: "Не удалось загрузить станции") }
            }
        }
    }

    private func playerChanged(_ playback: PlaybackState) {
        self.playback = playback
        state.nowPlaying = RadioFormatter.nowPlaying(playback)
        render()
    }

    private func render() {
        guard isLoaded else { return }
        state.content = RadioFormatter.content(stations: stations, genre: genre, query: state.query, playback: playback)
    }
}
