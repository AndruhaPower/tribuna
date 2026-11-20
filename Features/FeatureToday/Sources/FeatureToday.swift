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
        /// Ворота (D31): вошёл — сразу действие, иначе лист входа и действие после входа.
        let requireSignIn: (SignInReason, @escaping @MainActor () -> Void) -> Void

        public init(openMatch: @escaping (MatchID) -> Void, requireSignIn: @escaping (SignInReason, @escaping @MainActor () -> Void) -> Void) {
            self.openMatch = openMatch
            self.requireSignIn = requireSignIn
        }
    }

    @MainActor public static func make(dependencies: Dependencies, output: Output) -> UIViewController {
        TodayViewController(viewModel: TodayViewModel(
            matches: dependencies.matches,
            bookmarks: dependencies.bookmarks,
            onOpenMatch: output.openMatch,
            requireSignIn: output.requireSignIn
        ))
    }
}
