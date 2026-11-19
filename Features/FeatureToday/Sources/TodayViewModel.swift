import Combine
import CoreDomain
import Foundation

@MainActor
final class TodayViewModel {
    @Published private(set) var state: TodayState

    /// Текущий запрос; тесты ждут его `value`.
    private(set) var loadTask: Task<Void, Never>?

    private let matchesRepository: MatchesRepository
    private let bookmarksStore: BookmarksStore
    private let now: () -> Date
    private let calendar: Calendar
    private let onOpenMatch: (MatchID) -> Void

    private var selectedDay: Date
    /// Выбранный день был «сегодня» в момент выбора — при смене суток переезжает на новое «сегодня».
    private var followsToday = true
    private var matches: [Match] = []
    private var bookmarks: Set<MatchID>
    private var isVisible = false
    private var timerTask: Task<Void, Never>?
    private var bookmarksSubscription: AnyCancellable?

    init(
        matches: MatchesRepository,
        bookmarks: BookmarksStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        onOpenMatch: @escaping (MatchID) -> Void
    ) {
        matchesRepository = matches
        bookmarksStore = bookmarks
        self.now = now
        self.calendar = calendar
        self.onOpenMatch = onOpenMatch
        self.bookmarks = bookmarks.bookmarks
        let today = calendar.startOfDay(for: now())
        selectedDay = today
        state = TodayState(days: TodayFormatter.days(today: today, selected: today, calendar: calendar), content: .loading)
        bookmarksSubscription = bookmarks.bookmarksPublisher.sink { [weak self] ids in
            MainActor.assumeIsolated { self?.bookmarksChanged(ids) }
        }
    }

    deinit {
        timerTask?.cancel()
    }

    func viewDidAppear() {
        isVisible = true
        load(cancellingCurrent: false)
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while true {
                do { try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC) } catch { break }
                self?.tick()
            }
        }
    }

    func viewDidDisappear() {
        isVisible = false
        timerTask?.cancel()
        timerTask = nil
    }

    func didSelectDay(_ id: Date) {
        let day = calendar.startOfDay(for: id)
        guard day != selectedDay else { return }
        selectedDay = day
        followsToday = calendar.isDate(day, inSameDayAs: now())
        matches = []
        state.days = TodayFormatter.days(today: now(), selected: selectedDay, calendar: calendar)
        state.content = .loading
        load(cancellingCurrent: true)
    }

    func didPullToRefresh() {
        state.isRefreshing = true
        load(cancellingCurrent: false)
    }

    func didTapRetry() {
        state.content = .loading
        load(cancellingCurrent: false)
    }

    func didToggleBookmark(_ id: MatchID) {
        bookmarksStore.toggle(id)
    }

    func didTapMatch(_ id: MatchID) {
        onOpenMatch(id)
    }

    /// Возврат в приложение: пересчёт полосы дней (могли смениться сутки) и обновление данных.
    func didEnterForeground() {
        let dayChanged = followsToday && !calendar.isDate(selectedDay, inSameDayAs: now())
        if dayChanged {
            selectedDay = calendar.startOfDay(for: now())
            matches = []
            state.content = .loading
        }
        state.days = TodayFormatter.days(today: now(), selected: selectedDay, calendar: calendar)
        guard isVisible else { return }
        load(cancellingCurrent: dayChanged)
    }

    /// Тик автообновления (раз в 60 с, пока экран виден).
    func tick() {
        guard isVisible, loadTask == nil, calendar.isDate(selectedDay, inSameDayAs: now()) else { return }
        let soon = now().addingTimeInterval(15 * 60)
        let needsRefresh = matches.contains {
            $0.status == .live || $0.status == .paused || ($0.status == .scheduled && $0.kickoff <= soon)
        }
        if needsRefresh { load(cancellingCurrent: false) }
    }

    private func load(cancellingCurrent: Bool) {
        if cancellingCurrent {
            loadTask?.cancel()
        } else if loadTask != nil {
            return
        }
        let start = selectedDay
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        let repository = matchesRepository
        loadTask = Task { [weak self] in
            let result: Result<[Match], Error>
            do {
                result = .success(try await repository.matches(in: DateInterval(start: start, end: end)))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.loadTask = nil
            self.apply(result)
        }
    }

    private func apply(_ result: Result<[Match], Error>) {
        state.isRefreshing = false
        switch result {
        case let .success(matches):
            self.matches = matches
            render()
        case .failure:
            // Тихое обновление не затирает уже показанные матчи.
            if matches.isEmpty { state.content = .error(message: "Не удалось загрузить матчи") }
        }
    }

    private func bookmarksChanged(_ ids: Set<MatchID>) {
        bookmarks = ids
        if case .loaded = state.content { render() }
    }

    private func render() {
        state.content = TodayFormatter.content(matches: matches, bookmarks: bookmarks, day: selectedDay, calendar: calendar)
    }
}
