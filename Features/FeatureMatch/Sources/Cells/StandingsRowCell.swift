import CoreUI
import SnapKit
import UIKit

/// Строка таблицы турнира «# · Команда · И · О» или её заголовок.
/// Ячейки сами рисуют подложку карточки: подсветка строки доходит до краёв и скругляется на последней.
/// Замер макета от краёв карточки: «#» с 14 pt, команда с 50.5 pt, «И» по правому краю в 63 pt, «О» — в 14 pt.
final class StandingsRowCell: UICollectionViewCell {
    static let rowHeight: CGFloat = 37
    static let headerHeight: CGFloat = 34.5
    private static let cornerRadius: CGFloat = 18

    private let positionLabel = UILabel()
    private let nameLabel = UILabel()
    private let logoView = RemoteImageView()
    private var nameLeading: Constraint?
    private let playedLabel = UILabel()
    private let pointsLabel = UILabel()
    private var height: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = Self.cornerRadius
        nameLabel.lineBreakMode = .byTruncatingTail
        // Задаёт высоту ячейки при самоизмерении: у заголовка и строк она разная.
        let sizer = UIView()
        [sizer, positionLabel, logoView, nameLabel, playedLabel, pointsLabel].forEach(contentView.addSubview)
        sizer.snp.makeConstraints {
            $0.top.bottom.leading.equalToSuperview()
            $0.width.equalTo(0)
            height = $0.height.equalTo(Self.rowHeight).priority(999).constraint
        }
        positionLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(14)
            $0.centerY.equalToSuperview()
        }
        logoView.contentMode = .scaleAspectFit
        logoView.snp.makeConstraints {
            $0.size.equalTo(20)
            $0.leading.equalToSuperview().offset(50.5)
            $0.centerY.equalToSuperview()
        }
        nameLabel.snp.makeConstraints {
            nameLeading = $0.leading.equalToSuperview().offset(50.5).constraint
            $0.trailing.lessThanOrEqualTo(playedLabel.snp.leading).offset(-12)
            $0.centerY.equalToSuperview()
        }
        playedLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(63)
            $0.centerY.equalToSuperview()
        }
        pointsLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(14)
            $0.centerY.equalToSuperview()
        }
        for label in [playedLabel, pointsLabel] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configureHeader() {
        logoView.setImage(url: nil)
        nameLeading?.update(offset: 50.5)
        apply(["#", "Команда", "И", "О"], font: Typography.text(13), color: Palette.textSecondary)
        contentView.backgroundColor = Palette.surface
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        height?.update(offset: Self.headerHeight)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    func configure(_ row: MatchState.Row, isLast: Bool) {
        logoView.setImage(url: row.logoURL)
        nameLeading?.update(offset: 50.5 + 20 + 8)
        apply([row.position, row.name, row.played, row.points], font: Typography.text(15, .semibold), color: Palette.textPrimary)
        contentView.backgroundColor = row.isHighlighted ? Palette.highlight : Palette.surface
        contentView.layer.maskedCorners = isLast ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : []
        height?.update(offset: Self.rowHeight)
        isAccessibilityElement = true
        accessibilityElementsHidden = false
        accessibilityLabel = "\(row.position) место, \(row.name), игр \(row.played), очков \(row.points)"
    }

    private func apply(_ texts: [String], font: UIFont, color: UIColor) {
        for (label, text) in zip([positionLabel, nameLabel, playedLabel, pointsLabel], texts) {
            label.text = text
            label.font = font
            label.textColor = color
        }
    }
}
