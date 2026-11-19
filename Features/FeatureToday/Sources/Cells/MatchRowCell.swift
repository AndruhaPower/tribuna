import CoreUI
import SnapKit
import UIKit

/// Строка матча в карточке турнира: время или счёт, две команды, закладка 20 pt. 72 pt — замер по макету.
final class MatchRowCell: UICollectionViewCell {
    static let height: CGFloat = 72

    var onToggleBookmark: (() -> Void)?

    private let leadingLabel = UILabel()
    private let homeLabel = UILabel()
    private let awayLabel = UILabel()
    private let bookmarkButton = UIButton(type: .custom)
    /// Висит над ячейкой в зазоре 1 pt между строками.
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        leadingLabel.font = Typography.text(15, .semibold)
        leadingLabel.textColor = Palette.textPrimary
        // «LIVE 2 : 1», «Перенесён» шире колонки времени.
        leadingLabel.adjustsFontSizeToFitWidth = true
        leadingLabel.minimumScaleFactor = 0.6
        let teamFont = Typography.text(16, .medium)
        for label in [homeLabel, awayLabel] {
            label.font = teamFont
            label.textColor = Palette.textPrimary
        }
        bookmarkButton.tintColor = Palette.textSecondary
        bookmarkButton.addAction(UIAction { [weak self] _ in self?.onToggleBookmark?() }, for: .touchUpInside)
        separator.backgroundColor = Palette.separator

        [leadingLabel, homeLabel, awayLabel, bookmarkButton, separator].forEach(contentView.addSubview)
        // Замер от края карточки: время с 16 pt, команды с 76 pt, центр закладки в 38 pt от правого края.
        leadingLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(16)
            $0.width.lessThanOrEqualTo(56)
            $0.centerY.equalToSuperview()
        }
        homeLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(76)
            $0.trailing.lessThanOrEqualTo(bookmarkButton.snp.leading).offset(-4)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(19 + teamFont.capHeight)
        }
        awayLabel.snp.makeConstraints {
            $0.leading.equalTo(homeLabel)
            $0.trailing.lessThanOrEqualTo(bookmarkButton.snp.leading).offset(-4)
            $0.firstBaseline.equalTo(homeLabel).offset(22)
        }
        bookmarkButton.snp.makeConstraints {
            $0.size.equalTo(44)
            $0.trailing.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
        }
        separator.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.bottom.equalTo(contentView.snp.top)
            $0.height.equalTo(1)
        }
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ row: TodayState.MatchRow, isFirst: Bool) {
        leadingLabel.text = row.leading
        homeLabel.text = row.home
        awayLabel.text = row.away
        separator.isHidden = isFirst
        let icon = row.isBookmarked ? "bookmark-fill" : "bookmark"
        bookmarkButton.setImage(UIImage(named: icon, in: .module, compatibleWith: nil), for: .normal)
        bookmarkButton.tintColor = row.isBookmarked ? Palette.accent : Palette.textSecondary
        bookmarkButton.accessibilityLabel = row.isBookmarked ? "Убрать из закладок" : "В закладки"
        contentView.isAccessibilityElement = true
        contentView.accessibilityLabel = "\(row.leading), \(row.home) — \(row.away)"
        contentView.accessibilityTraits = .button
    }
}

/// Подложка карточки турнира под строками.
final class CompetitionCardBackground: UICollectionReusableView {
    static let kind = "competition-card"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.surface
        layer.cornerRadius = 18
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}
