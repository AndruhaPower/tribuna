import UIKit

/// UIImageView с загрузкой по URL. Смена URL отменяет прежнюю загрузку — безопасно для переиспользуемых ячеек.
public final class RemoteImageView: UIImageView {
    public private(set) var url: URL?
    private var task: Task<Void, Never>?

    /// nil — очистить. `maxPixelSize` nil — по размеру view (bounds × scale), при нулевых bounds — по умолчанию.
    /// `onLoaded` вызывается, когда картинка установлена.
    public func setImage(url: URL?, maxPixelSize: CGFloat? = nil, loader: ImageLoader = .shared, onLoaded: (() -> Void)? = nil) {
        task?.cancel()
        self.url = url
        image = nil
        guard let url else { return }
        let size = maxPixelSize ?? (max(bounds.width, bounds.height) > 0
            ? max(bounds.width, bounds.height) * traitCollection.displayScale : ImageLoader.defaultMaxPixelSize)
        if let cached = loader.cachedImage(for: url, maxPixelSize: size) {
            image = cached
            onLoaded?()
            return
        }
        task = Task { [weak self] in
            let loaded = await loader.image(for: url, maxPixelSize: size)
            guard !Task.isCancelled, let self, self.url == url, let loaded else { return }
            self.image = loaded
            onLoaded?()
        }
    }
}
