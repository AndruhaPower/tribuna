import UIKit

/// UIImageView с загрузкой по URL. Смена URL отменяет прежнюю загрузку — безопасно для переиспользуемых ячеек.
public final class RemoteImageView: UIImageView {
    public private(set) var url: URL?
    private var task: Task<Void, Never>?

    /// nil — очистить. `onLoaded` вызывается, когда картинка установлена.
    public func setImage(url: URL?, loader: ImageLoader = .shared, onLoaded: (() -> Void)? = nil) {
        task?.cancel()
        self.url = url
        image = nil
        guard let url else { return }
        if let cached = loader.cachedImage(for: url) {
            image = cached
            onLoaded?()
            return
        }
        task = Task { [weak self] in
            let loaded = await loader.image(for: url)
            guard !Task.isCancelled, let self, self.url == url, let loaded else { return }
            self.image = loaded
            onLoaded?()
        }
    }
}
