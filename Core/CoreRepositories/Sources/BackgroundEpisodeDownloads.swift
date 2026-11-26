import Combine
import CoreDomain
import Foundation

/// Задача загрузки; в приложении — `URLSessionTask`, в тестах — фейк.
protocol DownloadTaskHandle: AnyObject, Sendable {
    func cancel()
}

extension URLSessionTask: DownloadTaskHandle {}

/// Фоновая сессия за протоколом — чтобы проверять логику без настоящей сессии.
protocol DownloadSession: AnyObject {
    /// `id` — `EpisodeID.rawValue`, попадает в `taskDescription` и переживает перезапуск.
    func start(url: URL, allowsCellularAccess: Bool, id: String) -> any DownloadTaskHandle
    /// Задачи, которые сессия ещё ведёт (после перезапуска приложения).
    func allTasks(_ completion: @escaping @MainActor @Sendable ([(id: String, handle: any DownloadTaskHandle)]) -> Void)
}

extension URLSession: DownloadSession {
    func start(url: URL, allowsCellularAccess: Bool, id: String) -> any DownloadTaskHandle {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowsCellularAccess
        let task = downloadTask(with: request)
        task.taskDescription = id
        task.resume()
        return task
    }

    func allTasks(_ completion: @escaping @MainActor @Sendable ([(id: String, handle: any DownloadTaskHandle)]) -> Void) {
        getAllTasks { tasks in
            let running = tasks.compactMap { task in task.taskDescription.map { (id: $0, handle: task as any DownloadTaskHandle) } }
            Task { @MainActor in completion(running) }
        }
    }
}

/// Загрузки выпусков фоновой сессией `com.tribuna.app.downloads`: файлы и индекс в `Application Support/Downloads`.
/// Делегат сессии — на главной очереди: события сразу меняют состояние, временный файл переносится, пока жив.
/// iCloud KVS (D38): настройки, которые без входа переезжают на другие iPhone с тем же Apple ID. В тестах — словарь.
protocol CloudSettings: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension NSUbiquitousKeyValueStore: CloudSettings {}

@MainActor
public final class BackgroundEpisodeDownloads: NSObject, EpisodeDownloads {
    static let sessionIdentifier = "com.tribuna.app.downloads"
    static let wifiOnlyKey = "podcasts.downloads.wifiOnly"
    /// Прогресс в состоянии — не чаще 2 раз в секунду.
    static let progressInterval: TimeInterval = 0.5

    private let index: DownloadsIndex
    private let defaults: UserDefaults
    private let cloud: CloudSettings?
    private var cloudObserver: (any NSObjectProtocol)?
    private let fetchArtwork: @Sendable (URL) async throws -> Data
    private var session: (any DownloadSession)!
    private let subject: CurrentValueSubject<[DownloadedEpisode], Never>
    private var entries: [DownloadsIndex.Entry] {
        didSet { subject.send(entries.map(\.item)) }
    }
    /// Текущая задача выпуска; события старых задач (отменённых при удалении или смене Wi-Fi) отбрасываются.
    private var tasks: [String: any DownloadTaskHandle] = [:]
    private var progressPublishedAt: [String: Date] = [:]
    private var backgroundEventsCompletion: (() -> Void)?

    /// Одна на приложение: вторая сессия с тем же идентификатором не получит событий.
    public static func make(defaults: UserDefaults = .standard) -> BackgroundEpisodeDownloads {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()
        let downloads = BackgroundEpisodeDownloads(
            directory: support.appendingPathComponent("Downloads"), defaults: defaults, cloud: cloud,
            fetchArtwork: FeedRepository.fetch(session: .shared)
        ) { delegate in
            let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
            configuration.sessionSendsLaunchEvents = true
            return URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
        }
        // Правило поменяли на другом iPhone — применяем здесь (без iCloud-entitlement уведомлений просто нет, D35).
        downloads.cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak downloads] _ in MainActor.assumeIsolated { downloads?.applyCloudSettings() } }
        return downloads
    }

    init(directory: URL, defaults: UserDefaults, cloud: CloudSettings? = nil, fetchArtwork: @escaping @Sendable (URL) async throws -> Data,
         makeSession: (BackgroundEpisodeDownloads) -> any DownloadSession) {
        index = DownloadsIndex(directory: directory)
        self.defaults = defaults
        self.cloud = cloud
        self.fetchArtwork = fetchArtwork
        entries = index.load()
        subject = CurrentValueSubject(entries.map(\.item))
        super.init()
        session = makeSession(self)
        session.allTasks { [weak self] running in self?.restore(running) }
        // Обложка могла не успеть скачаться, если приложение выгрузили сразу после аудио.
        for entry in entries where entry.item.artworkFile == nil && entry.item.state.isDownloaded { loadArtwork(for: entry.item) }
        applyCloudSettings()
    }

    /// «Только по Wi-Fi» из iCloud KVS, если его уже выбирали на каком-то устройстве.
    func applyCloudSettings() {
        if let value = cloud?.object(forKey: Self.wifiOnlyKey) as? Bool { wifiOnly = value }
    }

    public var items: [DownloadedEpisode] { subject.value }

    public var itemsPublisher: AnyPublisher<[DownloadedEpisode], Never> { subject.eraseToAnyPublisher() }

    public var wifiOnly: Bool {
        get { defaults.object(forKey: Self.wifiOnlyKey) as? Bool ?? true }
        set {
            guard newValue != wifiOnly else { return }
            defaults.set(newValue, forKey: Self.wifiOnlyKey)
            cloud?.set(newValue, forKey: Self.wifiOnlyKey)
            // Resume data хранит старый запрос с прежним правилом — идущие загрузки начинаем заново.
            // shortcut: докачка с места при смене правила не сделана; делать, если будут жалобы.
            var updated = entries
            for i in updated.indices where updated[i].item.state.isActive {
                tasks[updated[i].item.id.rawValue]?.cancel()
                start(updated[i].item.episode)
                updated[i].item.state = .waiting
            }
            entries = updated
            index.save(entries)
        }
    }

    public func download(_ episode: Episode, podcast: Podcast) {
        if let existing = item(episode.id), existing.state != .failed { return }
        var updated = entries.filter { $0.item.id != episode.id }
        let item = DownloadedEpisode(episode: episode, podcast: podcast, addedAt: Date(), state: .waiting, artworkFile: nil)
        updated.insert(DownloadsIndex.Entry(item: item, fileName: nil), at: 0)
        entries = updated
        start(episode)
        index.save(entries)
    }

    public func remove(_ id: EpisodeID) {
        guard let i = position(id.rawValue) else { return }
        tasks.removeValue(forKey: id.rawValue)?.cancel()
        progressPublishedAt[id.rawValue] = nil
        if let name = entries[i].fileName { try? FileManager.default.removeItem(at: index.directory.appendingPathComponent(name)) }
        try? FileManager.default.removeItem(at: index.artworkFile(id))
        entries.remove(at: i)
        index.save(entries)
    }

    public func removeAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        progressPublishedAt = [:]
        // Вместе с папкой уходят и файлы, потерянные индексом.
        try? FileManager.default.removeItem(at: index.directory)
        entries = []
        index.save(entries)
    }

    public func localFile(for id: EpisodeID) -> URL? {
        guard let entry = position(id.rawValue).map({ entries[$0] }), entry.item.state.isDownloaded, let name = entry.fileName else { return nil }
        let file = index.directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    public func usage() -> (bytes: Int64, count: Int) {
        entries.reduce(into: (bytes: Int64(0), count: 0)) { usage, entry in
            guard case let .downloaded(bytes) = entry.item.state else { return }
            usage.bytes += bytes
            usage.count += 1
        }
    }

    public func availableCapacity() -> Int64? {
        try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    /// Передаёт обработчик системы; вызываем его, когда сессия отдала все события (`urlSessionDidFinishEvents`).
    public func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == Self.sessionIdentifier else { return completion() }
        backgroundEventsCompletion = completion
    }

    // MARK: - События сессии

    func handleProgress(id: String, written: Int64, expected: Int64) {
        guard let i = position(id), entries[i].item.state.isActive else { return }
        let now = Date()
        let isFirst = entries[i].item.state == .waiting
        // Первый прогресс — сразу (уходим из «ждёт Wi-Fi»), дальше не чаще `progressInterval`.
        if !isFirst, let last = progressPublishedAt[id], now.timeIntervalSince(last) < Self.progressInterval { return }
        progressPublishedAt[id] = now
        entries[i].item.state = .downloading(progress: expected > 0 ? min(Double(written) / Double(expected), 1) : 0)
        if isFirst { index.save(entries) }
    }

    /// Переносит временный файл синхронно: после возврата из делегата система его удаляет.
    /// Принимает и `.failed`: сверка при запуске могла не увидеть задачу, которая как раз завершалась.
    func handleFinished(id: String, tempFile: URL, mimeType: String?) {
        tasks[id] = nil
        progressPublishedAt[id] = nil
        guard let i = position(id), !entries[i].item.state.isDownloaded else { return }
        let item = entries[i].item
        let name = DownloadsIndex.baseName(item.id) + "." + Self.fileExtension(audioURL: item.episode.audioURL, mimeType: mimeType)
        let file = index.directory.appendingPathComponent(name)
        do {
            index.prepareDirectory()
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tempFile, to: file)
            let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            entries[i].fileName = name
            entries[i].item.state = .downloaded(bytes: Int64(bytes))
        } catch {
            entries[i].item.state = .failed
        }
        index.save(entries)
        if entries[i].item.state.isDownloaded { loadArtwork(for: item) }
    }

    /// Отмена (наша) — записи нет; ошибка — «не удалось», повтор через `download`.
    func handleFailure(id: String, cancelled: Bool) {
        tasks[id] = nil
        progressPublishedAt[id] = nil
        guard let i = position(id), entries[i].item.state.isActive else { return }
        if cancelled {
            entries.remove(at: i)
        } else {
            entries[i].item.state = .failed
        }
        index.save(entries)
    }

    /// Расширение из пути URL, затем по MIME; иначе mp3 — без расширения AVPlayer файл может не открыть.
    static func fileExtension(audioURL: URL, mimeType: String?) -> String {
        let fromURL = audioURL.pathExtension.lowercased()
        if ["mp3", "m4a", "aac", "mp4"].contains(fromURL) { return fromURL }
        switch mimeType?.lowercased() {
        case "audio/mp4", "audio/x-m4a": return "m4a"
        default: return "mp3"
        }
    }

    // MARK: - Внутреннее

    private func position(_ id: String) -> Int? {
        entries.firstIndex { $0.item.id.rawValue == id }
    }

    private func start(_ episode: Episode) {
        let id = episode.id.rawValue
        tasks[id] = session.start(url: episode.audioURL, allowsCellularAccess: !wifiOnly, id: id)
    }

    /// Сверка индекса с задачами сессии: идущая запись без задачи — «не удалось», задача без записи — отменяем.
    private func restore(_ running: [(id: String, handle: any DownloadTaskHandle)]) {
        for task in running {
            // У выпуска уже новая задача (сменили Wi-Fi до сверки) — старая с прежним правилом не нужна.
            if let current = tasks[task.id] {
                if current !== task.handle { task.handle.cancel() }
                continue
            }
            if let i = position(task.id), entries[i].item.state.isActive {
                tasks[task.id] = task.handle
            } else {
                task.handle.cancel()
            }
        }
        var updated = entries
        for i in updated.indices where updated[i].item.state.isActive && tasks[updated[i].item.id.rawValue] == nil {
            updated[i].item.state = .failed
        }
        entries = updated
        index.save(entries)
    }

    /// Обложка выпуска (или подкаста) рядом с аудио; не удалась — остаётся nil, выпуск всё равно скачан.
    private func loadArtwork(for item: DownloadedEpisode) {
        let url = item.episode.artworkURL ?? item.podcast.artworkURL
        let file = index.artworkFile(item.id)
        let fetch = fetchArtwork
        Task { [weak self] in
            guard let data = try? await fetch(url), let self, let i = position(item.id.rawValue), entries[i].item.state.isDownloaded,
                  (try? data.write(to: file, options: .atomic)) != nil else { return }
            entries[i].item.artworkFile = file
            index.save(entries)
        }
    }

    /// Событие текущей задачи выпуска; задачи ещё нет в `tasks` — значит, сессия восстановлена раньше сверки, событие наше.
    private func isCurrent(_ task: URLSessionTask, id: String) -> Bool {
        tasks[id].map { $0 === task } ?? true
    }
}

extension BackgroundEpisodeDownloads: URLSessionDownloadDelegate {
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        MainActor.assumeIsolated {
            guard let id = downloadTask.taskDescription, isCurrent(downloadTask, id: id) else { return }
            // Фоновая загрузка «успешна» и с 404: тело ошибки — не аудио.
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return handleFailure(id: id, cancelled: false)
            }
            handleFinished(id: id, tempFile: location, mimeType: downloadTask.response?.mimeType)
        }
    }

    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                       totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard let id = downloadTask.taskDescription, isCurrent(downloadTask, id: id) else { return }
            handleProgress(id: id, written: totalBytesWritten, expected: totalBytesExpectedToWrite)
        }
    }

    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error = error as NSError? else { return }
        // Отменила система (приложение смахнули из переключателя и т.п.) — это сбой, а не удаление пользователем.
        let cancelled = error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
            && error.userInfo[NSURLErrorBackgroundTaskCancelledReasonKey] == nil
        MainActor.assumeIsolated {
            guard let id = task.taskDescription, isCurrent(task, id: id) else { return }
            handleFailure(id: id, cancelled: cancelled)
        }
    }

    nonisolated public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            backgroundEventsCompletion?()
            backgroundEventsCompletion = nil
        }
    }
}

private extension DownloadState {
    var isActive: Bool {
        switch self {
        case .waiting, .downloading: true
        case .downloaded, .failed: false
        }
    }

    var isDownloaded: Bool {
        if case .downloaded = self { true } else { false }
    }
}
