import SnapKit
import UIKit

/// Кружок с аббревиатурой команды вместо герба (D16). По умолчанию 28 pt, текст SF 12 semibold — замер по макету «Сегодня».
public final class TeamBadgeView: UIView {
    public static let size: CGFloat = 28

    public var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    private let label = UILabel()

    public init(size: CGFloat = TeamBadgeView.size, font: UIFont = Typography.text(12, .semibold)) {
        super.init(frame: .zero)
        backgroundColor = Palette.surfaceHigh
        layer.cornerRadius = size / 2
        label.font = font
        label.textColor = Palette.textPrimary
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        addSubview(label)
        snp.makeConstraints { $0.size.equalTo(size) }
        // Длинная аббревиатура («RMA») ужимается шрифтом, а не растягивает кружок.
        label.snp.makeConstraints {
            $0.centerY.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(2)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}
