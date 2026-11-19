import CoreDomain
import Foundation
import Testing
@testable import FeatureMatch

@MainActor
struct MatchViewModelTests {
    let bookmarks = FakeBookmarksStore()
    let reminders = FakeRemindersStore()

    func makeViewModel(
        _ repository: FakeMatchesRepository,
        standings: FakeStandingsRepository = FakeStandingsRepository(),
        id: MatchID = footballID,
        now: @escaping () -> Date = { now }
    ) -> MatchViewModel {
        MatchViewModel(
            matchID: id, matches: repository, standings: standings, bookmarks: bookmarks, reminders: reminders,
            now: now, calendar: calendar()
        )
    }

    func appear(_ viewModel: MatchViewModel) async {
        viewModel.viewDidAppear()
        await viewModel.loadTask?.value
    }

    func loaded(_ viewModel: MatchViewModel) -> MatchState.Card? {
        if case let .loaded(card) = viewModel.state.content { return card }
        return nil
    }

    @Test func scheduledFootballMatch() async throws {
        let viewModel = makeViewModel(FakeMatchesRepository(match()))
        #expect(viewModel.state.content == .loading)
        await appear(viewModel)

        let card = try #require(loaded(viewModel))
        #expect(card.header == "АПЛ · 12 тур")
        #expect(card.standingsTitle == "ТАБЛИЦА АПЛ")
        #expect(card.statusText == "22:00")
        #expect(!card.isLive)
        #expect(card.home == MatchState.TeamItem(name: "Ливерпуль", abbreviation: "LIV"))
        #expect(card.away == MatchState.TeamItem(name: "Арсенал", abbreviation: "ARS"))
        #expect(card.score.isEmpty)
        #expect(!card.showsDelayNote)
        #expect(!card.isBookmarked)
        #expect(card.reminder == .off)
        #expect(card.shareText == "Ливерпуль — Арсенал, 22:00 · АПЛ, 12 тур")
    }

    @Test func liveFootballMatchShowsScoreAndDelayNote() async throws {
        let viewModel = makeViewModel(FakeMatchesRepository(match(at: "2026-11-18 19:00", status: .live, score: (2, 1))))
        await appear(viewModel)

        let card = try #require(loaded(viewModel))
        #expect(card.statusText == "LIVE")
        #expect(card.isLive)
        #expect(card.score == "2 : 1")
        #expect(card.showsDelayNote)
        #expect(card.reminder == .hidden)
        #expect(card.shareText == "Ливерпуль — Арсенал, 2 : 1 · АПЛ, 12 тур")
    }

    @Test(arguments: [
        (MatchStatus.paused, "LIVE", true, "1 : 1", true),
        (.finished, "Завершён", false, "1 : 1", false),
        (.postponed, "Перенесён", false, "", false),
        (.cancelled, "Отменён", false, "", false),
    ])
    func statusesHideReminder(
        status: MatchStatus, text: String, isLive: Bool, score: String, delayNote: Bool
    ) async throws {
        let hasScore = status == .paused || status == .finished
        let viewModel = makeViewModel(FakeMatchesRepository(match(status: status, score: hasScore ? (1, 1) : nil)))
        await appear(viewModel)

        let card = try #require(loaded(viewModel))
        #expect(card.statusText == text)
        #expect(card.isLive == isLive)
        #expect(card.score == score)
        #expect(card.reminder == .hidden)
        #expect(card.showsDelayNote == delayNote)
    }

    @Test func kickoffOnAnotherDayShowsDate() async throws {
        let tomorrow = makeViewModel(FakeMatchesRepository(match(at: "2026-11-19 18:00")))
        await appear(tomorrow)
        let tomorrowCard = try #require(loaded(tomorrow))
        #expect(tomorrowCard.statusText == "Завтра, 18:00")
        #expect(tomorrowCard.shareText == "Ливерпуль — Арсенал, завтра, 18:00 · АПЛ, 12 тур")

        let saturday = makeViewModel(FakeMatchesRepository(match(at: "2026-11-21 18:00")))
        await appear(saturday)
        let saturdayCard = try #require(loaded(saturday))
        #expect(saturdayCard.statusText == "Сб, 21 нояб · 18:00")
        #expect(saturdayCard.shareText == "Ливерпуль — Арсенал, Сб, 21 нояб · 18:00 · АПЛ, 12 тур")

        let sameDay = makeViewModel(FakeMatchesRepository(match(at: "2026-11-18 23:30")))
        await appear(sameDay)
        #expect(try #require(loaded(sameDay)).statusText == "23:30")
    }

    @Test func hockeyMatchHasNoTableNoDelayNote() async throws {
        let standings = FakeStandingsRepository()
        let repository = FakeMatchesRepository(match(hockeyID, at: "2026-11-18 19:00", status: .live, score: (3, 2)))
        let viewModel = makeViewModel(repository, standings: standings, id: hockeyID)
        await appear(viewModel)

        let card = try #require(loaded(viewModel))
        #expect(card.header == "НХЛ")
        #expect(!card.showsDelayNote)
        #expect(card.standings == [])
        #expect(standings.codes.isEmpty)
        #expect(card.shareText == "Ливерпуль — Арсенал, 3 : 2 · НХЛ")
    }

    @Test func standingsHighlightBothTeams() async throws {
        let standings = FakeStandingsRepository()
        let viewModel = makeViewModel(FakeMatchesRepository(match()), standings: standings)
        await appear(viewModel)

        let rows = try #require(loaded(viewModel)).standings
        #expect(standings.codes == ["PL"])
        #expect(rows.map(\.position) == ["1", "2", "3"])
        #expect(rows.map(\.name) == ["Арсенал", "Манчестер Сити", "Ливерпуль"])
        #expect(rows.map(\.played) == ["12", "12", "12"])
        #expect(rows.map(\.points) == ["29", "28", "27"])
        #expect(rows.map(\.isHighlighted) == [true, false, true])
    }

    @Test func teamsMissingFromTableAreNotHighlighted() async throws {
        let standings = FakeStandingsRepository([row(1, "Бавария", "5"), row(2, "Интер", "108")])
        let viewModel = makeViewModel(FakeMatchesRepository(match()), standings: standings)
        await appear(viewModel)

        let rows = try #require(loaded(viewModel)).standings
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { !$0.isHighlighted })
    }

    @Test func noTableMeansEmptyStandings() async throws {
        let viewModel = makeViewModel(FakeMatchesRepository(match()), standings: FakeStandingsRepository([]))
        await appear(viewModel)

        #expect(try #require(loaded(viewModel)).standings == [])
    }

    @Test func standingsFailureStillShowsMatch() async throws {
        let standings = FakeStandingsRepository()
        standings.result = .failure(FakeError())
        let viewModel = makeViewModel(FakeMatchesRepository(match()), standings: standings)
        await appear(viewModel)

        #expect(try #require(loaded(viewModel)).standings == [])
    }

    @Test func missingMatchIsNotFound() async {
        let viewModel = makeViewModel(FakeMatchesRepository(nil))
        await appear(viewModel)

        #expect(viewModel.state.content == .notFound)
    }

    @Test func errorThenRetryLoads() async throws {
        let repository = FakeMatchesRepository(match())
        repository.result = .failure(FakeError())
        let viewModel = makeViewModel(repository)
        await appear(viewModel)
        #expect(viewModel.state.content == .error(message: "Не удалось загрузить матч"))

        repository.result = .success(match())
        viewModel.didTapRetry()
        #expect(viewModel.state.content == .loading)
        await viewModel.loadTask?.value

        #expect(loaded(viewModel) != nil)
        #expect(repository.calls == 2)
    }

    @Test func refreshFailureKeepsShownMatch() async throws {
        let repository = FakeMatchesRepository(match(at: "2026-11-18 19:00", status: .live, score: (0, 0)))
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        repository.result = .failure(FakeError())
        viewModel.tick()
        await viewModel.loadTask?.value

        #expect(try #require(loaded(viewModel)).score == "0 : 0")
    }

    @Test func reminderHiddenWhenKickoffWithin15Minutes() async throws {
        let soon = makeViewModel(FakeMatchesRepository(match(at: "2026-11-18 20:15")))
        await appear(soon)
        #expect(try #require(loaded(soon)).reminder == .hidden)

        let later = makeViewModel(FakeMatchesRepository(match(at: "2026-11-18 20:16")))
        await appear(later)
        #expect(try #require(loaded(later)).reminder == .off)
    }

    @Test func reminderHidesOnTickWhenKickoffComesClose() async throws {
        var current = now
        let viewModel = makeViewModel(FakeMatchesRepository(match(at: "2026-11-18 20:30")), now: { current })
        await appear(viewModel)
        #expect(try #require(loaded(viewModel)).reminder == .off)

        current = date("2026-11-18 20:20")
        viewModel.tick()

        #expect(try #require(loaded(viewModel)).reminder == .hidden)
    }

    @Test func tapRemindSchedulesAndCancels() async throws {
        let viewModel = makeViewModel(FakeMatchesRepository(match()))
        await appear(viewModel)

        let alert = await viewModel.didTapRemind()
        #expect(!alert)
        #expect(reminders.scheduledMatches == [footballID])
        #expect(try #require(loaded(viewModel)).reminder == .on)

        let second = await viewModel.didTapRemind()
        #expect(!second)
        #expect(reminders.scheduled.isEmpty)
        #expect(try #require(loaded(viewModel)).reminder == .off)
    }

    @Test func repeatTapWhileSchedulingIsIgnored() async throws {
        reminders.held = true
        let viewModel = makeViewModel(FakeMatchesRepository(match()))
        await appear(viewModel)

        let first = Task { await viewModel.didTapRemind() }
        while reminders.scheduledMatches.isEmpty { await Task.yield() }
        let second = await viewModel.didTapRemind()
        #expect(!second)
        #expect(reminders.scheduledMatches == [footballID])

        reminders.release()
        #expect(await first.value == false)
        #expect(reminders.scheduledMatches == [footballID])
        #expect(try #require(loaded(viewModel)).reminder == .on)
    }

    @Test func deniedRemindStaysOffAndAsksForAlert() async throws {
        reminders.scheduleResult = .denied
        let viewModel = makeViewModel(FakeMatchesRepository(match()))
        await appear(viewModel)

        let alert = await viewModel.didTapRemind()

        #expect(alert)
        #expect(try #require(loaded(viewModel)).reminder == .off)
    }

    @Test func bookmarkAndReminderFollowStoresWithoutRefetch() async throws {
        let repository = FakeMatchesRepository(match())
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        bookmarks.subject.value = [footballID]
        reminders.subject.value = [footballID]
        #expect(try #require(loaded(viewModel)).isBookmarked)
        #expect(try #require(loaded(viewModel)).reminder == .on)

        viewModel.didToggleBookmark()
        #expect(bookmarks.bookmarks.isEmpty)
        #expect(try #require(loaded(viewModel)).isBookmarked == false)

        reminders.subject.value = []
        #expect(try #require(loaded(viewModel)).reminder == .off)
        #expect(repository.calls == 1)
    }

    @Test func tickRefreshesOnlyLiveMatch() async {
        let live = FakeMatchesRepository(match(at: "2026-11-18 19:00", status: .live, score: (0, 0)))
        let liveModel = makeViewModel(live)
        await appear(liveModel)
        liveModel.tick()
        await liveModel.loadTask?.value
        #expect(live.calls == 2)

        let scheduled = FakeMatchesRepository(match())
        let scheduledModel = makeViewModel(scheduled)
        await appear(scheduledModel)
        scheduledModel.tick()
        #expect(scheduledModel.loadTask == nil)
        #expect(scheduled.calls == 1)
    }

    @Test func tickReloadsScheduledMatchWhenKickoffPassed() async {
        var current = now
        let repository = FakeMatchesRepository(match(at: "2026-11-18 20:30"))
        let viewModel = makeViewModel(repository, now: { current })
        await appear(viewModel)

        current = date("2026-11-18 20:31")
        viewModel.tick()
        await viewModel.loadTask?.value
        #expect(repository.calls == 2)
    }

    @Test func freshMatchReconcilesExistingReminder() async {
        reminders.subject.value = [footballID]
        let fresh = match(at: "2026-11-18 22:00", status: .postponed)
        let viewModel = makeViewModel(FakeMatchesRepository(fresh))
        await appear(viewModel)
        #expect(reminders.reconciled == [[fresh]])

        let other = makeViewModel(FakeMatchesRepository(match(hockeyID)), id: hockeyID)
        await appear(other)
        #expect(reminders.reconciled.count == 1)
    }

    @Test func tickSkipsAfterDisappear() async {
        let repository = FakeMatchesRepository(match(at: "2026-11-18 19:00", status: .live, score: (0, 0)))
        let viewModel = makeViewModel(repository)
        await appear(viewModel)

        viewModel.viewDidDisappear()
        viewModel.tick()

        #expect(viewModel.loadTask == nil)
        #expect(repository.calls == 1)
    }

    @Test func noParallelRequests() async {
        let repository = FakeMatchesRepository(match(at: "2026-11-18 19:00", status: .live, score: (0, 0)), held: true)
        let viewModel = makeViewModel(repository)
        repository.release()
        await appear(viewModel)

        viewModel.tick()
        let inFlight = viewModel.loadTask
        viewModel.tick()
        viewModel.didEnterForeground()
        viewModel.viewDidAppear()
        #expect(viewModel.loadTask == inFlight)

        repository.release()
        await inFlight?.value
        #expect(repository.calls == 2)
    }

    @Test func foregroundReloadsOnlyWhenVisible() async {
        let repository = FakeMatchesRepository(match())
        let viewModel = makeViewModel(repository)

        viewModel.didEnterForeground()
        #expect(viewModel.loadTask == nil)
        #expect(repository.calls == 0)

        await appear(viewModel)
        viewModel.didEnterForeground()
        await viewModel.loadTask?.value
        #expect(repository.calls == 2)
    }
}
