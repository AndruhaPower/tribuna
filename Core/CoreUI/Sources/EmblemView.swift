import SnapKit
import UIKit

/// Значок турнира 20 pt на светлой подложке: тёмные эмблемы (АПЛ, Лига 1) не читаются на фоне приложения.
public final class EmblemView: UIView {
    public static let size: CGFloat = 20
    private let imageView = RemoteImageView()

    public init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 1, alpha: 0.92)
        layer.cornerRadius = 5
        isHidden = true
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        imageView.snp.makeConstraints { $0.edges.equalToSuperview().inset(2) }
        snp.makeConstraints { $0.size.equalTo(Self.size) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Значок скрыт, пока картинка не загрузилась (и если загрузка не удалась).
    /// `onVisibilityChange` — чтобы владелец освободил или занял место под значок.
    public func setImage(url: URL?, loader: ImageLoader = .shared, onVisibilityChange: ((Bool) -> Void)? = nil) {
        isHidden = true
        onVisibilityChange?(false)
        imageView.setImage(url: url, loader: loader) { [weak self] in
            self?.isHidden = false
            onVisibilityChange?(true)
        }
    }
}
