import SnapKit
import UIKit

/// Заголовок секции списка: капсом слева, подпись справа («2 матча», «ночь на чт»).
/// Высота — от низа предыдущего блока до верха карточки секции, как в макете «Сегодня».
public final class SectionHeaderView: UICollectionReusableView {
    public static let height: CGFloat = 45.5
    /// Середина заглавных букв от верха заголовка.
    private static let capCenter: CGFloat = 25.75
    private static let iconSize = EmblemView.size

    private let titleLabel = UILabel()
    private let iconView = EmblemView()
    private var titleLeading: Constraint?
    private let trailingLabel = UILabel()
    private let titleFont = Typography.text(14, .semibold)

    override public init(frame: CGRect) {
        super.init(frame: frame)
        trailingLabel.font = Typography.text(13)
        trailingLabel.textColor = Palette.textSecondary
        trailingLabel.textAlignment = .right
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(trailingLabel)
        titleLabel.snp.makeConstraints {
            titleLeading = $0.leading.equalToSuperview().constraint
            $0.firstBaseline.equalTo(snp.top).offset(Self.capCenter + titleFont.capHeight / 2)
        }
        iconView.snp.makeConstraints {
            $0.leading.equalToSuperview()
            $0.centerY.equalTo(titleLabel.snp.firstBaseline).offset(-titleFont.capHeight / 2)
        }
        trailingLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview()
            $0.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(8)
            $0.firstBaseline.equalTo(titleLabel)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// `iconURL` — значок турнира перед названием; nil — без значка.
    public func configure(title: String, trailing: String?, iconURL: URL? = nil) {
        iconView.setImage(url: iconURL) { [weak self] visible in
            self?.titleLeading?.update(offset: visible ? Self.iconSize + 6 : 0)
        }
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: Palette.textSecondary,
            .kern: 0.3,
        ])
        trailingLabel.text = trailing
    }
}
