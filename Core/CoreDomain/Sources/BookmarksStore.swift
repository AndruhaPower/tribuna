import Combine

@MainActor
public protocol BookmarksStore: AnyObject {
    var bookmarks: Set<MatchID> { get }
    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { get }
    func toggle(_ id: MatchID)
}
