import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle(for: RSSBundleToken.self).url(forResource: name, withExtension: "xml"))
    return try Data(contentsOf: url)
}

private func feed(_ items: String) -> Data {
    Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel><title>Канал</title><link>https://example.com</link>
    <image><url>https://example.com/c.jpg</url><title>Картинка канала</title></image>
    \(items)
    </channel></rss>
    """.utf8)
}

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

struct RSSParserTests {
    @Test func parsesPodsterFeed() throws {
        let episodes = try RSSParser.episodes(from: fixture("feed_podster"), podcastID: "skvoz-sport")
        #expect(episodes.count == 10)
        let first = try #require(episodes.first)
        #expect(first.id == EpisodeID(podcastID: "skvoz-sport", guid: "a342cb6f-6b7d-4dd5-b605-7692e1cbdb7f"))
        #expect(first.podcastID == "skvoz-sport")
        #expect(first.title == "18 - ноября: Медведев, Евро, «Майами», ЦСКА, Пиастри")
        #expect(first.publishedAt == date("2026-11-19T07:19:22Z"))
        #expect(first.duration == 725)
        #expect(first.audioURL.absoluteString == "https://podster.fm/episodes/a342cb6f-6b7d-4dd5-b605-7692e1cbdb7f/audio.mp3?media=rss")
        #expect(first.artworkURL?.absoluteString == "https://podster.fm/image-storage/762020/f1A3St7ZYkJxuXs3.png")
        #expect(first.link?.absoluteString == "https://skvozsport.podster.fm/e/548050/18-noyabrya-medvedev-evro-mayami-tsska-piastri")
    }

    @Test func parsesMaveFeed() throws {
        let episodes = try RSSParser.episodes(from: fixture("feed_mave"), podcastID: "gentlemen")
        #expect(episodes.count == 10)
        let first = try #require(episodes.first)
        #expect(first.title == "Россию нагло убрали с чемпионата мира по хоккею. Можно ли с этим бороться?")
        #expect(first.publishedAt == date("2026-11-17T19:44:45Z"))
        #expect(first.duration == 2580)
        #expect(episodes.last?.id.rawValue == "gentlemen:654b3109-c5db-456e-bd15-e8510e3dd986")
    }

    @Test func sortsNewestFirst() throws {
        // В ленте rss.com выпуски идут не по дате: второй новее первого.
        let episodes = try RSSParser.episodes(from: fixture("feed_rsscom"), podcastID: "hob")
        #expect(episodes.count == 10)
        #expect(episodes.first?.id.rawValue == "hob:24858a5f-1b1c-4070-83cd-6b82e2165252")
        #expect(episodes.map(\.publishedAt) == episodes.map(\.publishedAt).sorted(by: >))
    }

    @Test(arguments: [
        ("1234", 1234.0), ("12:34", 754.0), ("1:02:03", 3723.0), ("01:02:03", 3723.0), (" 95 ", 95.0), ("1234.5", 1234.5),
    ])
    func parsesDuration(text: String, seconds: TimeInterval) {
        #expect(RSSParser.duration(text) == seconds)
    }

    @Test(arguments: ["", "abc", "1:2:3:4", "-5", "12:xx"])
    func rejectsBrokenDuration(text: String) {
        #expect(RSSParser.duration(text) == nil)
    }

    @Test func usesEnclosureURLWithoutGuid() throws {
        let episodes = try RSSParser.episodes(from: feed("""
        <item><title>Без guid</title><pubDate>Wed, 4 Nov 2026 18:16:25 +0000</pubDate>
        <enclosure url="https://example.com/a.mp3" type="audio/mpeg" length="1"/></item>
        """), podcastID: "p")
        #expect(episodes.map(\.id.rawValue) == ["p:https://example.com/a.mp3"])
        #expect(episodes.first?.duration == nil)
        #expect(episodes.first?.artworkURL == nil)
        #expect(episodes.first?.link == nil)
    }

    @Test func dropsItemsWithoutHTTPSAudioOrDate() throws {
        let episodes = try RSSParser.episodes(from: feed("""
        <item><guid>ok</guid><title>Годный</title><pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate>
        <enclosure url="https://example.com/ok.mp3" type="audio/mpeg"/></item>
        <item><guid>http</guid><title>По http</title><pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate>
        <enclosure url="http://example.com/a.mp3" type="audio/mpeg"/></item>
        <item><guid>video</guid><title>Видео</title><pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate>
        <enclosure url="https://example.com/a.mp4" type="video/mp4"/></item>
        <item><guid>none</guid><title>Без аудио</title><pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate></item>
        <item><guid>nodate</guid><title>Без даты</title><enclosure url="https://example.com/b.mp3" type="audio/mpeg"/></item>
        <item><guid>baddate</guid><title>Кривая дата</title><pubDate>вчера</pubDate><enclosure url="https://example.com/c.mp3"/></item>
        """), podcastID: "p")
        #expect(episodes.map(\.id.rawValue) == ["p:ok"])
    }

    @Test func decodesCDATAAndEntities() throws {
        let episodes = try RSSParser.episodes(from: feed("""
        <item><guid><![CDATA[g1]]></guid><title><![CDATA[«Спартак» &amp; &quot;ЦСКА&quot; &#8212; &#x41;&nbsp;Б]]></title>
        <pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/></item>
        <item><guid>g2</guid><title>Рок &amp; ролл &#171;футбол&#187;</title>
        <pubDate>Mon, 16 Nov 2026 19:44:45 GMT</pubDate><enclosure url="https://example.com/b.mp3" type="audio/mpeg"/></item>
        """), podcastID: "p")
        #expect(episodes.map(\.title) == ["«Спартак» & \"ЦСКА\" — A Б", "Рок & ролл «футбол»"])
    }

    @Test func ignoresHTTPArtworkAndChannelFields() throws {
        let episodes = try RSSParser.episodes(from: feed("""
        <item><guid>g</guid><title>  Выпуск  </title><link>https://example.com/ep</link>
        <itunes:image href="http://example.com/e.jpg"/><itunes:duration>1:00</itunes:duration>
        <pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/></item>
        """), podcastID: "p")
        let episode = try #require(episodes.first)
        #expect(episode.title == "Выпуск")
        #expect(episode.artworkURL == nil)
        #expect(episode.link?.absoluteString == "https://example.com/ep")
        #expect(episode.duration == 60)
    }

    @Test func keepsFirstOfDuplicateGuids() throws {
        let episodes = try RSSParser.episodes(from: feed("""
        <item><guid>g</guid><title>Первый</title><pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate><enclosure url="https://example.com/a.mp3"/></item>
        <item><guid>g</guid><title>Второй</title><pubDate>Tue, 17 Nov 2026 19:44:45 GMT</pubDate><enclosure url="https://example.com/b.mp3"/></item>
        """), podcastID: "p")
        #expect(episodes.map(\.title) == ["Первый"])
    }

    @Test func throwsOnBrokenXML() {
        #expect(throws: RSSParser.ParseError.self) {
            try RSSParser.episodes(from: Data("<html><body>502 Bad Gateway".utf8), podcastID: "p")
        }
    }
}

private final class RSSBundleToken {}
