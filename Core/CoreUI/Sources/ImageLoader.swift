import UIKit

/// Загрузка картинок по URL: кэш в памяти, дисковый URLCache, склейка параллельных запросов.
/// Неудачные URL помним до конца сессии — без повторов при скролле.
@MainActor
public final class ImageLoader {
    public static let shared = ImageLoader()

    private let fetch: @Sendable (URL) async throws -> Data
    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var failed: Set<URL> = []

    public init(fetch: (@Sendable (URL) async throws -> Data)? = nil) {
        self.fetch = fetch ?? Self.networkFetch
    }

    public func cachedImage(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    public func image(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        if failed.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }
        let fetch = fetch
        let task = Task<UIImage?, Never> {
            guard let data = try? await fetch(url) else { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) } else { failed.insert(url) }
        return image
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private static let networkFetch: @Sendable (URL) async throws -> Data = { url in
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
