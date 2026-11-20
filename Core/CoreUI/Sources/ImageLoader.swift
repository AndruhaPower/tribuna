import UIKit

/// Загрузка картинок по URL: кэш в памяти, дисковый URLCache, склейка параллельных запросов.
/// Неудачные URL помним до конца сессии — без повторов при скролле.
@MainActor
public final class ImageLoader {
    public static let shared = ImageLoader()

    private let fetch: @Sendable (URL) async throws -> Data
    private let cache = NSCache<NSURL, UIImage>()
    /// Сетевой сбой (URLError) не запоминаем — следующий показ повторит запрос; 4xx и битые данные — навсегда на сессию.
    private enum Result: Sendable {
        case image(UIImage)
        case definitiveFailure, transientFailure
    }

    private var inFlight: [URL: Task<Result, Never>] = [:]
    private var failed: Set<URL> = []

    public init(fetch: (@Sendable (URL) async throws -> Data)? = nil) {
        self.fetch = fetch ?? Self.networkFetch
        cache.countLimit = 300
    }

    public func cachedImage(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    public func image(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        if failed.contains(url) { return nil }
        if let task = inFlight[url] {
            if case let .image(image) = await task.value { return image }
            return nil
        }
        let fetch = fetch
        let task = Task<Result, Never> {
            do {
                let data = try await fetch(url)
                return UIImage(data: data).map(Result.image) ?? .definitiveFailure
            } catch is URLError {
                return .transientFailure
            } catch {
                return .definitiveFailure
            }
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        switch result {
        case let .image(image): cache.setObject(image, forKey: url as NSURL)
        case .definitiveFailure: failed.insert(url)
        case .transientFailure: break
        }
        if case let .image(image) = result { return image }
        return nil
    }

    struct RejectedError: Error {}

    /// 4xx — герба нет, повторять бессмысленно (кроме 408/429); остальное — временный сбой (URLError).
    nonisolated static func validate(statusCode code: Int) throws {
        if code == 200 { return }
        if (400..<500).contains(code), code != 408, code != 429 { throw RejectedError() }
        throw URLError(.badServerResponse)
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Память держит NSCache; диск — отдельный каталог, чтобы не мешать остальному кэшу приложения.
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("images")
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 100_000_000, directory: directory)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private static let networkFetch: @Sendable (URL) async throws -> Data = { url in
        let (data, response) = try await session.data(from: url)
        try validate(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return data
    }
}
