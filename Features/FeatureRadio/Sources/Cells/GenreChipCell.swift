import CoreUI
import SnapKit
import UIKit

/// Чип жанра высотой 36 pt, ширина по тексту. Поля 13 pt: SF в UIKit шире шрифта макета (D18), так ширина чипов совпадает с макетом.
final class GenreChipCell: UICollectionViewCell {
    static let height: CGFloat = 36

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = Self.height / 2
        contentView.layer.borderWidth = 1
        label.font = Typography.text(15, .semibold)
        contentView.addSubview(label)
        label.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(13)
            $0.centerY.equalToSuperview()
        }
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ chip: RadioState.Chip) {
        label.text = chip.title
        label.textColor = chip.isSelected ? Palette.background : Palette.textPrimary
        contentView.backgroundColor = chip.isSelected ? Palette.textPrimary : Palette.background
        contentView.layer.borderColor = (chip.isSelected ? Palette.textPrimary : Palette.track).cgColor
        accessibilityLabel = chip.title
        accessibilityTraits = chip.isSelected ? [.button, .selected] : .button
    }
}
