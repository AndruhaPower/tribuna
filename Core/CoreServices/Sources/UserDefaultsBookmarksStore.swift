import Combine
import CoreDomain
import Foundation

/// Закладки локально: массив `MatchID.rawValue` в UserDefaults.
@MainActor
final class UserDefaultsBookmarksStore: BookmarksStore {
    static let key = "bookmarks.v1"

    private let defaults: UserDefaults
    private let subject: CurrentValueSubject<Set<MatchID>, Never>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        subject = CurrentValueSubject(Set(stored.map(MatchID.init(rawValue:))))
    }

    var bookmarks: Set<MatchID> { subject.value }

    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { subject.eraseToAnyPublisher() }

    func toggle(_ id: MatchID) {
        var bookmarks = subject.value
        if bookmarks.remove(id) == nil { bookmarks.insert(id) }
        defaults.set(bookmarks.map(\.rawValue).sorted(), forKey: Self.key)
        subject.send(bookmarks)
    }
}
