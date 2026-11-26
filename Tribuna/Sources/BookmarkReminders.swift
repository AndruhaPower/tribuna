#if FEATURE_PROFILE2
import Combine
import CoreDomain
import Foundation

/// «Начало событий» (1.2, D41): пока включено, каждая закладка сама ставит напоминание за 15 минут;
/// включили — ставим по всем закладкам, выключили — снимаем по закладкам. «Напомнить» в карточке работает как раньше.
@MainActor
final class BookmarkReminders {
    private let settings: ProfileSettings
    private let bookmarks: BookmarksStore
    private let reminders: RemindersStore
    private let matches: MatchesRepository
    private var known: Set<MatchID>
    private var enabled: Bool
    private var subscriptions: Set<AnyCancellable> = []

    init(settings: ProfileSettings, bookmarks: BookmarksStore, reminders: RemindersStore, matches: MatchesRepository) {
        self.settings = settings
        self.bookmarks = bookmarks
        self.reminders = reminders
        self.matches = matches
        known = bookmarks.bookmarks
        enabled = settings.remindBookmarks
        bookmarks.bookmarksPublisher.sink { [weak self] in self?.bookmarksChanged($0) }.store(in: &subscriptions)
        settings.changes.sink { [weak self] in self?.settingsChanged() }.store(in: &subscriptions)
    }

    private func bookmarksChanged(_ ids: Set<MatchID>) {
        let added = ids.subtracting(known)
        known = ids
        if enabled { schedule(added) }
    }

    private func settingsChanged() {
        guard settings.remindBookmarks != enabled else { return }
        enabled = settings.remindBookmarks
        if enabled { schedule(known) } else { known.forEach(reminders.cancel) }
    }

    /// Прошедшие и начавшиеся матчи хранилище само отвергает (`tooLate`).
    private func schedule(_ ids: Set<MatchID>) {
        guard !ids.isEmpty else { return }
        let (matches, reminders) = (matches, reminders)
        Task {
            for id in ids {
                guard let match = try? await matches.match(id: id), match.status == .scheduled else { continue }
                _ = try? await reminders.schedule(match)
            }
        }
    }
}
#endif
