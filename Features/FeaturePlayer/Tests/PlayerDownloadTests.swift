import Combine
import CoreDomain
import Foundation
import Testing
@testable import FeaturePlayer

@MainActor
final class FakeDownloads: EpisodeDownloads {
    let subject = CurrentValueSubject<[DownloadedEpisode], Never>([])
    var wifiOnly = true
    private(set) var downloaded: [EpisodeID] = []
    private(set) var removed: [EpisodeID] = []

    var items: [DownloadedEpisode] { subject.value }
    var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { subject.eraseToAnyPublisher() }

    func set(_ episode: Episode, _ podcast: Podcast, _ state: DownloadState) {
        subject.value = [DownloadedEpisode(episode: episode, podcast: podcast, addedAt: Date(), state: state, artworkFile: nil)]
    }

    func download(_ episode: Episode, podcast: Podcast) {
        downloaded.append(episode.id)
        set(episode, podcast, .waiting)
    }

    func remove(_ id: EpisodeID) {
        removed.append(id)
        subject.value.removeAll { $0.id == id }
    }

    func removeAll() { subject.value = [] }
    func localFile(for id: EpisodeID) -> URL? { nil }
    func usage() -> (bytes: Int64, count: Int) { (0, 0) }
    func availableCapacity() -> Int64? { nil }
}

/// «Скачать» / «45 %» / «Скачан» в плеере выпуска (макет «Плеер»).
@MainActor
struct PlayerDownloadTests {
    let podcast = Podcast(id: "out", title: "Вне игры", author: "Tribuna", feedURL: URL(string: "https://example.com/out.xml")!,
                          artworkURL: URL(string: "https://example.com/out.jpg")!, featuredOrder: 1)
    let episode = Episode(id: EpisodeID(podcastID: "out", guid: "preview"), podcastID: "out", title: "Превью 12 тура",
                          publishedAt: Date(), duration: 2050, audioURL: URL(string: "https://example.com/p.mp3")!, artworkURL: nil, link: nil)

    func playing(_ player: FakeAudioPlayer) {
        player.subject.value = PlaybackState(item: .episode(episode, podcast: podcast), status: .playing, sleepTimerEndsAt: nil,
                                             position: 1122, duration: 2050, rate: 1)
    }

    @Test func downloadButtonStates() {
        let player = FakeAudioPlayer()
        let downloads = FakeDownloads()
        let viewModel = PlayerViewModel(player: player, downloads: downloads)
        playing(player)
        #expect(viewModel.state?.progress?.download == .download)
        #expect(PlayerState.Download.download.title == "Скачать")

        viewModel.didTapDownload()
        #expect(downloads.downloaded == [episode.id])
        #expect(viewModel.state?.progress?.download == .progress("0 %"))

        downloads.set(episode, podcast, .downloading(progress: 0.459))
        #expect(viewModel.state?.progress?.download == .progress("45 %"))
        #expect(PlayerState.Download.progress("45 %").title == "45 %")

        downloads.set(episode, podcast, .downloaded(bytes: 1))
        #expect(viewModel.state?.progress?.download == .downloaded)
        #expect(PlayerState.Download.downloaded.title == "Скачан")
        // «Скачан» не качает заново — удаление только через подтверждение.
        viewModel.didTapDownload()
        #expect(downloads.downloaded == [episode.id])

        downloads.set(episode, podcast, .failed)
        #expect(viewModel.state?.progress?.download == .download)
    }

    /// Удаление скачанного играющего выпуска не трогает воспроизведение — кнопка снова «Скачать».
    @Test func removeWhilePlayingKeepsState() {
        let player = FakeAudioPlayer()
        let downloads = FakeDownloads()
        let viewModel = PlayerViewModel(player: player, downloads: downloads)
        playing(player)
        downloads.set(episode, podcast, .downloaded(bytes: 1))
        let before = player.state

        viewModel.didConfirmRemoveDownload()
        #expect(downloads.removed == [episode.id])
        #expect(viewModel.state?.progress?.download == .download)
        #expect(player.state == before)
        #expect((player.stops, player.toggles, player.seeks) == (0, 0, []))
    }

    /// Скачанный выпуск показывает локальную обложку, остальные — сетевую.
    @Test func downloadedEpisodeUsesLocalArtwork() {
        let player = FakeAudioPlayer()
        let downloads = FakeDownloads()
        let viewModel = PlayerViewModel(player: player, downloads: downloads)
        playing(player)
        let local = URL(fileURLWithPath: "/tmp/a.artwork")
        #expect(viewModel.state?.artworkURL == podcast.artworkURL)

        downloads.subject.value = [DownloadedEpisode(episode: episode, podcast: podcast, addedAt: Date(), state: .downloading(progress: 0.5), artworkFile: local)]
        #expect(viewModel.state?.artworkURL == podcast.artworkURL)

        downloads.subject.value = [DownloadedEpisode(episode: episode, podcast: podcast, addedAt: Date(), state: .downloaded(bytes: 1), artworkFile: local)]
        #expect(viewModel.state?.artworkURL == local)
    }
}
