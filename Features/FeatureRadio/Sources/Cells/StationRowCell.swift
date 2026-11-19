import CoreUI
import SnapKit
import UIKit

/// Строка станции: значок с буквами, название, подпись, кнопка play. Шаг строк 69 pt — замер по макету,
/// разделитель внизу строки (у последней скрыт).
final class StationRowCell: UICollectionViewCell {
    static let height: CGFloat = 69

    var onPlay: (() -> Void)?

    private let initialsLabel = UILabel()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playButton = PlayButton(tint: Palette.textPrimary)
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let logo = UIView()
        logo.backgroundColor = Palette.surfaceRaised
        logo.layer.cornerRadius = 12
        initialsLabel.font = Typography.text(14, .bold)
        initialsLabel.textColor = Palette.textPrimary
        let nameFont = Typography.text(16, .semibold)
        nameLabel.font = nameFont
        nameLabel.textColor = Palette.textPrimary
        let subtitleFont = Typography.text(13)
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = Palette.textSecondary
        playButton.layer.cornerRadius = 22
        playButton.layer.borderWidth = 1
        playButton.layer.borderColor = Palette.track.cgColor
        playButton.addAction(UIAction { [weak self] _ in self?.onPlay?() }, for: .touchUpInside)
        separator.backgroundColor = Palette.separator

        [logo, nameLabel, subtitleLabel, playButton, separator].forEach(contentView.addSubview)
        logo.addSubview(initialsLabel)
        // Замер от верха строки: значок и кнопка 44 pt с 8.5 pt, текст с 57 pt, заглавные названия с 16.5 pt, подписи с 36.5 pt.
        logo.snp.makeConstraints {
            $0.leading.equalToSuperview()
            $0.top.equalToSuperview().offset(8.5)
            $0.size.equalTo(44)
        }
        initialsLabel.snp.makeConstraints { $0.center.equalToSuperview() }
        playButton.snp.makeConstraints {
            $0.trailing.equalToSuperview()
            $0.centerY.equalTo(logo)
            $0.size.equalTo(44)
        }
        nameLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(56.5)
            $0.trailing.lessThanOrEqualTo(playButton.snp.leading).offset(-12)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(16.5 + nameFont.capHeight)
        }
        subtitleLabel.snp.makeConstraints {
            $0.leading.equalTo(nameLabel)
            $0.trailing.lessThanOrEqualTo(playButton.snp.leading).offset(-12)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(36.5 + subtitleFont.capHeight)
        }
        separator.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalToSuperview().offset(62.5)
            $0.height.equalTo(1)
        }
        // VoiceOver: строка — один элемент-кнопка, нажатие запускает станцию.
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ row: RadioState.Row, isLast: Bool) {
        initialsLabel.text = row.initials
        nameLabel.text = row.name
        subtitleLabel.text = row.subtitle
        playButton.configure(row.button)
        separator.isHidden = isLast
        accessibilityLabel = "\(row.name), \(row.subtitle)"
        accessibilityValue = row.button == .play ? nil : "играет"
        accessibilityHint = row.button == .play ? "Слушать" : "Пауза"
    }
}
