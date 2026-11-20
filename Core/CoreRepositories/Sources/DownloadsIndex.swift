import CoreDomain
import CryptoKit
import Foundation
import os

/// Индекс загрузок — `index.json` в папке загрузок, рядом с файлами. Порядок записей — новые первыми.
/// Аудио хранится именем файла; обложку `load()` пересобирает из папки: абсолютный путь контейнера меняется при обновлении.
struct DownloadsIndex {
    struct Entry: Codable, Equatable {
        var item: DownloadedEpisode
        /// Имя аудиофайла в папке; nil — ещё не скачан.
        var fileName: String?
    }

    private static let logger = Logger(subsystem: "com.tribuna.app", category: "downloads")

    let directory: URL

    private var indexFile: URL { directory.appendingPathComponent("index.json") }

    /// Имя файла без расширения: SHA256 от `EpisodeID` — в guid бывают `/` и любые символы.
    static func baseName(_ id: EpisodeID) -> String {
        SHA256.hash(data: Data(id.rawValue.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func artworkFile(_ id: EpisodeID) -> URL { directory.appendingPathComponent(Self.baseName(id) + ".artwork") }

    /// Запись, которую не удалось разобрать, — nil: одна битая не должна ронять весь индекс.
    private struct Lossy: Decodable {
        let entry: Entry?
        init(from decoder: Decoder) { entry = try? Entry(from: decoder) }
    }

    /// Сверка с диском: у скачанной записи нет файла — записи нет; обложка — только если файл на месте (путь в JSON
    /// не берём, собираем заново). Файлы папки, на которые не ссылается ни одна запись, удаляются.
    func load() -> [Entry] {
        let decoded = (try? Data(contentsOf: indexFile)).flatMap { try? JSONDecoder().decode([Lossy].self, from: $0) } ?? []
        let entries: [Entry] = decoded.compactMap(\.entry).compactMap { entry in
            var entry = entry
            if case .downloaded = entry.item.state {
                guard let name = entry.fileName, FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) else { return nil }
            }
            let artwork = artworkFile(entry.item.id)
            entry.item.artworkFile = FileManager.default.fileExists(atPath: artwork.path) ? artwork : nil
            return entry
        }
        removeOrphans(keeping: entries)
        return entries
    }

    private func removeOrphans(keeping entries: [Entry]) {
        let keep = Set(entries.flatMap { [$0.fileName, Self.baseName($0.item.id) + ".artwork"] }.compactMap { $0 } + ["index.json"])
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func save(_ entries: [Entry]) {
        prepareDirectory()
        do {
            try JSONEncoder().encode(entries).write(to: indexFile, options: .atomic)
        } catch {
            Self.logger.error("Не записан индекс загрузок: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Папка без резервной копии iCloud: выпуски можно скачать заново.
    func prepareDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }
}
