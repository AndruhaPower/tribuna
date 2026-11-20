import CoreDomain
import Foundation
import Testing
@testable import FeatureToday

@MainActor
struct TodayViewModelTests {
    func makeViewModel(
        _ repository: FakeMatchesRepository,
        bookmarks: FakeBookmarksStore = FakeBookmarksStore(),
        timeZone: TimeZone = moscow,
        onOpenMatch: @escaping (MatchID) -> Void = { _ in }
    ) -> TodayViewModel {
        TodayViewModel(
            matches: repository, bookmarks: bookmarks, now: { now }, calendar: calendar(timeZone),
            onOpenMatch: onOpenMatch
        )
    }

    func loaded(_ viewModel: TodayViewModel) -> (events: [TodayState.EventCard], sections: [TodayState.Section])? {
        if case let .loaded(events, sections) = viewModel.state.content { return (events, sections) }
        return nil
    }

    func appear(_ viewModel: TodayViewModel) async {
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
    }

    @Test func daysStripFromYesterdayWithTodaySelected() {
        let viewModel = makeViewModel(FakeMatchesRepository())
        let days = viewModel.state.days

        #expect(days.count == 8)
        #expect(days[0].id == date("2026-11-17 00:00"))
        #expect(days[0].weekday == "Вт")
        #expect(days[0].number == "17")
        #expect(days.filter(\.isSelected).map(\.id) == [date("2026-11-18 00:00")])
        #expect(days[1].weekday == "Ср")
        #expect(days[1].number == "18")
        #expect(days.map(\.weekday) == ["Вт", "Ср", "Чт", "Пт", "Сб", "Вс", "Пн", "Вт"])
        #expect(viewModel.state.content == .loading)
    }

    @Test func sectionsOrderedByCompetitionWithCounts() async throws {
        let repository = FakeMatchesRepository([
            match("nhl1", "NHL", "НХЛ", at: "2026-11-18 21:00"),
            match("pl1", "PL", "АПЛ", at: "2026-11-18 22:00"),
            match("cl2", "CL", "Лига чемпионов", at: "2026-11-18 23:00"),
            match("cl1", "CL", "Лига чемпионов", at: "2026-11-18 20:45"),
            match("bl1", "BL1", "Бундеслига", at: "2026-11-18 17:30"),
            match("bl2", "BL1", "Бундеслига", at: "2026-11-18 17:30"),
            match("bl3", "BL1", "Бундеслига", at: "2026-11-18 17:30"),
            match("bl4", "BL1", "Бундеслига", at: "2026-11-18 17:30"),
            match("bl5", "BL1", "Бундеслига", at: "2026-11-18 20:30"),
        ])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        let sections = try #require(loaded(viewModel)).sections
        #expect(sections.map(\.id) == ["CL", "PL", "BL1", "NHL"])
        #expect(sections.map(\.title) == ["ЛИГА ЧЕМПИОНОВ", "АПЛ", "БУНДЕСЛИГА", "НХЛ"])
        #expect(sections.map(\.trailing) == ["2 матча", "1 матч", "5 матчей", "1 матч"])
        #expect(sections[0].rows.map(\.id.rawValue) == ["cl1", "cl2"])
        #expect(sections[0].emblemURL != nil && sections[3].emblemURL == nil)
        #expect(repository.calls == 1)
    }

    @Test func nightNHLSectionSaysNightOnNextDay() async throws {
        let repository = FakeMatchesRepository([
            match("nhl1", "NHL", "НХЛ", at: "2026-11-19 04:30"),
            match("nhl2", "NHL", "НХЛ", at: "2026-11-19 03:00"),
        ])
        let viewModel = makeViewModel(repository)
        viewModel.didSelectDay(date("2026-11-19 00:00"))
        await viewModel.loadTask?.value

        let section = try #require(loaded(viewModel)?.sections.first)
        #expect(section.trailing == "ночь на чт")
        #expect(section.rows.map(\.leading) == ["03:00", "04:30"])
    }

    @Test func rowsFormatStatusesAndUnknownTeam() async throws {
        let repository = FakeMatchesRepository([
            match("s", at: "2026-11-18 22:00"),
            match("f", at: "2026-11-18 14:00", status: .finished, score: (2, 1)),
            match("l", at: "2026-11-18 19:00", status: .live, score: (2, 1)),
            match("p", at: "2026-11-18 16:00", status: .postponed),
            match("n", at: "2026-11-18 23:00", home: nil, away: "Бавария"),
        ])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        let rows = try #require(loaded(viewModel)?.sections.first?.rows)
        #expect(rows.map(\.leading) == ["2 : 1", "Перенесён", "LIVE 2 : 1", "22:00", "23:00"])
        #expect(rows[4].home == "—")
        #expect(rows[4].away == "Бавария")
        #expect(rows[3].home == "Ливерпуль")
    }

    @Test func bookmarkedMatchShowsInEventsAndToggleUpdatesWithoutRefetch() async throws {
        let repository = FakeMatchesRepository([
            match("pl1", at: "2026-11-18 22:00", status: .live, score: (1, 0)),
            match("pl2", at: "2026-11-18 23:00"),
        ])
        let bookmarks = FakeBookmarksStore(["pl1"])
        let viewModel = makeViewModel(repository, bookmarks: bookmarks)
        await appear(viewModel)

        let content = try #require(loaded(viewModel))
        let event = try #require(content.events.first)
        #expect(content.events.count == 1)
        #expect(event.header == "АПЛ · 12 тур")
        #expect(event.isLive)
        #expect(event.home == TodayState.TeamItem(name: "Ливерпуль", abbreviation: "ЛИВ", logoURL: URL(string: "https://crests.test/Ливерпуль.png")))
        #expect(content.sections[0].emblemURL == URL(string: "https://crests.test/PL.png"))
        #expect(event.homeScore == "1")
        #expect(event.awayScore == "0")
        #expect(event.statusText == "LIVE")
        #expect(content.sections[0].rows.map(\.isBookmarked) == [true, false])

        viewModel.didToggleBookmark(MatchID(rawValue: "pl2"))

        let updated = try #require(loaded(viewModel))
        #expect(updated.events.map(\.id.rawValue) == ["pl1", "pl2"])
        #expect(updated.events[1].statusText == "23:00")
        #expect(updated.events[1].homeScore.isEmpty)
        #expect(updated.events[1].awayScore.isEmpty)
        #expect(!updated.events[1].isLive)
        #expect(updated.sections[0].rows.map(\.isBookmarked) == [true, true])
        #expect(bookmarks.bookmarks.contains(MatchID(rawValue: "pl2")))
        #expect(repository.calls == 1)
    }

    @Test func selectDayRequestsLocalDayInterval() async {
        let repository = FakeMatchesRepository()
        let viewModel = makeViewModel(repository)
        viewModel.didSelectDay(date("2026-11-19 00:00"))
        await viewModel.loadTask?.value

        #expect(repository.intervals == [DateInterval(start: date("2026-11-19 00:00"), end: date("2026-11-20 00:00"))])
        #expect(viewModel.state.days.filter(\.isSelected).map(\.number) == ["19"])
    }

    @Test func selectDayUsesCalendarTimeZone() async {
        let vladivostok = TimeZone(identifier: "Asia/Vladivostok")!
        let repository = FakeMatchesRepository()
        let viewModel = makeViewModel(repository, timeZone: vladivostok)
        // 20:00 Москва = 03:00 19.11 во Владивостоке: сегодня там уже 19-е.
        #expect(viewModel.state.days.filter(\.isSelected).map(\.number) == ["19"])

        viewModel.didSelectDay(date("2026-11-20 00:00", vladivostok))
        await viewModel.loadTask?.value

        let expected = DateInterval(start: date("2026-11-20 00:00", vladivostok), end: date("2026-11-21 00:00", vladivostok))
        #expect(repository.intervals == [expected])
        #expect(expected.start == date("2026-11-19 17:00"))
    }

    @Test func errorThenRetryLoads() async throws {
        let repository = FakeMatchesRepository([match("pl1")])
        repository.result = .failure(FakeError())
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        #expect(viewModel.state.content == .error(message: "Не удалось загрузить матчи"))

        repository.result = .success([match("pl1")])
        viewModel.didTapRetry()
        await viewModel.loadTask?.value

        #expect(repository.calls == 2)
        #expect(loaded(viewModel)?.sections.count == 1)
    }

    @Test func emptyResponseIsEmpty() async {
        let viewModel = makeViewModel(FakeMatchesRepository())
        await appear(viewModel)

        #expect(viewModel.state.content == .empty)
    }

    @Test func pullToRefreshRequestsAgain() async {
        let repository = FakeMatchesRepository([match("pl1")])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)
        viewModel.didPullToRefresh()
        await viewModel.loadTask?.value

        #expect(repository.calls == 2)
    }

    @Test func eventStatusTextForFinishedPostponedCancelled() async throws {
        let repository = FakeMatchesRepository([
            match("f", at: "2026-11-18 14:00", status: .finished, score: (2, 1)),
            match("p", at: "2026-11-18 15:00", status: .postponed),
            match("c", at: "2026-11-18 16:00", status: .cancelled),
        ])
        let viewModel = makeViewModel(repository, bookmarks: FakeBookmarksStore(["f", "p", "c"]))
        await appear(viewModel)

        let events = try #require(loaded(viewModel)).events
        #expect(events.map(\.statusText) == ["Завершён", "Перенесён", "Отменён"])
        #expect(events.map(\.homeScore) == ["2", "", ""])
    }

    @Test func pullToRefreshFailureKeepsContentAndStopsRefreshing() async throws {
        let repository = FakeMatchesRepository([match("pl1")])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)
        let content = viewModel.state.content
        #expect(!viewModel.state.isRefreshing)

        repository.result = .failure(FakeError())
        viewModel.didPullToRefresh()
        #expect(viewModel.state.isRefreshing)
        await viewModel.loadTask?.value

        #expect(!viewModel.state.isRefreshing)
        #expect(viewModel.state.content == content)
        #expect(repository.calls == 2)
    }

    @Test func daySwitchIgnoresLateResponseForPreviousDay() async throws {
        let today = date("2026-11-18 00:00"), tomorrow = date("2026-11-19 00:00")
        let repository = FakeMatchesRepository(
            byDay: [today: [match("d18")], tomorrow: [match("d19", at: "2026-11-19 21:00")]],
            held: true
        )
        let viewModel = makeViewModel(repository)
        viewModel.viewDidAppear()
        let first = viewModel.loadTask
        viewModel.didSelectDay(tomorrow)
        let second = viewModel.loadTask

        repository.release(tomorrow)
        await second?.value
        repository.release(today)
        await first?.value

        #expect(loaded(viewModel)?.sections.first?.rows.map(\.id.rawValue) == ["d19"])
        #expect(viewModel.state.days.filter(\.isSelected).map(\.id) == [tomorrow])
        #expect(viewModel.loadTask == nil)
    }

    @Test func tickRefreshesWhenLiveAndVisible() async {
        let repository = FakeMatchesRepository([match("pl1", status: .live, score: (0, 0))])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        viewModel.tick()
        await viewModel.loadTask?.value

        #expect(repository.calls == 2)
    }

    @Test func tickRefreshesWhenKickoffWithin15Minutes() async {
        let repository = FakeMatchesRepository([match("pl1", at: "2026-11-18 20:10")])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        viewModel.tick()
        await viewModel.loadTask?.value

        #expect(repository.calls == 2)
    }

    @Test func tickSkipsWhenNothingLiveOrSoon() async {
        let repository = FakeMatchesRepository([
            match("pl1", at: "2026-11-18 20:30"),
            match("pl2", at: "2026-11-18 14:00", status: .finished, score: (1, 1)),
        ])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        viewModel.tick()

        #expect(viewModel.loadTask == nil)
        #expect(repository.calls == 1)
    }

    @Test func tickSkipsAfterDisappear() async {
        let repository = FakeMatchesRepository([match("pl1", status: .live, score: (0, 0))])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        viewModel.viewDidDisappear()
        viewModel.tick()

        #expect(viewModel.loadTask == nil)
        #expect(repository.calls == 1)
    }

    @Test func tickSkipsWhenOtherDaySelected() async {
        let repository = FakeMatchesRepository([match("pl1", at: "2026-11-19 21:00", status: .live, score: (0, 0))])
        let viewModel = makeViewModel(repository)
        viewModel.viewDidAppear()
        viewModel.didSelectDay(date("2026-11-19 00:00"))
        await viewModel.loadTask?.value

        viewModel.tick()

        #expect(viewModel.loadTask == nil)
        #expect(repository.calls == 2)
    }

    @Test func tickDoesNotStartSecondRequestWhileInFlight() async {
        let repository = FakeMatchesRepository([match("pl1", status: .live, score: (0, 0))], held: true)
        let viewModel = makeViewModel(repository)
        repository.release()
        await appear(viewModel)

        viewModel.tick()
        let inFlight = viewModel.loadTask
        viewModel.tick()
        viewModel.tick()
        #expect(viewModel.loadTask == inFlight)

        repository.release()
        await inFlight?.value
        #expect(repository.calls == 2)
    }

    @Test func tapMatchOpensMatch() async {
        var opened: [MatchID] = []
        let viewModel = makeViewModel(FakeMatchesRepository([match("pl1")])) { opened.append($0) }
        await appear(viewModel)

        viewModel.didTapMatch(MatchID(rawValue: "pl1"))

        #expect(opened.map(\.rawValue) == ["pl1"])
    }

    final class Clock { var date: Date; init(_ date: Date) { self.date = date } }

    func makeViewModel(_ repository: FakeMatchesRepository, clock: Clock) -> TodayViewModel {
        TodayViewModel(
            matches: repository, bookmarks: FakeBookmarksStore(), now: { clock.date }, calendar: calendar(),
            onOpenMatch: { _ in }
        )
    }

    @Test func foregroundAfterMidnightMovesTodaySelection() async {
        let clock = Clock(now)
        let repository = FakeMatchesRepository()
        let viewModel = makeViewModel(repository, clock: clock)
        await appear(viewModel)

        clock.date = date("2026-11-19 00:30")
        viewModel.didEnterForeground()
        await viewModel.loadTask?.value

        #expect(viewModel.state.days[0].id == date("2026-11-18 00:00"))
        #expect(viewModel.state.days.filter(\.isSelected).map(\.id) == [date("2026-11-19 00:00")])
        #expect(repository.intervals.last?.start == date("2026-11-19 00:00"))
        #expect(repository.calls == 2)
    }

    @Test func foregroundKeepsOtherSelectedDayAndReloads() async {
        let clock = Clock(now)
        let repository = FakeMatchesRepository()
        let viewModel = makeViewModel(repository, clock: clock)
        await appear(viewModel)
        viewModel.didSelectDay(date("2026-11-20 00:00"))
        await viewModel.loadTask?.value

        viewModel.didEnterForeground()
        await viewModel.loadTask?.value

        #expect(viewModel.state.days.filter(\.isSelected).map(\.id) == [date("2026-11-20 00:00")])
        #expect(repository.calls == 3)
        #expect(repository.intervals.last?.start == date("2026-11-20 00:00"))
    }

    @Test func foregroundWhenNotVisibleDoesNotRequest() async {
        let repository = FakeMatchesRepository()
        let viewModel = makeViewModel(repository, clock: Clock(now))

        viewModel.didEnterForeground()
        await viewModel.loadTask?.value

        #expect(repository.calls == 0)
    }

    @Test func selectingSameDayIsNoOp() async {
        let repository = FakeMatchesRepository([match("pl1")])
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        viewModel.didSelectDay(date("2026-11-18 15:00"))

        #expect(loaded(viewModel) != nil)
        #expect(repository.calls == 1)
    }
}
