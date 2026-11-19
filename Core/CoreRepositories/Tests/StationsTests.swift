import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private func dto(_ id: String, name: String? = nil, genres: [String] = ["news"], featured: Int? = nil, enabled: Bool = true, url: String = "https://example.com/s") -> StationDTO {
    StationDTO(id: id, name: name ?? id, streamURL: url, country: "Россия", bitrate: 128, genres: genres, subtitle: "Новости", featuredOrder: featured, enabled: enabled)
}

struct StationsTests {
    @Test func parsesFixture() throws {
        // Ответ PostgREST для таблицы stations: порядок и disabled-станция приходят «как есть».
        let url = try #require(Bundle(for: StationsBundleToken.self).url(forResource: "stations", withExtension: "json"))
        let rows = try JSONDecoder().decode([StationDTO].self, from: Data(contentsOf: url))
        let stations = StationsMapping.stations(from: rows)
        #expect(stations.map(\.id) == ["bbc-5live", "vesti-fm", "mayak", "kommersant-fm"])
        let first = try #require(stations.first)
        #expect(first.name == "BBC Radio 5 Live")
        #expect(first.genres == [.sport, .football, .news])
        #expect(first.bitrate == nil)
        #expect(first.featuredOrder == 1)
        #expect(first.streamURL.absoluteString.hasSuffix(".m3u8"))
    }

    @Test func sortsByFeaturedThenName() {
        let result = StationsMapping.stations(from: [
            dto("c", name: "Яблоко"), dto("a", name: "Альфа"), dto("f2", name: "Б", featured: 2), dto("f1", name: "Я", featured: 1),
        ])
        #expect(result.map(\.id) == ["f1", "f2", "a", "c"])
    }

    @Test func dropsDisabledAndBrokenRows() {
        let result = StationsMapping.stations(from: [
            dto("ok"), dto("off", enabled: false), dto("badurl", url: ""),
        ])
        #expect(result.map(\.id) == ["ok"])
    }

    @Test func ignoresUnknownGenres() {
        let result = StationsMapping.stations(from: [dto("x", genres: ["hockey", "jazz"])])
        #expect(result.first?.genres == [.hockey])
    }
}

private final class StationsBundleToken {}
