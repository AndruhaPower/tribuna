import CoreDomain
import UIKit

public enum FeatureToday {
    public struct Dependencies {
        let matches: MatchesRepository
        let bookmarks: BookmarksStore

        public init(matches: MatchesRepository, bookmarks: BookmarksStore) {
            self.matches = matches
            self.bookmarks = bookmarks
        }
    }

    public struct Output {
        let openMatch: (MatchID) -> Void

        public init(openMatch: @escaping (MatchID) -> Void) {
            self.openMatch = openMatch
        }
    }

    @MainActor public static func make(dependencies: Dependencies, output: Output) -> UIViewController {
        TodayViewController(viewModel: TodayViewModel(
            matches: dependencies.matches,
            bookmarks: dependencies.bookmarks,
            onOpenMatch: output.openMatch
        ))
    }
}
