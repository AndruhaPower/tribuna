import CoreDomain
import Foundation

/// Разбор RSS-ленты подкаста в выпуски (XMLParser, без зависимостей).
enum RSSParser {
    struct ParseError: Error {
        let underlying: Error?
    }

    /// Выпуски, новые первыми. Отбрасываются элементы без https-аудио (ATS) и без читаемой даты:
    /// без даты выпуск не встанет в список по времени и не посчитается «новым».
    static func episodes(from data: Data, podcastID: String) throws -> [Episode] {
        let parser = XMLParser(data: numericEntities(data))
        let collector = ItemCollector()
        parser.delegate = collector
        guard parser.parse() else { throw ParseError(underlying: parser.parserError) }

        let dates = DateParser()
        var seen = Set<EpisodeID>()
        return collector.items.compactMap { item -> Episode? in
            guard let audio = item.enclosureURL.flatMap(httpsURL),
                  item.enclosureType.map({ $0.isEmpty || $0.hasPrefix("audio/") }) ?? true,
                  let publishedAt = item.fields["pubDate"].flatMap(dates.date) else { return nil }
            let guid = item.fields["guid"].flatMap { $0.isEmpty ? nil : $0 } ?? audio.absoluteString
            let id = EpisodeID(podcastID: podcastID, guid: guid)
            guard seen.insert(id).inserted else { return nil }
            return Episode(
                id: id, podcastID: podcastID, title: decodeEntities(item.fields["title"] ?? ""), publishedAt: publishedAt,
                duration: item.fields["itunes:duration"].flatMap(duration), audioURL: audio,
                artworkURL: item.imageURL.flatMap(httpsURL), link: item.fields["link"].flatMap { URL(string: $0) }
            )
        }
        .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// `itunes:duration`: секунды («1234», «1234.5»), «мм:сс» или «чч:мм:сс».
    static func duration(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total: TimeInterval = 0
        for part in parts {
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }

    private static func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    private static let xmlBuiltins: Set<String> = ["amp", "lt", "gt", "quot", "apos"]
    private static let named = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ", "laquo": "«", "raquo": "»",
                                "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
                                "bdquo": "„", "bull": "•", "middot": "·", "copy": "©", "reg": "®", "trade": "™", "times": "×", "deg": "°"]
    private static let namedEntity = try! NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]{1,31});")

    /// Именованные HTML-сущности вне XML (`&nbsp;`) роняют XMLParser на всей ленте: заменяем их числовыми,
    /// неизвестные — пробелом. Пять встроенных XML-сущностей не трогаем. Не UTF-8 — оставляем как есть.
    static func numericEntities(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), text.contains("&") else { return data }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in namedEntity.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1))
            guard !xmlBuiltins.contains(name) else { continue }
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            result += named[name].map { $0.unicodeScalars.map { "&#\($0.value);" }.joined() } ?? " "
            last = match.range.location + match.range.length
        }
        guard last > 0 else { return data }
        return Data((result + source.substring(from: last)).utf8)
    }

    /// HTML-сущности, которые XMLParser не раскрывает: внутри CDATA и двойное экранирование.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let tail = rest[rest.index(after: amp)...]
            if let semi = tail.prefix(10).firstIndex(of: ";") {
                let name = tail[..<semi]
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = named[String(name)]
                }
                if let decoded {
                    result += decoded
                    rest = tail[tail.index(after: semi)...]
                    continue
                }
            }
            result += "&"
            rest = tail
        }
        return result + rest
    }
}

/// Поля одного `<item>`; берутся только прямые дети элемента.
private struct RawItem {
    var fields: [String: String] = [:]
    var enclosureURL: String?
    var enclosureType: String?
    var imageURL: String?
}

private final class ItemCollector: NSObject, XMLParserDelegate {
    private(set) var items: [RawItem] = []
    private var current: RawItem?
    /// Глубина вложенности внутри `<item>`: 1 — прямой ребёнок.
    private var depth = 0
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item", current == nil {
            current = RawItem()
            depth = 0
            return
        }
        guard current != nil else { return }
        depth += 1
        text = ""
        guard depth == 1 else { return }
        switch name {
        case "enclosure" where current?.enclosureURL == nil:
            current?.enclosureURL = attributes["url"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            current?.enclosureType = attributes["type"]?.lowercased()
        case "itunes:image":
            current?.imageURL = attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if current != nil { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if current != nil { text += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let item = current else { return }
        if depth == 0, name == "item" {
            items.append(item)
            current = nil
            return
        }
        if depth == 1, current?.fields[name] == nil {
            current?.fields[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        depth -= 1
        text = ""
    }
}

/// Даты RFC 822 в вариантах, что встречаются в лентах, и ISO 8601.
private struct DateParser {
    private let formatters: [DateFormatter] = ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z",
                                               "d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm Z"].map {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = $0
        return formatter
    }
    private let iso = ISO8601DateFormatter()

    func date(_ text: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: text) { return date }
        }
        return iso.date(from: text)
    }
}
