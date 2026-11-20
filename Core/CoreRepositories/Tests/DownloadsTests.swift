import CoreDomain
import Foundation
import Testing
@testable import CoreRepositories

/// Фейковая фоновая сессия: считает созданные задачи, отдаёт заданные «живые» задачи при запуске.
private final class FakeTask: DownloadTaskHandle, @unchecked Sendable {
    let id: String
    let allowsCellularAccess: Bool
    var isCancelled = false

    init(id: String, allowsCellularAccess: Bool) {
        self.id = id
        self.allowsCellularAccess = allowsCellularAccess
    }

    func cancel() { isCancelled = true }
}

private final class FakeSession: DownloadSession, @unchecked Sendable {
    var created: [FakeTask] = []
    var running: [FakeTask] = []

    func start(url: URL, allowsCellularAccess: Bool, id: String) -> any DownloadTaskHandle {
        let task = FakeTask(id: id, allowsCellularAccess: allowsCellularAccess)
        created.append(task)
        return task
    }

    func allTasks(_ completion: @escaping @MainActor @Sendable ([(id: String, handle: any DownloadTaskHandle)]) -> Void) {
        let tasks = running.map { (id: $0.id, handle: $0 as any DownloadTaskHandle) }
        MainActor.assumeIsolated { completion(tasks) }
    }
}

@MainActor
struct DownloadsTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadsTests-\(UUID().uuidString)")
    let suite = "DownloadsTests.\(UUID().uuidString)"
    let podcast = Podcast(id: "p", title: "Подкаст", author: "Автор", feedURL: URL(string: "https://example.com/feed.xml")!,
                          artworkURL: URL(string: "https://example.com/p.jpg")!, featuredOrder: nil)

    func episode(_ guid: String, audio: String = "https://example.com/a.mp3") -> Episode {
        Episode(id: EpisodeID(podcastID: "p", guid: guid), podcastID: "p", title: guid, publishedAt: Date(timeIntervalSince1970: 0),
                duration: 60, audioURL: URL(string: audio)!, artworkURL: nil, link: nil)
    }

    func make(_ session: any DownloadSession, defaults: UserDefaults) -> BackgroundEpisodeDownloads {
        BackgroundEpisodeDownloads(directory: directory, defaults: defaults, fetchArtwork: { _ in throw URLError(.notConnectedToInternet) },
                                   makeSession: { _ in session })
    }

    func tempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(count: bytes).write(to: url)
        return url
    }

    func cleanUp(_ defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func finishMovesFileAndPersists() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let downloads = make(FakeSession(), defaults: defaults)
        let episode = episode("e1")
        downloads.download(episode, podcast: podcast)
        let temp = try tempFile(bytes: 1234)

        downloads.handleFinished(id: episode.id.rawValue, tempFile: temp, mimeType: "audio/mpeg")

        #expect(!FileManager.default.fileExists(atPath: temp.path))
        let file = try #require(downloads.localFile(for: episode.id))
        #expect(file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(file.pathExtension == "mp3")
        #expect(downloads.item(episode.id)?.state == .downloaded(bytes: 1234))
        let entries = DownloadsIndex(directory: directory).load()
        #expect(entries.map(\.item.id) == [episode.id])
        #expect(entries.first?.item.state == .downloaded(bytes: 1234))
    }

    @Test func restoresFromIndexAfterRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let first = FakeSession()
        let downloads = make(first, defaults: defaults)
        let done = episode("done"), running = episode("running"), orphan = episode("orphan")
        downloads.download(done, podcast: podcast)
        downloads.download(running, podcast: podcast)
        downloads.download(orphan, podcast: podcast)
        downloads.handleFinished(id: done.id.rawValue, tempFile: try tempFile(bytes: 10), mimeType: nil)
        downloads.handleProgress(id: running.id.rawValue, written: 50, expected: 100)

        let second = FakeSession()
        second.running = [FakeTask(id: running.id.rawValue, allowsCellularAccess: false)]
        let relaunched = make(second, defaults: defaults)

        #expect(relaunched.item(done.id)?.state == .downloaded(bytes: 10))
        #expect(relaunched.localFile(for: done.id) != nil)
        #expect(relaunched.item(running.id)?.state == .downloading(progress: 0.5))
        #expect(relaunched.item(orphan.id)?.state == .failed)
        #expect(relaunched.items.count == 3)
    }

    @Test func reconcileDropsMissingFiles() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let downloads = make(FakeSession(), defaults: defaults)
        let episode = episode("e1")
        downloads.download(episode, podcast: podcast)
        downloads.handleFinished(id: episode.id.rawValue, tempFile: try tempFile(bytes: 10), mimeType: nil)
        try FileManager.default.removeItem(at: try #require(downloads.localFile(for: episode.id)))

        #expect(DownloadsIndex(directory: directory).load().isEmpty)
        #expect(make(FakeSession(), defaults: defaults).items.isEmpty)
    }

    private func writeIndex(_ json: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("index.json"))
    }

    @Test func loadRepairsStoredArtworkPath() throws {
        let item = DownloadedEpisode(episode: episode("a"), podcast: podcast, addedAt: Date(timeIntervalSince1970: 0), state: .failed,
                                     artworkFile: URL(string: "file:///old/container/x.artwork"))
        let index = DownloadsIndex(directory: directory)
        index.save([.init(item: item, fileName: nil)])
        #expect(index.load().first?.item.artworkFile == nil)

        let real = index.artworkFile(item.id)
        try Data(count: 1).write(to: real)
        #expect(index.load().first?.item.artworkFile?.standardizedFileURL == real.standardizedFileURL)
    }

    @Test func loadSkipsBadEntryAndRemovesOrphans() throws {
        let index = DownloadsIndex(directory: directory)
        let good = DownloadedEpisode(episode: episode("good"), podcast: podcast, addedAt: Date(timeIntervalSince1970: 0), state: .failed, artworkFile: nil)
        index.save([.init(item: good, fileName: nil)])
        let goodJSON = try String(decoding: Data(contentsOf: directory.appendingPathComponent("index.json")), as: UTF8.self)
        // Добавляем битую запись перед хорошей: `[bad, good]`.
        try writeIndex("[{\"item\":42}," + goodJSON.dropFirst())
        let orphan = directory.appendingPathComponent("orphan.mp3")
        try Data(count: 5).write(to: orphan)
        let artwork = index.artworkFile(good.id)
        try Data(count: 1).write(to: artwork)

        let entries = index.load()

        #expect(entries.map(\.item.id) == [good.id])
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: artwork.path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
    }

    @Test func unreadableIndexKeepsFiles() throws {
        try writeIndex("not json")
        let file = directory.appendingPathComponent("x.mp3")
        try Data(count: 5).write(to: file)

        #expect(DownloadsIndex(directory: directory).load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func downloadIsIdempotent() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let session = FakeSession()
        let downloads = make(session, defaults: defaults)
        let episode = episode("e1")

        downloads.download(episode, podcast: podcast)
        downloads.download(episode, podcast: podcast)
        #expect(downloads.items.count == 1)
        #expect(session.created.count == 1)

        downloads.handleFailure(id: episode.id.rawValue, cancelled: false)
        downloads.download(episode, podcast: podcast)
        #expect(downloads.items.count == 1)
        #expect(session.created.count == 2)
        #expect(downloads.item(episode.id)?.state == .waiting)
    }

    @Test func extensionFromURLThenMime() {
        func ext(_ url: String, _ mime: String?) -> String {
            BackgroundEpisodeDownloads.fileExtension(audioURL: URL(string: url)!, mimeType: mime)
        }
        #expect(ext("https://example.com/a.m4a?x=1", "audio/mpeg") == "m4a")
        #expect(ext("https://example.com/a", "audio/mpeg") == "mp3")
        #expect(ext("https://example.com/a", "audio/x-m4a") == "m4a")
        #expect(ext("https://example.com/a", "audio/mp4") == "m4a")
        #expect(ext("https://example.com/a.php", "text/html") == "mp3")
        #expect(ext("https://example.com/a", nil) == "mp3")
    }

    @Test func wifiOnlyDefaultsToTrueAndRestartsActiveTasks() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let session = FakeSession()
        let downloads = make(session, defaults: defaults)
        #expect(downloads.wifiOnly)
        let active = episode("active"), done = episode("done")
        downloads.download(active, podcast: podcast)
        downloads.download(done, podcast: podcast)
        downloads.handleFinished(id: done.id.rawValue, tempFile: try tempFile(bytes: 10), mimeType: nil)
        #expect(session.created.map(\.allowsCellularAccess) == [false, false])

        downloads.wifiOnly = false

        #expect(session.created[0].isCancelled)
        #expect(session.created.count == 3)
        #expect(session.created[2].id == active.id.rawValue)
        #expect(session.created[2].allowsCellularAccess)
        #expect(downloads.item(done.id)?.state == .downloaded(bytes: 10))
        #expect(downloads.item(active.id)?.state == .waiting)
        #expect(make(FakeSession(), defaults: defaults).wifiOnly == false)
    }

    @Test func removeAllDeletesFilesAndUsageIsZero() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let session = FakeSession()
        let downloads = make(session, defaults: defaults)
        let a = episode("a"), b = episode("b"), c = episode("c")
        for episode in [a, b, c] { downloads.download(episode, podcast: podcast) }
        downloads.handleFinished(id: a.id.rawValue, tempFile: try tempFile(bytes: 10), mimeType: nil)
        downloads.handleFinished(id: b.id.rawValue, tempFile: try tempFile(bytes: 20), mimeType: nil)
        #expect(downloads.usage() == (30, 2))
        let files = [a, b].compactMap { downloads.localFile(for: $0.id) }

        downloads.removeAll()

        #expect(downloads.items.isEmpty)
        #expect(downloads.usage() == (0, 0))
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(session.created[2].isCancelled)
        #expect(DownloadsIndex(directory: directory).load().isEmpty)
    }

    @Test func failureNotCancellationMarksFailed() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let downloads = make(FakeSession(), defaults: defaults)
        let episode = episode("e1")
        downloads.download(episode, podcast: podcast)

        downloads.handleFailure(id: episode.id.rawValue, cancelled: false)

        #expect(downloads.item(episode.id)?.state == .failed)
        #expect(downloads.localFile(for: episode.id) == nil)
        #expect(DownloadsIndex(directory: directory).load().first?.item.state == .failed)
    }

    @Test func cancellationRemovesEntry() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let session = FakeSession()
        let downloads = make(session, defaults: defaults)
        let first = episode("first"), second = episode("second")
        downloads.download(first, podcast: podcast)
        downloads.download(second, podcast: podcast)

        downloads.handleFailure(id: first.id.rawValue, cancelled: true)
        downloads.remove(second.id)

        #expect(downloads.items.isEmpty)
        #expect(session.created[1].isCancelled)
    }

    @Test func newestFirst() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let downloads = make(FakeSession(), defaults: defaults)
        downloads.download(episode("old"), podcast: podcast)
        downloads.download(episode("new"), podcast: podcast)

        #expect(downloads.items.map(\.episode.title) == ["new", "old"])
    }

    @Test func lateFinishAfterRestoreFailedIsAccepted() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let episode = episode("e1")
        make(FakeSession(), defaults: defaults).download(episode, podcast: podcast)
        let relaunched = make(FakeSession(), defaults: defaults)
        #expect(relaunched.item(episode.id)?.state == .failed)

        relaunched.handleFinished(id: episode.id.rawValue, tempFile: try tempFile(bytes: 10), mimeType: nil)

        #expect(relaunched.item(episode.id)?.state == .downloaded(bytes: 10))
        #expect(relaunched.localFile(for: episode.id) != nil)
    }

    @Test func restoreCancelsSystemTaskReplacedBeforeSync() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { cleanUp(defaults) }
        let episode = episode("e1")
        make(FakeSession(), defaults: defaults).download(episode, podcast: podcast)

        // Сверка позже смены Wi-Fi: сессия отдаёт задачи только по вызову `deliver`.
        let session = DeferredSession()
        let downloads = make(session, defaults: defaults)
        let stale = FakeTask(id: episode.id.rawValue, allowsCellularAccess: false)
        downloads.wifiOnly = false
        session.deliver([stale])

        #expect(stale.isCancelled)
        #expect(session.created.last?.allowsCellularAccess == true)
        #expect(downloads.item(episode.id)?.state == .waiting)
    }
}

private final class DeferredSession: DownloadSession, @unchecked Sendable {
    var created: [FakeTask] = []
    private var completion: (@MainActor @Sendable ([(id: String, handle: any DownloadTaskHandle)]) -> Void)?

    func start(url: URL, allowsCellularAccess: Bool, id: String) -> any DownloadTaskHandle {
        let task = FakeTask(id: id, allowsCellularAccess: allowsCellularAccess)
        created.append(task)
        return task
    }

    func allTasks(_ completion: @escaping @MainActor @Sendable ([(id: String, handle: any DownloadTaskHandle)]) -> Void) {
        self.completion = completion
    }

    @MainActor func deliver(_ tasks: [FakeTask]) {
        completion?(tasks.map { (id: $0.id, handle: $0 as any DownloadTaskHandle) })
    }
}
