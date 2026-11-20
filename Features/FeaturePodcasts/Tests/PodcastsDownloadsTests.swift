import CoreDomain
import Foundation
import Testing
@testable import FeaturePodcasts

/// «Скачать», полоска загрузки и сегмент «Загрузки» (подэтап 2).
@MainActor
extension PodcastsViewModelTests {
    var preview: Episode { feeds["out"]![0] }
    var results: Episode { feeds["out"]![2] }
    var cup: Episode { feeds["puck"]![0] }

    func downloadsContent(_ viewModel: PodcastsViewModel) -> PodcastsState.EpisodesContent? {
        if case let .downloads(content) = viewModel.state.content { return content }
        return nil
    }

    func downloadRows(_ viewModel: PodcastsViewModel) -> [EpisodeRow] {
        if case let .rows(rows) = downloadsContent(viewModel) { return rows }
        return []
    }

    @Test func downloadPillOnlyWithListenPill() async {
        let setup = make()
        await appear(setup.viewModel)
        // «Скачать» рядом со «Слушать» — у первой строки; у остальных пилюль нет.
        #expect(rows(setup.viewModel).map(\.showsDownloadButton) == [true, false, false, false])

        setup.player.set(results, outOfPlay, .paused)
        #expect(rows(setup.viewModel).map(\.showsDownloadButton) == [true, false, false, true])

        setup.downloads.download(preview, podcast: outOfPlay)
        #expect(rows(setup.viewModel)[0].showsDownloadButton == false)
        setup.downloads.set(preview.id, .downloading(progress: 0.3))
        #expect(rows(setup.viewModel)[0].showsDownloadButton == false)
        setup.downloads.set(preview.id, .downloaded(bytes: 1))
        #expect(rows(setup.viewModel)[0].showsDownloadButton == false)
        setup.downloads.set(preview.id, .failed)
        #expect(rows(setup.viewModel)[0].showsDownloadButton == true)
    }

    @Test func progressRowShowsWifiCaption() async {
        let setup = make(downloads: [download(cup, puck, .downloading(progress: 0.6))])
        await appear(setup.viewModel)
        var row = rows(setup.viewModel)[1]
        #expect(row.subtitle == "Вчера · 51 мин · загрузка по Wi-Fi")
        #expect(row.downloadProgress == 0.6)
        #expect(row.caption == "● Новый · Шайба")

        setup.downloads.wifiOnly = false
        setup.downloads.set(cup.id, .downloading(progress: 0.7))
        row = rows(setup.viewModel)[1]
        #expect(row.subtitle == "Вчера · 51 мин · загрузка")
        #expect(row.downloadProgress == 0.7)

        setup.downloads.set(cup.id, .waiting)
        #expect(rows(setup.viewModel)[1].subtitle == "Вчера · 51 мин · ждёт сеть")
        #expect(rows(setup.viewModel)[1].downloadProgress == 0)
        setup.downloads.wifiOnly = true
        setup.downloads.set(cup.id, .waiting)
        #expect(rows(setup.viewModel)[1].subtitle == "Вчера · 51 мин · ждёт Wi-Fi")

        setup.downloads.set(cup.id, .failed)
        #expect(rows(setup.viewModel)[1].subtitle == "Вчера · 51 мин · не удалось скачать")
        #expect(rows(setup.viewModel)[1].downloadProgress == nil)
    }

    @Test func downloadedCaptionAndNoPill() async {
        let setup = make(downloads: [download(preview, outOfPlay, .downloaded(bytes: 48_000_000)), download(results, outOfPlay, .downloaded(bytes: 1))])
        await appear(setup.viewModel)
        let rows = rows(setup.viewModel)
        #expect(rows[0].caption == "● Новый · Вне игры · скачан")
        #expect(rows[0].showsDownloadButton == false)
        #expect(rows[0].button == .listen)
        #expect(rows[0].downloadProgress == nil)
        #expect(rows[0].subtitle == "Сегодня · 34 мин")
        #expect(rows[3].caption == "Вне игры · скачан")
        #expect(rows[3].subtitle == "16 нояб · осталось 12 мин")
    }

    @Test func downloadsSegmentListsNewestFirst() async {
        let artwork = URL(fileURLWithPath: "/tmp/a.artwork")
        let setup = make(downloads: [download(results, outOfPlay, .downloaded(bytes: 48_000_000), artwork: artwork)])
        await appear(setup.viewModel)
        setup.viewModel.didSelectSegment(.downloads)
        // Скачать из списка: новая запись — сверху.
        setup.viewModel.didTapDownloadAction(cup.id)
        setup.downloads.set(cup.id, .downloading(progress: 0.6))

        let rows = downloadRows(setup.viewModel)
        #expect(rows.map(\.title) == ["Кто заберёт Кубок Стэнли", "Итоги 11 тура"])
        #expect(rows.map(\.caption) == ["Шайба", "Вне игры · скачан"])
        #expect(rows.map(\.isNew) == [false, false])
        #expect(rows.map(\.subtitle) == ["Вчера · 51 мин · загрузка по Wi-Fi", "16 нояб · осталось 12 мин · 48 МБ"])
        #expect(rows.map(\.downloadProgress) == [0.6, nil])
        #expect(rows[1].artworkURL == artwork)
        #expect(rows[0].artworkURL == puck.artworkURL)
    }

    /// Меню показало «Отменить загрузку», пока оно было открыто, загрузка кончилась — нажатие не удаляет файл.
    @Test func staleCancelDoesNotRemoveFinishedDownload() async {
        let setup = make(downloads: [download(results, outOfPlay, .downloading(progress: 0.5))])
        await appear(setup.viewModel)
        setup.downloads.set(results.id, .downloaded(bytes: 10))

        setup.viewModel.didTapDownloadAction(results.id, shown: .cancel)
        #expect(setup.downloads.removed.isEmpty)
        #expect(setup.downloads.item(results.id)?.state == .downloaded(bytes: 10))

        setup.viewModel.didTapDownloadAction(results.id, shown: .remove)
        #expect(setup.downloads.removed == [results.id])
    }

    @Test func downloadsSegmentNeedsNoCatalog() async {
        let setup = make(downloads: [download(results, outOfPlay, .downloaded(bytes: 48_000_000))])
        setup.podcasts.result = .failure(FakeError())
        setup.episodes.feeds = [:]
        setup.viewModel.didSelectSegment(.downloads)
        #expect(downloadRows(setup.viewModel).map(\.title) == ["Итоги 11 тура"])
        await appear(setup.viewModel)
        #expect(downloadRows(setup.viewModel).map(\.title) == ["Итоги 11 тура"])
        // Играет из снимка, без каталога.
        setup.viewModel.didTapEpisode(results.id)
        #expect(setup.player.played == [results.id])
    }

    @Test func downloadsSegmentEmptyText() async {
        let setup = make()
        await appear(setup.viewModel)
        setup.viewModel.didSelectSegment(.downloads)
        #expect(downloadsContent(setup.viewModel) == .status(StatusMessage(message: "Скачанных выпусков нет", showsRetry: false)))
    }

    @Test func segmentDefaultNeverDownloads() async {
        let setup = make(subscriptions: [:], downloads: [download(results, outOfPlay, .downloaded(bytes: 1))])
        #expect(setup.viewModel.state.segment == .catalog)
        await appear(setup.viewModel)
        #expect(setup.viewModel.state.segment == .catalog)
    }

    @Test func contextMenuActionsByState() async {
        let setup = make(downloads: [download(cup, puck, .downloading(progress: 0.2))])
        await appear(setup.viewModel)
        func action(_ index: Int) -> EpisodeRow.DownloadAction { rows(setup.viewModel)[index].downloadAction }
        #expect(action(0) == .download)
        #expect(action(1) == .cancel)
        setup.downloads.set(cup.id, .waiting)
        #expect(action(1) == .cancel)
        setup.downloads.set(cup.id, .downloaded(bytes: 1))
        #expect(action(1) == .remove)
        setup.downloads.set(cup.id, .failed)
        #expect(action(1) == .download)

        setup.viewModel.didTapDownloadAction(preview.id)
        #expect(setup.downloads.downloaded == [preview.id])
        #expect(action(0) == .cancel)
        setup.viewModel.didTapDownloadAction(preview.id)
        #expect(setup.downloads.removed == [preview.id])
        // «Удалить» свайпом в «Загрузках».
        setup.viewModel.didSwipeDelete(cup.id)
        #expect(setup.downloads.removed == [preview.id, cup.id])
    }
}

@MainActor
extension PodcastViewModelTests {
    @Test func podcastScreenRowsShowDownloads() async {
        let downloads = FakeDownloads()
        let (viewModel, _, _) = make(subscribed: true, feed: feed, downloads: downloads)
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
        #expect(rows(viewModel).map(\.showsDownloadButton) == [true, false, false])
        viewModel.didTapDownloadAction(feed[0].id)
        #expect(downloads.downloaded == [feed[0].id])
        downloads.set(feed[0].id, .downloading(progress: 0.5))
        #expect(rows(viewModel)[0].subtitle == "Сегодня · 34 мин · загрузка по Wi-Fi")
        #expect(rows(viewModel)[0].downloadProgress == 0.5)
        #expect(rows(viewModel)[0].showsDownloadButton == false)
    }
}
