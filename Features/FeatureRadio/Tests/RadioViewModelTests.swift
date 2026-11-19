import CoreDomain
import Foundation
import Testing
@testable import FeatureRadio

@MainActor
struct RadioViewModelTests {
    let golos = station("golos", "Голос матча", genres: [.sport, .football], featured: 1)
    let hockey = station("hockey", "Хоккей Радио", genres: [.sport, .hockey], featured: 2, subtitle: "Хоккей · ток-шоу")
    let news = station("news", "Спорт Новости 24", genres: [.sport, .news], featured: 3, subtitle: "Новости · каждые 30 мин")
    let stadion = station("stadion", "Стадион FM", genres: [.sport, .football])
    let vesti = station("vesti", "Вести FM", genres: [.news], featured: 4, bitrate: nil)

    func makeViewModel(
        _ repository: FakeStationsRepository,
        player: FakeAudioPlayer = FakeAudioPlayer(),
        onOpenPlayer: @escaping () -> Void = {}
    ) -> RadioViewModel {
        RadioViewModel(stations: repository, player: player, onOpenPlayer: onOpenPlayer)
    }

    func appear(_ viewModel: RadioViewModel) async {
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
    }

    func rows(_ viewModel: RadioViewModel) -> [RadioState.Row]? {
        if case let .loaded(_, rows) = viewModel.state.content { return rows }
        return nil
    }

    func title(_ viewModel: RadioViewModel) -> String? {
        if case let .loaded(title, _) = viewModel.state.content { return title }
        return nil
    }

    @Test func sportChipSelectedByDefault() {
        let viewModel = makeViewModel(FakeStationsRepository())
        #expect(viewModel.state.chips.map(\.title) == ["Спорт", "Футбол", "Хоккей", "Новости"])
        #expect(viewModel.state.chips.filter(\.isSelected).map(\.id) == [.sport])
        #expect(viewModel.state.content == .loading)
        #expect(viewModel.state.nowPlaying == nil)
    }

    @Test func featuredOfSelectedGenreInEditorialOrder() async throws {
        let viewModel = makeViewModel(FakeStationsRepository([news, stadion, hockey, golos, vesti]))
        await appear(viewModel)

        #expect(title(viewModel) == "ПОДБОРКА РЕДАКЦИИ")
        let rows = try #require(self.rows(viewModel))
        #expect(rows.map(\.id) == ["golos", "hockey", "news"])
        #expect(rows.map(\.initials) == ["ГМ", "ХР", "СН"])
        #expect(rows[0].name == "Голос матча")
        #expect(rows[0].subtitle == "Футбол · репортажи")
        #expect(rows.allSatisfy { $0.button == .play })
    }

    @Test func chipFiltersByGenreWithSingleSelection() async {
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey, news, vesti]))
        await appear(viewModel)

        viewModel.didSelectGenre(.news)
        #expect(rows(viewModel)?.map(\.id) == ["news", "vesti"])
        #expect(viewModel.state.chips.filter(\.isSelected).map(\.id) == [.news])

        viewModel.didSelectGenre(.hockey)
        #expect(rows(viewModel)?.map(\.id) == ["hockey"])
        #expect(viewModel.state.chips.filter(\.isSelected).map(\.id) == [.hockey])
    }

    @Test func searchByNameIgnoresCaseChipAndFeatured() async {
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey, news, stadion, vesti]))
        await appear(viewModel)
        viewModel.didSelectGenre(.hockey)

        viewModel.didChangeQuery("  стадион ")
        #expect(rows(viewModel)?.map(\.id) == ["stadion"])
        #expect(title(viewModel) == "РЕЗУЛЬТАТЫ ПОИСКА")
        #expect(viewModel.state.query == "  стадион ")

        viewModel.didChangeQuery("FM")
        #expect(rows(viewModel)?.map(\.id) == ["stadion", "vesti"])
    }

    @Test func searchByGenreLabel() async {
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey, news, stadion, vesti]))
        await appear(viewModel)

        viewModel.didChangeQuery("ФУТБ")
        #expect(rows(viewModel)?.map(\.id) == ["golos", "stadion"])
        viewModel.didChangeQuery("новости")
        #expect(rows(viewModel)?.map(\.id) == ["news", "vesti"])
        viewModel.didChangeQuery("спорт")
        #expect(rows(viewModel)?.map(\.id) == ["golos", "hockey", "news", "stadion"])
    }

    @Test func clearingQueryReturnsToChip() async {
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey, news, vesti]))
        await appear(viewModel)
        viewModel.didSelectGenre(.news)
        viewModel.didChangeQuery("хоккей")
        #expect(rows(viewModel)?.map(\.id) == ["hockey"])

        viewModel.didChangeQuery("   ")
        #expect(rows(viewModel)?.map(\.id) == ["news", "vesti"])
        #expect(title(viewModel) == "ПОДБОРКА РЕДАКЦИИ")
    }

    @Test func nothingFound() async {
        let viewModel = makeViewModel(FakeStationsRepository([golos]))
        await appear(viewModel)

        viewModel.didChangeQuery("джаз")
        #expect(viewModel.state.content == .empty(message: "Ничего не нашлось"))
        viewModel.didChangeQuery("")
        viewModel.didSelectGenre(.news)
        #expect(viewModel.state.content == .empty(message: "Ничего не нашлось"))
    }

    @Test func loadErrorThenRetry() async {
        let repository = FakeStationsRepository([golos])
        repository.result = .failure(FakeError())
        let player = FakeAudioPlayer()
        let viewModel = makeViewModel(repository, player: player)
        await appear(viewModel)
        #expect(viewModel.state.content == .error(message: "Не удалось загрузить станции"))
        // Смена плеера, чипа или запроса не подменяет ошибку пустым списком.
        player.set(golos, .playing)
        viewModel.didSelectGenre(.news)
        viewModel.didChangeQuery("г")
        #expect(viewModel.state.content == .error(message: "Не удалось загрузить станции"))

        repository.result = .success([golos])
        viewModel.didTapRetry()
        #expect(viewModel.state.content == .loading)
        await viewModel.loadTask?.value
        #expect(rows(viewModel)?.map(\.id) == ["golos"])
        #expect(repository.calls == 2)
    }

    @Test func appearLoadsOnce() async {
        let repository = FakeStationsRepository([golos])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)
        await appear(viewModel)
        #expect(repository.calls == 1)
    }

    @Test func foregroundReloadsKeepingStationsOnError() async {
        let repository = FakeStationsRepository([golos])
        let viewModel = makeViewModel(repository)
        viewModel.didEnterForeground()
        #expect(repository.calls == 0)

        await appear(viewModel)
        repository.result = .success([golos, hockey])
        viewModel.didEnterForeground()
        await viewModel.loadTask?.value
        #expect(rows(viewModel)?.map(\.id) == ["golos", "hockey"])

        repository.result = .failure(FakeError())
        viewModel.didEnterForeground()
        await viewModel.loadTask?.value
        #expect(rows(viewModel)?.map(\.id) == ["golos", "hockey"])
        #expect(repository.calls == 3)
    }

    @Test func nowPlayingFollowsPlayer() {
        let player = FakeAudioPlayer()
        let viewModel = makeViewModel(FakeStationsRepository(), player: player)

        player.set(stadion, .playing)
        let card = viewModel.state.nowPlaying
        #expect(card?.id == "stadion")
        #expect(card?.name == "Стадион FM")
        #expect(card?.subtitle == "Россия · 128 кбит/с")
        #expect(card?.button == .pause)
        #expect(card?.isAnimating == true)
        #expect(card?.isError == false)

        player.set(vesti, .loading)
        #expect(viewModel.state.nowPlaying?.subtitle == "Россия")
        #expect(viewModel.state.nowPlaying?.button == .loading)
        #expect(viewModel.state.nowPlaying?.isAnimating == false)

        player.set(vesti, .paused)
        #expect(viewModel.state.nowPlaying?.button == .play)

        player.set(vesti, .failed("Не удалось подключиться"))
        #expect(viewModel.state.nowPlaying?.subtitle == "Не удалось подключиться")
        #expect(viewModel.state.nowPlaying?.isError == true)
        #expect(viewModel.state.nowPlaying?.button == .play)

        player.set(nil, .idle)
        #expect(viewModel.state.nowPlaying == nil)
    }

    @Test func currentRowShowsPause() async {
        let player = FakeAudioPlayer()
        player.set(golos, .playing)
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey]), player: player)
        await appear(viewModel)
        #expect(rows(viewModel)?.map(\.button) == [.pause, .play])

        player.set(golos, .paused)
        #expect(rows(viewModel)?.map(\.button) == [.play, .play])
        player.set(hockey, .loading)
        #expect(rows(viewModel)?.map(\.button) == [.play, .pause])
    }

    @Test func rowAccessibilityFollowsPlayer() async throws {
        let player = FakeAudioPlayer()
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey]), player: player)
        await appear(viewModel)
        let idle = try #require(rows(viewModel))
        #expect(idle[0].accessibilityLabel == "Голос матча, Футбол · репортажи")
        #expect(idle.map(\.accessibilityValue) == [nil, nil])
        #expect(idle.map(\.actionLabel) == ["Слушать Голос матча", "Слушать Хоккей Радио"])

        player.set(golos, .loading)
        #expect(rows(viewModel)?.map(\.accessibilityValue) == ["подключение", nil])
        #expect(rows(viewModel)?.map(\.actionLabel) == ["Остановить", "Слушать Хоккей Радио"])

        player.set(golos, .playing)
        #expect(rows(viewModel)?.map(\.accessibilityValue) == ["играет", nil])
        #expect(rows(viewModel)?.map(\.actionLabel) == ["Пауза", "Слушать Хоккей Радио"])

        player.set(golos, .failed("Не удалось подключиться"))
        #expect(rows(viewModel)?.map(\.accessibilityValue) == [nil, nil])
        #expect(rows(viewModel)?.first?.actionLabel == "Слушать Голос матча")
    }

    @Test func nowPlayingButtonAccessibility() {
        let player = FakeAudioPlayer()
        let viewModel = makeViewModel(FakeStationsRepository(), player: player)
        player.set(stadion, .playing)
        #expect(viewModel.state.nowPlaying?.actionLabel == "Пауза, Стадион FM")
        player.set(stadion, .loading)
        #expect(viewModel.state.nowPlaying?.actionLabel == "Остановить, Стадион FM")
        player.set(stadion, .paused)
        #expect(viewModel.state.nowPlaying?.actionLabel == "Слушать Стадион FM")
    }

    @Test func tapStationPlaysOrToggles() async {
        let player = FakeAudioPlayer()
        let viewModel = makeViewModel(FakeStationsRepository([golos, hockey]), player: player)
        await appear(viewModel)

        viewModel.didTapStation("golos")
        #expect(player.played == ["golos"])
        player.set(golos, .playing)
        viewModel.didTapStation("golos")
        #expect(player.toggles == 1)
        viewModel.didTapStation("hockey")
        #expect(player.played == ["golos", "hockey"])
        viewModel.didTapStation("missing")
        #expect(player.played == ["golos", "hockey"])
    }

    @Test func nowPlayingCardActions() {
        let player = FakeAudioPlayer()
        var opened = 0
        let viewModel = makeViewModel(FakeStationsRepository(), player: player, onOpenPlayer: { opened += 1 })
        player.set(stadion, .playing)

        viewModel.didTapNowPlayingButton()
        #expect(player.toggles == 1)
        viewModel.didTapNowPlaying()
        #expect(opened == 1)
    }

    @Test(arguments: [
        ("Голос матча", "ГМ"), ("Спорт Новости 24", "СН"), ("Стадион FM", "СF"),
        ("Чемпионат", "ЧЕ"), ("24 Спорт", "СП"), ("", ""),
    ])
    func initials(_ name: String, _ expected: String) {
        #expect(RadioFormatter.initials(name) == expected)
    }
}
