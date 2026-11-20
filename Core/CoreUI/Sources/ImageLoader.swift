import ImageIO
import UIKit

/// Загрузка картинок по URL (и `file://`): кэш в памяти, дисковый URLCache, склейка параллельных запросов.
/// Неудачные URL помним до конца сессии — без повторов при скролле.
@MainActor
public final class ImageLoader {
    public static let shared = ImageLoader()

    private let fetch: @Sendable (URL) async throws -> Data
    private let cache = NSCache<NSString, UIImage>()
    /// Размер по умолчанию — маленькие гербы и значки.
    public nonisolated static let defaultMaxPixelSize: CGFloat = 120
    /// Сетевой сбой (URLError) не запоминаем — следующий показ повторит запрос; 4xx и битые данные — навсегда на сессию.
    private enum Result: Sendable {
        case image(UIImage)
        case definitiveFailure, transientFailure
    }

    private var inFlight: [String: Task<Result, Never>] = [:]
    private var failed: Set<URL> = []

    public init(fetch: (@Sendable (URL) async throws -> Data)? = nil) {
        self.fetch = fetch ?? Self.networkFetch
        cache.countLimit = 300
        cache.totalCostLimit = 50_000_000  // стоимость — байты декодированной картинки (w × h × 4)
    }

    /// Ключ кэша и склейки: URL + размер, округлённый вверх до 64 px (близкие размеры делят запись).
    nonisolated static func bucket(_ size: CGFloat) -> Int { max(1, Int((size / 64).rounded(.up))) * 64 }
    private func key(_ url: URL, _ bucket: Int) -> String { "\(url.absoluteString)#\(bucket)" }

    public func cachedImage(for url: URL, maxPixelSize: CGFloat = ImageLoader.defaultMaxPixelSize) -> UIImage? {
        cache.object(forKey: key(url, Self.bucket(maxPixelSize)) as NSString)
    }

    /// Декодирует с даунсэмплингом до `maxPixelSize` по большей стороне (ImageIO); вызывается вне главного потока.
    nonisolated static func decode(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, max(w, h)),  // не увеличиваем маленькие
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }

    public func image(for url: URL, maxPixelSize: CGFloat = ImageLoader.defaultMaxPixelSize) async -> UIImage? {
        let bucket = Self.bucket(maxPixelSize)
        let key = key(url, bucket)
        if let image = cache.object(forKey: key as NSString) { return image }
        if failed.contains(url) { return nil }
        if let task = inFlight[key] {
            if case let .image(image) = await task.value { return image }
            return nil
        }
        let fetch = fetch
        // Task без привязки к актору: декодирование идёт вне главного потока.
        let task = Task.detached { () -> Result in
            do {
                let data = try await fetch(url)
                return Self.decode(data, maxPixelSize: bucket).map(Result.image) ?? .definitiveFailure
            } catch is URLError {
                return .transientFailure
            } catch {
                return .definitiveFailure
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        switch result {
        case let .image(image):
            let cost = image.cgImage.map { $0.width * $0.height * 4 } ?? 0
            cache.setObject(image, forKey: key as NSString, cost: cost)
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
        // Локальный файл (обложка скачанного выпуска): ответ не HTTP, статуса нет.
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await session.data(from: url)
        try validate(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return data
    }
}
