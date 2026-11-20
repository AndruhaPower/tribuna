import CoreDomain
import Foundation
import Testing
@testable import FeaturePlayer

/// Плеер и мини-плеер выпуска (макет «Плеер»: «Превью 12 тура…», «Вне игры», 18:42 из 34:10, 1,25×).
@MainActor
struct EpisodePlayerTests {
    let podcast = Podcast(id: "out", title: "Вне игры", author: "Tribuna", feedURL: URL(string: "https://example.com/out.xml")!,
                          artworkURL: URL(string: "https://example.com/out.jpg")!, featuredOrder: 1)
    let link = URL(string: "https://example.com/out/preview")!
    /// 18 нояб 2026, 12:00 по Москве.
    let published = Date(timeIntervalSince1970: 1_795_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    func episode(duration: TimeInterval? = 2050, artwork: URL? = nil, link: URL? = nil) -> Episode {
        Episode(id: EpisodeID(podcastID: "out", guid: "preview"), podcastID: "out", title: "Превью 12 тура: дерби на Энфилде",
                publishedAt: published, duration: duration, audioURL: URL(string: "https://example.com/p.mp3")!, artworkURL: artwork, link: link)
    }

    func playback(_ status: PlaybackStatus = .playing, position: TimeInterval? = 1122, duration: TimeInterval? = 2050, rate: Float = 1.25,
                  episode: Episode? = nil) -> PlaybackState {
        PlaybackState(item: .episode(episode ?? self.episode(duration: duration), podcast: podcast), status: status,
                      sleepTimerEndsAt: nil, position: position, duration: duration, rate: rate)
    }

    func state(_ playback: PlaybackState, scrub: TimeInterval? = nil) throws -> PlayerState {
        try #require(PlayerFormatter.state(playback, now: published.addingTimeInterval(2 * 86400), scrubPosition: scrub, calendar: calendar))
    }

    @Test func mockupState() throws {
        let state = try state(playback())
        #expect(state.name == "Превью 12 тура: дерби на Энфилде")
        #expect(state.header == "Подкаст · Вне игры")
        #expect(state.caption == "ВНЕ ИГРЫ")
        #expect(state.subtitle == "Вне игры · 18 нояб")
        #expect((state.status, state.statusTone, state.button) == ("Вне игры · 18:42 из 34:10", .secondary, .pause))
        #expect(state.artworkURL == podcast.artworkURL)
        let progress = try #require(state.progress)
        #expect(progress.elapsed == "18:42")
        #expect(progress.remaining == "−15:28")
        #expect(abs((progress.fraction ?? 0) - Float(1122.0 / 2050)) < 0.0001)
        #expect(progress.speed == "1,25×")
        #expect(progress.speedLabel == "Скорость 1,25×")
        #expect(progress.accessibilityValue == "18 минут 42 секунды из 34 минут")
        #expect(state.summaryLabel == "Превью 12 тура: дерби на Энфилде, Вне игры, 18 минут 42 секунды из 34 минут")
    }

    @Test func episodeArtworkWinsAndYearShownForOldEpisodes() throws {
        let artwork = URL(string: "https://example.com/ep.jpg")!
        #expect(try state(playback(episode: episode(artwork: artwork))).artworkURL == artwork)
        let old = PlayerFormatter.state(playback(), now: published.addingTimeInterval(400 * 86400), calendar: calendar)
        #expect(old?.subtitle == "Вне игры · 18 нояб 2026")
    }

    @Test func statusTextsForLoadingFailedAndPaused() throws {
        var state = try state(playback(.loading))
        #expect((state.status, state.statusTone, state.button) == ("Подключение…", .secondary, .loading))
        #expect(state.summaryLabel == "Превью 12 тура: дерби на Энфилде, Подключение…")

        state = try self.state(playback(.failed("Не удалось подключиться")))
        #expect((state.status, state.statusTone, state.subtitle, state.isError) == ("Не удалось подключиться", .error, "Не удалось подключиться", true))

        // На паузе мини-плеер показывает, где остановились.
        state = try self.state(playback(.paused))
        #expect((state.status, state.button) == ("Вне игры · 18:42 из 34:10", .play))
    }

    @Test func timeFormatting() {
        #expect(PlayerFormatter.time(0) == "0:00")
        #expect(PlayerFormatter.time(59.9) == "0:59")
        #expect(PlayerFormatter.time(59 * 60 + 59) == "59:59")
        #expect(PlayerFormatter.time(3600) == "1:00:00")
        #expect(PlayerFormatter.time(3600 + 5 * 60 + 7) == "1:05:07")
        #expect(PlayerFormatter.time(-3) == "0:00")
        #expect(PlayerFormatter.time(.nan) == "0:00")
    }

    @Test func progressEdges() throws {
        // Начало часового выпуска: остаток «−1:00:00», ползунок в нуле.
        var progress = try #require(try state(playback(position: 0, duration: 3600)).progress)
        #expect((progress.elapsed, progress.remaining, progress.fraction) == ("0:00", "−1:00:00", 0))
        #expect(progress.accessibilityValue == "0 секунд из 1 часа")

        // Позиции ещё нет — считаем с нуля.
        progress = try #require(try state(playback(position: nil)).progress)
        #expect(progress.elapsed == "0:00")

        // Длительность неизвестна: ползунок выключен, остатка нет, мини-плеер — только позиция.
        let state = try state(playback(duration: nil))
        progress = try #require(state.progress)
        #expect((progress.fraction, progress.remaining) == (nil, ""))
        #expect(progress.accessibilityValue == "18 минут 42 секунды")
        #expect(state.status == "Вне игры · 18:42")

        // Позиция за длительностью (длительность из ленты короче файла) — ползунок не вылезает.
        progress = try #require(try self.state(playback(position: 2100)).progress)
        #expect((progress.fraction, progress.remaining) == (1, "−0:00"))
    }

    @Test func spokenDurationsDecline() {
        #expect(PlayerFormatter.spoken(61, genitive: false) == "1 минута 1 секунда")
        #expect(PlayerFormatter.spoken(2 * 3600 + 22 * 60 + 3, genitive: false) == "2 часа 22 минуты 3 секунды")
        #expect(PlayerFormatter.spoken(21 * 60 + 30, genitive: true) == "22 минут")
        #expect(PlayerFormatter.spoken(21 * 60, genitive: true) == "21 минуты")
        #expect(PlayerFormatter.spoken(3600 + 60, genitive: true) == "1 часа 1 минуты")
        #expect(PlayerFormatter.spoken(5 * 3600, genitive: true) == "5 часов")
    }

    @Test func speedCycle() {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        for rate: Float in [0.75, 1, 1.25, 1.5, 2, 0.5] {
            player.subject.value = playback(rate: rate)
            viewModel.didTapSpeed()
        }
        #expect(player.rates == [1, 1.25, 1.5, 2, 0.75, 0.75])
        #expect(PlayerFormatter.speed(1) == "1×")
        #expect(PlayerFormatter.speed(0.75) == "0,75×")
        #expect(PlayerFormatter.speed(1.5) == "1,5×")
        #expect(PlayerFormatter.speed(2) == "2×")
    }

    @Test func skipsAndAccessibilityAdjustGoToPlayer() {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        player.subject.value = playback()
        viewModel.didTapSkip(by: -15)
        viewModel.didTapSkip(by: 30)
        viewModel.didAdjustAccessibility(forward: true)
        viewModel.didAdjustAccessibility(forward: false)
        #expect(player.skips == [-15, 30, 15, -15])
    }

    @Test func shareTextWithAndWithoutLink() {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        player.subject.value = playback(episode: episode(link: link))
        let items = viewModel.shareItems()
        #expect(items.count == 2)
        #expect(items.first as? String == "Превью 12 тура: дерби на Энфилде — Вне игры")
        #expect(items.last as? URL == link)

        player.subject.value = playback()
        #expect(viewModel.shareItems().count == 1)
    }

    /// Пока палец на ползунке, состояние плеера не двигает ни бегунок, ни время; перемотка — когда отпустили.
    @Test func scrubbingDoesNotFightStateUpdates() throws {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        player.subject.value = playback()

        viewModel.scrub(to: 0.5)
        #expect(viewModel.state?.progress?.elapsed == "17:05")
        #expect(viewModel.state?.progress?.remaining == "−17:05")
        #expect(viewModel.state?.progress?.fraction == 0.5)

        player.subject.value = playback(position: 1123)
        #expect(viewModel.state?.progress?.elapsed == "17:05")
        #expect(viewModel.state?.progress?.fraction == 0.5)
        #expect(player.seeks.isEmpty)

        viewModel.endScrubbing(at: 0.25)
        #expect(player.seeks == [512.5])
        player.subject.value = playback(position: 512.5)
        #expect(viewModel.state?.progress?.elapsed == "8:32")

        // После отпускания снова ведёт плеер.
        player.subject.value = playback(position: 600)
        #expect(viewModel.state?.progress?.elapsed == "10:00")
    }

    @Test func scrubbingWithoutDurationDoesNothing() {
        let player = FakeAudioPlayer()
        let viewModel = PlayerViewModel(player: player)
        player.subject.value = playback(duration: nil)
        viewModel.scrub(to: 0.5)
        viewModel.endScrubbing(at: 0.5)
        #expect(player.seeks.isEmpty)
        #expect(viewModel.state?.progress?.elapsed == "18:42")
    }
}
