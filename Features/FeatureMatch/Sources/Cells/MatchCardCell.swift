import CoreUI
import SnapKit
import UIKit

/// Блок матча: статус, команды, счёт, подпись о задержке, «В закладки» и «Напомнить».
/// Все отступы — замер макета от верха карточки (ширина 350 pt).
final class MatchCardCell: UICollectionViewCell {
    static let estimatedHeight: CGFloat = 260.5

    var onToggleBookmark: (() -> Void)?
    var onRemind: (() -> Void)?

    private let pill = UIView()
    private let liveDot = UIView()
    private let statusLabel = UILabel()
    private let homeBadge = TeamBadgeView(size: 56, font: Typography.text(15, .bold))
    private let awayBadge = TeamBadgeView(size: 56, font: Typography.text(15, .bold))
    private let homeLabel = UILabel()
    private let awayLabel = UILabel()
    private let scoreLabel = UILabel()
    private let noteLabel = UILabel()
    private let bookmarkButton = UIButton(configuration: .plain())
    private let remindButton = UIButton(configuration: .plain())
    private let buttons: UIStackView
    private var buttonsBelowNote: Constraint?
    private var buttonsBelowNames: Constraint?

    override init(frame: CGRect) {
        buttons = UIStackView(arrangedSubviews: [bookmarkButton, remindButton])
        super.init(frame: frame)
        contentView.backgroundColor = Palette.surface
        contentView.layer.cornerRadius = 24

        pill.layer.cornerRadius = 14
        liveDot.backgroundColor = Palette.accent
        liveDot.layer.cornerRadius = 4
        statusLabel.font = Typography.text(13, .bold)
        let nameFont = Typography.text(16, .semibold)
        for label in [homeLabel, awayLabel] {
            label.font = nameFont
            label.textColor = Palette.textPrimary
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
        }
        let scoreFont = Typography.display(41)
        scoreLabel.font = scoreFont
        scoreLabel.textColor = Palette.textPrimary
        let noteFont = Typography.text(13)
        noteLabel.font = noteFont
        noteLabel.textColor = Palette.textSecondary
        noteLabel.text = "Счёт обновляется с небольшой задержкой"
        buttons.distribution = .fillEqually
        buttons.spacing = 8
        bookmarkButton.addAction(UIAction { [weak self] _ in self?.onToggleBookmark?() }, for: .touchUpInside)
        remindButton.addAction(UIAction { [weak self] _ in self?.onRemind?() }, for: .touchUpInside)

        let pillContent = UIStackView(arrangedSubviews: [liveDot, statusLabel])
        pillContent.alignment = .center
        pillContent.spacing = 6.5
        pill.addSubview(pillContent)
        [pill, homeBadge, awayBadge, scoreLabel, homeLabel, awayLabel, noteLabel, buttons].forEach(contentView.addSubview)

        pill.snp.makeConstraints {
            $0.top.equalToSuperview().offset(20)
            $0.height.equalTo(28)
            $0.centerX.equalToSuperview()
        }
        pillContent.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(12)
            $0.centerY.equalToSuperview()
        }
        liveDot.snp.makeConstraints { $0.size.equalTo(8) }
        // Центры кружков в 69 pt от краёв карточки.
        homeBadge.snp.makeConstraints {
            $0.top.equalToSuperview().offset(64)
            $0.centerX.equalTo(contentView.snp.leading).offset(69)
        }
        awayBadge.snp.makeConstraints {
            $0.top.equalTo(homeBadge)
            $0.centerX.equalTo(contentView.snp.trailing).offset(-69)
        }
        // Базовая линия счёта — по низу кружков.
        scoreLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.firstBaseline.equalTo(homeBadge.snp.bottom)
        }
        for (label, badge) in [(homeLabel, homeBadge), (awayLabel, awayBadge)] {
            label.snp.makeConstraints {
                $0.centerX.equalTo(badge)
                $0.width.lessThanOrEqualTo(130)
                $0.firstBaseline.equalTo(contentView.snp.top).offset(131 + nameFont.capHeight)
            }
        }
        noteLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview().inset(16)
            $0.firstBaseline.equalTo(homeLabel).offset(31.5)
        }
        buttons.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(16)
            $0.height.equalTo(48)
            $0.bottom.equalToSuperview().inset(20)
            buttonsBelowNote = $0.top.equalTo(noteLabel.snp.firstBaseline).offset(18.5).constraint
            buttonsBelowNames = $0.top.equalTo(homeLabel.snp.firstBaseline).offset(26).constraint
        }
        buttonsBelowNames?.deactivate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ card: MatchState.Card) {
        statusLabel.text = card.statusText
        statusLabel.textColor = card.isLive ? Palette.accent : Palette.textSecondary
        liveDot.isHidden = !card.isLive
        pill.backgroundColor = card.isLive ? Palette.accentMuted : Palette.surfaceRaised
        homeBadge.configure(abbreviation: card.home.abbreviation, logoURL: card.home.logoURL)
        awayBadge.configure(abbreviation: card.away.abbreviation, logoURL: card.away.logoURL)
        homeLabel.text = card.home.name
        awayLabel.text = card.away.name
        scoreLabel.text = card.score
        noteLabel.isHidden = !card.showsDelayNote
        if card.showsDelayNote {
            buttonsBelowNames?.deactivate()
            buttonsBelowNote?.activate()
        } else {
            buttonsBelowNote?.deactivate()
            buttonsBelowNames?.activate()
        }

        Self.style(
            bookmarkButton,
            title: card.isBookmarked ? "В закладках" : "В закладки",
            icon: card.isBookmarked ? "bookmark-fill" : "bookmark",
            filled: card.isBookmarked
        )
        remindButton.isHidden = card.reminder == .hidden
        Self.style(remindButton, title: card.reminder == .on ? "Напомню" : "Напомнить", icon: "bell", filled: card.reminder == .on)

        scoreLabel.accessibilityLabel = card.score.replacingOccurrences(of: " : ", with: ":")
        bookmarkButton.accessibilityValue = card.isBookmarked ? "в закладках" : nil
        remindButton.accessibilityValue = card.reminder == .on ? "напоминание включено" : nil
    }

    /// Включённое состояние — светлая заливка, выключенное — контур, как «Напомнить» в макете.
    private static func style(_ button: UIButton, title: String, icon: String, filled: Bool) {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: Typography.text(15, .semibold)]))
        config.image = UIImage(named: icon, in: .module, compatibleWith: nil)
        config.imagePadding = 10
        config.baseForegroundColor = filled ? Palette.background : Palette.textPrimary
        config.background.backgroundColor = filled ? Palette.textPrimary : .clear
        config.background.strokeColor = filled ? nil : Palette.track
        config.background.strokeWidth = filled ? 0 : 1
        config.background.cornerRadius = 14
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        button.configuration = config
    }
}
