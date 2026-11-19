import CoreDomain
import UIKit

public enum FeatureMatch {
    public struct Dependencies {
        let matches: MatchesRepository
        let standings: StandingsRepository
        let bookmarks: BookmarksStore
        let reminders: RemindersStore

        public init(matches: MatchesRepository, standings: StandingsRepository, bookmarks: BookmarksStore, reminders: RemindersStore) {
            self.matches = matches
            self.standings = standings
            self.bookmarks = bookmarks
            self.reminders = reminders
        }
    }

    public struct Output {
        /// Уведомления запрещены — открыть настройки приложения.
        let openSettings: () -> Void

        public init(openSettings: @escaping () -> Void) {
            self.openSettings = openSettings
        }
    }

    @MainActor public static func make(dependencies: Dependencies, output: Output, matchID: MatchID) -> UIViewController {
        MatchViewController(
            viewModel: MatchViewModel(
                matchID: matchID,
                matches: dependencies.matches,
                standings: dependencies.standings,
                bookmarks: dependencies.bookmarks,
                reminders: dependencies.reminders
            ),
            output: output
        )
    }
}
