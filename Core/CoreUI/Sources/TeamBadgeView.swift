import SnapKit
import UIKit

/// Кружок с аббревиатурой команды с гербом (D26); пока герб не загружен — аббревиатура. По умолчанию 28 pt, текст SF 12 semibold — замер по макету «Сегодня».
public final class TeamBadgeView: UIView {
    public static let size: CGFloat = 28

    private let label = UILabel()
    private let logoView = RemoteImageView()
    private let loader: ImageLoader

    public init(size: CGFloat = TeamBadgeView.size, font: UIFont = Typography.text(12, .semibold), loader: ImageLoader = .shared) {
        self.loader = loader
        super.init(frame: .zero)
        backgroundColor = Palette.surfaceHigh
        layer.cornerRadius = size / 2
        label.font = font
        label.textColor = Palette.textPrimary
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)
        logoView.contentMode = .scaleAspectFit
        addSubview(logoView)
        snp.makeConstraints { $0.size.equalTo(size) }
        // Отступ ≈18 % диаметра: герб не упирается в край круга.
        logoView.snp.makeConstraints { $0.edges.equalToSuperview().inset(size * 0.18) }
        // Длинная аббревиатура («RMA») ужимается шрифтом, а не растягивает кружок.
        label.snp.makeConstraints {
            $0.centerY.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(2)
        }
    }

    /// Аббревиатура видна, пока герб не загружен (или его нет / загрузка не удалась).
    public func configure(abbreviation: String?, logoURL: URL?) {
        label.text = abbreviation
        label.isHidden = false
        logoView.setImage(url: logoURL, loader: loader) { [weak self] in self?.label.isHidden = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}
