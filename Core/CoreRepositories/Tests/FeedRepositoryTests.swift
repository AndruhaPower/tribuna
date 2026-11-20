import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

/// Изменяемое значение для `@Sendable`-замыканий в тестах.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private struct Offline: Error {}

private func item(_ guid: String, day: Int) -> String {
    """
    <item><guid>\(guid)</guid><title>Выпуск \(guid)</title><pubDate>\(day) Nov 2026 10:00:00 +0000</pubDate>
    <enclosure url="https://example.com/\(guid).mp3" type="audio/mpeg"/></item>
    """
}

private func feed(_ items: String...) -> Data {
    Data("<rss><channel><title>К</title>\(items.joined())</channel></rss>".utf8)
}

struct FeedRepositoryTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FeedRepositoryTests-\(UUID().uuidString)")
    let podcast = Podcast(id: "p1", title: "П", author: "А", feedURL: URL(string: "https://example.com/feed")!,
                          artworkURL: URL(string: "https://example.com/a.jpg")!, featuredOrder: 1)
    let now = Box(Date(timeIntervalSince1970: 1_800_000_000))
    let response = Box<Result<Data, Error>>(.success(feed(item("a", day: 1))))
    let requests = Box<[URL]>([])

    func repository() -> FeedRepository {
        let (now, response, requests) = (now, response, requests)
        return FeedRepository(directory: directory, fetch: { url in
            requests.value.append(url)
            return try response.value.get()
        }, now: { now.value })
    }

    @Test func cachesForThirtyMinutes() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = repository()
        #expect(try await repo.episodes(for: podcast, forceRefresh: false).map(\.id.rawValue) == ["p1:a"])
        #expect(requests.value == [podcast.feedURL])

        response.value = .success(feed(item("a", day: 1), item("b", day: 2)))
        now.value += 29 * 60
        #expect(try await repo.episodes(for: podcast, forceRefresh: false).map(\.id.rawValue) == ["p1:a"])
        #expect(requests.value.count == 1)

        now.value += 60
        #expect(try await repo.episodes(for: podcast, forceRefresh: false).map(\.id.rawValue) == ["p1:b", "p1:a"])
        #expect(requests.value.count == 2)
    }

    @Test func forceRefreshSkipsThrottle() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = repository()
        _ = try await repo.episodes(for: podcast, forceRefresh: false)
        response.value = .success(feed(item("b", day: 2)))
        #expect(try await repo.episodes(for: podcast, forceRefresh: true).map(\.id.rawValue) == ["p1:b"])
        #expect(requests.value.count == 2)
    }

    @Test func cacheSurvivesRelaunch() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await repository().episodes(for: podcast, forceRefresh: false)
        response.value = .failure(Offline())
        #expect(try await repository().episodes(for: podcast, forceRefresh: false) == first)
        #expect(requests.value.count == 1)
    }

    @Test func fallsBackToCacheOnFailure() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = repository()
        let cached = try await repo.episodes(for: podcast, forceRefresh: false)

        response.value = .failure(Offline())
        #expect(try await repo.episodes(for: podcast, forceRefresh: true) == cached)

        // Вместо ленты пришла страница ошибки — тоже сбой.
        now.value += 3600
        response.value = .success(Data("<html>502".utf8))
        #expect(try await repo.episodes(for: podcast, forceRefresh: false) == cached)
    }

    @Test func failedRefreshRetriesNextTime() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = repository()
        _ = try await repo.episodes(for: podcast, forceRefresh: false)
        now.value += 3600
        response.value = .failure(Offline())
        _ = try await repo.episodes(for: podcast, forceRefresh: false)
        response.value = .success(feed(item("b", day: 2)))
        #expect(try await repo.episodes(for: podcast, forceRefresh: false).map(\.id.rawValue) == ["p1:b"])
        #expect(requests.value.count == 3)
    }

    @Test func throwsWithoutCache() async {
        defer { try? FileManager.default.removeItem(at: directory) }
        response.value = .failure(Offline())
        await #expect(throws: Offline.self) { try await repository().episodes(for: podcast, forceRefresh: false) }
    }

    @Test func ignoresCacheOfOtherFeedURL() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = repository()
        _ = try await repo.episodes(for: podcast, forceRefresh: false)
        let moved = Podcast(id: podcast.id, title: podcast.title, author: podcast.author, feedURL: URL(string: "https://example.com/new")!,
                            artworkURL: podcast.artworkURL, featuredOrder: 1)
        response.value = .success(feed(item("n", day: 3)))
        #expect(try await repo.episodes(for: moved, forceRefresh: false).map(\.id.rawValue) == ["p1:n"])
        #expect(requests.value.last == moved.feedURL)
    }
}
