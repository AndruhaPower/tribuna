import CoreUI
import SnapKit
import UIKit

/// Чип дня 52×56 pt: день недели и число.
final class DayChipCell: UICollectionViewCell {
    static let size = CGSize(width: 52, height: 56)

    private let weekdayLabel = UILabel()
    private let numberLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 14
        contentView.layer.borderWidth = 1
        let weekdayFont = Typography.text(13, .medium)
        let numberFont = Typography.text(17, .semibold)
        weekdayLabel.font = weekdayFont
        numberLabel.font = numberFont
        contentView.addSubview(weekdayLabel)
        contentView.addSubview(numberLabel)
        // Верх заглавных: день недели — 12.5 pt, число — 30 pt от верха чипа.
        weekdayLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.firstBaseline.equalTo(contentView.snp.top).offset(12.5 + weekdayFont.capHeight)
        }
        numberLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.firstBaseline.equalTo(contentView.snp.top).offset(30 + numberFont.capHeight)
        }
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ day: TodayState.DayItem) {
        weekdayLabel.text = day.weekday
        numberLabel.text = day.number
        // У выбранного чипа контур цвета фона: в макете светлая заливка на 1 pt уже обычного чипа.
        contentView.backgroundColor = day.isSelected ? Palette.textPrimary : Palette.surface
        contentView.layer.borderColor = (day.isSelected ? Palette.background : Palette.track).cgColor
        weekdayLabel.textColor = day.isSelected ? Palette.background : Palette.textSecondary
        numberLabel.textColor = day.isSelected ? Palette.background : Palette.textPrimary
        accessibilityLabel = "\(day.weekday) \(day.number)"
        accessibilityTraits = day.isSelected ? [.button, .selected] : .button
    }
}
