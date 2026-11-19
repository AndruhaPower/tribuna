import Combine
import CoreDomain
import Foundation
import Testing
@testable import CoreServices

@MainActor
struct BookmarksStoreTests {
    let suite = "BookmarksStoreTests.\(UUID().uuidString)"
    let id = MatchID(sport: .football, sourceID: "555081")

    @Test func toggleAddsAndRemoves() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsBookmarksStore(defaults: defaults)

        store.toggle(id)
        #expect(store.bookmarks == [id])
        store.toggle(id)
        #expect(store.bookmarks.isEmpty)
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        UserDefaultsBookmarksStore(defaults: defaults).toggle(id)

        #expect(UserDefaultsBookmarksStore(defaults: defaults).bookmarks == [id])
        #expect(defaults.stringArray(forKey: "bookmarks.v1") == ["football:555081"])
    }

    @Test func publisherSendsNewSet() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsBookmarksStore(defaults: defaults)
        var received: [Set<MatchID>] = []
        let cancellable = store.bookmarksPublisher.sink { received.append($0) }

        store.toggle(id)
        cancellable.cancel()
        #expect(received == [[], [id]])
    }
}
