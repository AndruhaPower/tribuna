import Combine
import CoreDomain
import Foundation

@MainActor
final class MatchViewModel {
    @Published private(set) var state = MatchState(content: .loading)

    /// Текущий запрос; тесты ждут его `value`.
    private(set) var loadTask: Task<Void, Never>?

    private let matchID: MatchID
    private let matchesRepository: MatchesRepository
    private let standingsRepository: StandingsRepository
    private let bookmarksStore: BookmarksStore
    private let remindersStore: RemindersStore
    private let now: () -> Date
    private let calendar: Calendar

    private var match: Match?
    private var standings: [StandingRow] = []
    private var bookmarks: Set<MatchID>
    private var reminders: Set<MatchID>
    private var isVisible = false
    /// Идёт `schedule` — повторные нажатия игнорируются.
    private var isSchedulingReminder = false
    private var timerTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    init(
        matchID: MatchID,
        matches: MatchesRepository,
        standings: StandingsRepository,
        bookmarks: BookmarksStore,
        reminders: RemindersStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.matchID = matchID
        matchesRepository = matches
        standingsRepository = standings
        bookmarksStore = bookmarks
        remindersStore = reminders
        self.now = now
        self.calendar = calendar
        self.bookmarks = bookmarks.bookmarks
        self.reminders = reminders.scheduled
        // Закладку и напоминание могут поменять на «Сегодня» — карточка следует за хранилищами.
        bookmarks.bookmarksPublisher
            .sink { [weak self] ids in MainActor.assumeIsolated { self?.bookmarks = ids; self?.render() } }
            .store(in: &subscriptions)
        reminders.scheduledPublisher
            .sink { [weak self] ids in MainActor.assumeIsolated { self?.reminders = ids; self?.render() } }
            .store(in: &subscriptions)
    }

    deinit {
        timerTask?.cancel()
    }

    func viewDidAppear() {
        isVisible = true
        load()
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

    func didEnterForeground() {
        guard isVisible else { return }
        load()
    }

    func didTapRetry() {
        state.content = .loading
        load()
    }

    func didToggleBookmark() {
        bookmarksStore.toggle(matchID)
    }

    /// Ставит или снимает напоминание. true — уведомления запрещены, показать алерт со ссылкой в Настройки.
    /// Состояние кнопки берётся из паблишера хранилища, а не из результата.
    func didTapRemind() async -> Bool {
        if reminders.contains(matchID) {
            remindersStore.cancel(matchID)
            return false
        }
        guard let match, !isSchedulingReminder else { return false }
        isSchedulingReminder = true
        defer { isSchedulingReminder = false }
        return (try? await remindersStore.schedule(match)) == .denied
    }

    /// Тик раз в 60 с, пока экран виден: перерисовка (кнопка напоминания прячется ближе к старту)
    /// и обновление, пока матч идёт.
    func tick() {
        guard isVisible else { return }
        render()
        guard loadTask == nil, let match, match.status == .live || match.status == .paused else { return }
        load()
    }

    /// Без параллельных запросов: пока идёт загрузка, новые не начинаются.
    private func load() {
        guard loadTask == nil else { return }
        let id = matchID
        let matchesRepository = matchesRepository
        let standingsRepository = standingsRepository
        loadTask = Task { [weak self] in
            let result: Result<(Match?, [StandingRow]), Error>
            do {
                let match = try await matchesRepository.match(id: id)
                // Таблица только для футбола; её ошибка не мешает показать матч.
                var rows: [StandingRow] = []
                if let match, match.sport == .football {
                    rows = (try? await standingsRepository.standings(competitionCode: match.competition.code)) ?? []
                }
                result = .success((match, rows))
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.loadTask = nil
            self.apply(result)
        }
    }

    private func apply(_ result: Result<(Match?, [StandingRow]), Error>) {
        switch result {
        case let .success((match, rows)):
            self.match = match
            standings = rows
            if match == nil { state.content = .notFound } else { render() }
        case .failure:
            // Тихое обновление не затирает уже показанный матч.
            if match == nil { state.content = .error(message: "Не удалось загрузить матч") }
        }
    }

    private func render() {
        guard let match else { return }
        state.content = .loaded(MatchFormatter.card(
            match,
            standings: standings,
            isBookmarked: bookmarks.contains(matchID),
            isReminderScheduled: reminders.contains(matchID),
            now: now(),
            calendar: calendar
        ))
    }
}
