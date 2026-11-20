import CoreDomain
import CryptoKit
import Foundation

/// Индекс загрузок — `index.json` в папке загрузок, рядом с файлами. Порядок записей — новые первыми.
/// Пути хранятся именами файлов: абсолютный путь к контейнеру приложения меняется при обновлении.
struct DownloadsIndex {
    struct Entry: Codable, Equatable {
        var item: DownloadedEpisode
        /// Имя аудиофайла в папке; nil — ещё не скачан.
        var fileName: String?
    }

    let directory: URL

    private var indexFile: URL { directory.appendingPathComponent("index.json") }

    /// Имя файла без расширения: SHA256 от `EpisodeID` — в guid бывают `/` и любые символы.
    static func baseName(_ id: EpisodeID) -> String {
        SHA256.hash(data: Data(id.rawValue.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func artworkFile(_ id: EpisodeID) -> URL { directory.appendingPathComponent(Self.baseName(id) + ".artwork") }

    /// Сверка с диском: у скачанной записи нет файла — записи нет; обложка — только если файл на месте.
    func load() -> [Entry] {
        let entries = (try? Data(contentsOf: indexFile)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        return entries.compactMap { entry in
            var entry = entry
            if case .downloaded = entry.item.state {
                guard let name = entry.fileName, FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) else { return nil }
            }
            let artwork = artworkFile(entry.item.id)
            entry.item.artworkFile = FileManager.default.fileExists(atPath: artwork.path) ? artwork : nil
            return entry
        }
    }

    func save(_ entries: [Entry]) {
        prepareDirectory()
        try? JSONEncoder().encode(entries).write(to: indexFile, options: .atomic)
    }

    /// Папка без резервной копии iCloud: выпуски можно скачать заново.
    func prepareDirectory() {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }
}
