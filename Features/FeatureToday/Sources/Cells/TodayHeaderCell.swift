import CoreUI
import SnapKit
import UIKit

/// Шапка: логотип и заголовок экрана (навигационная панель на «Сегодня» скрыта).
/// Отступы — от верха безопасной зоны, замер по макету.
final class TodayHeaderCell: UICollectionViewCell {
    /// До верха полосы дней.
    static let height: CGFloat = 122.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        let halo = UIView()
        halo.backgroundColor = Palette.accentHalo
        halo.layer.cornerRadius = 9
        let dot = UIView()
        dot.backgroundColor = Palette.accent
        dot.layer.cornerRadius = 5

        let logoFont = Typography.display(16)
        let logo = UILabel()
        logo.font = logoFont
        logo.textColor = Palette.textPrimary
        logo.text = "TRIBUNA"

        let titleFont = Typography.screenTitle
        let title = UILabel()
        title.font = titleFont
        title.textColor = Palette.textPrimary
        title.text = "Сегодня"
        title.accessibilityTraits = .header

        [halo, dot, logo, title].forEach(contentView.addSubview)
        dot.snp.makeConstraints {
            $0.size.equalTo(10)
            $0.leading.equalToSuperview().offset(20)
            $0.centerY.equalTo(contentView.snp.top).offset(31)
        }
        halo.snp.makeConstraints {
            $0.center.equalTo(dot)
            $0.size.equalTo(18)
        }
        logo.snp.makeConstraints {
            $0.leading.equalTo(dot.snp.trailing).offset(8)
            $0.firstBaseline.equalTo(dot.snp.centerY).offset(logoFont.capHeight / 2)
        }
        title.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(20)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(75.5 + titleFont.capHeight)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}
