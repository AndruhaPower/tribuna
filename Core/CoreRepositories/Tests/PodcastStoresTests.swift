import Combine
import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private func podcastDTO(_ id: String, title: String? = nil, featured: Int? = nil, enabled: Bool = true,
                        feed: String = "https://example.com/feed", artwork: String = "https://example.com/a.jpg") -> PodcastDTO {
    PodcastDTO(id: id, title: title ?? id, author: "Автор", feedURL: feed, artworkURL: artwork, featuredOrder: featured, enabled: enabled)
}

struct PodcastsMappingTests {
    @Test func decodesPostgRESTRow() throws {
        let json = """
        [{"id":"skvoz-sport","title":"Сквозь Спорт","author":"Алексей Бибиков","feed_url":"https://podster.fm/rss.xml?pid=100138",
          "artwork_url":"https://is1-ssl.mzstatic.com/a/600x600bb.jpg","featured_order":1,"enabled":true}]
        """
        let rows = try JSONDecoder().decode([PodcastDTO].self, from: Data(json.utf8))
        #expect(PodcastsMapping.podcasts(from: rows) == [
            Podcast(id: "skvoz-sport", title: "Сквозь Спорт", author: "Алексей Бибиков", feedURL: URL(string: "https://podster.fm/rss.xml?pid=100138")!,
                    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/a/600x600bb.jpg")!, featuredOrder: 1),
        ])
    }

    @Test func sortsByFeaturedThenTitle() {
        let result = PodcastsMapping.podcasts(from: [
            podcastDTO("c", title: "Яблоко"), podcastDTO("a", title: "Альфа"), podcastDTO("f2", title: "Б", featured: 2), podcastDTO("f1", title: "Я", featured: 1),
        ])
        #expect(result.map(\.id) == ["f1", "f2", "a", "c"])
    }

    @Test func dropsDisabledAndNonHTTPSRows() {
        let result = PodcastsMapping.podcasts(from: [
            podcastDTO("ok"), podcastDTO("off", enabled: false), podcastDTO("httpfeed", feed: "http://example.com/feed"),
            podcastDTO("httpart", artwork: "http://example.com/a.jpg"), podcastDTO("broken", feed: ""),
        ])
        #expect(result.map(\.id) == ["ok"])
    }
}

struct PodcastsCacheTests {
    struct Down: Error {}
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("podcasts-\(UUID().uuidString).json")
    let catalog = [Podcast(id: "a", title: "А", author: "Б", feedURL: URL(string: "https://example.com/f")!, artworkURL: URL(string: "https://example.com/a.jpg")!, featuredOrder: 1)]

    @Test func catalogWritesCacheOnSuccess() async throws {
        let list = catalog
        let repo = SupabasePodcastsRepository(cacheFile: file, fetch: { list })
        #expect(try await repo.podcasts() == catalog)
        let cached = try JSONDecoder().decode([Podcast].self, from: Data(contentsOf: file))
        #expect(cached == catalog)
    }

    @Test func catalogFallsBackToCacheOnFailure() async throws {
        try JSONEncoder().encode(catalog).write(to: file)
        let repo = SupabasePodcastsRepository(cacheFile: file, fetch: { throw Down() })
        #expect(try await repo.podcasts() == catalog)
    }

    @Test func catalogThrowsWithoutCache() async {
        let repo = SupabasePodcastsRepository(cacheFile: file, fetch: { throw Down() })
        await #expect(throws: Down.self) { try await repo.podcasts() }
    }
}
