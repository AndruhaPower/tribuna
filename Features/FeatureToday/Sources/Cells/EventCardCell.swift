import CoreUI
import SnapKit
import UIKit

/// Карточка «Моих событий». Кнопки «Слушать эфир матча» пока нет (нужна связка матч → станция, D16),
/// поэтому карточка заканчивается под второй командой с тем же отступом, что под кнопкой в макете.
final class EventCardCell: UICollectionViewCell {
    static let height: CGFloat = 128.5

    private let headerLabel = UILabel()
    private let liveDot = UIView()
    private let statusLabel = UILabel()
    private let homeRow = TeamScoreRow()
    private let awayRow = TeamScoreRow()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Palette.surfaceRaised
        contentView.layer.cornerRadius = 18
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = Palette.track.cgColor

        let captionFont = Typography.text(13)
        headerLabel.font = captionFont
        headerLabel.textColor = Palette.textSecondary
        statusLabel.font = Typography.text(13, .bold)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        liveDot.backgroundColor = Palette.accent
        liveDot.layer.cornerRadius = 4

        [headerLabel, liveDot, statusLabel, homeRow, awayRow].forEach(contentView.addSubview)
        // Замер по макету от внешнего края карточки: текст — 17 pt слева и справа, верх заглавных шапки — 19.5 pt.
        headerLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(17)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(19.5 + captionFont.capHeight)
        }
        statusLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(17)
            $0.leading.greaterThanOrEqualTo(headerLabel.snp.trailing).offset(24)
            $0.firstBaseline.equalTo(headerLabel)
        }
        liveDot.snp.makeConstraints {
            $0.size.equalTo(8)
            $0.trailing.equalTo(statusLabel.snp.leading).offset(-6.5)
            $0.centerY.equalTo(headerLabel.snp.firstBaseline).offset(-captionFont.capHeight / 2)
        }
        homeRow.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(17)
            $0.top.equalToSuperview().offset(45.5)
        }
        awayRow.snp.makeConstraints {
            $0.leading.trailing.equalTo(homeRow)
            $0.top.equalTo(homeRow.snp.bottom).offset(10)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ event: TodayState.EventCard) {
        headerLabel.text = event.header
        statusLabel.text = event.statusText
        statusLabel.textColor = event.isLive ? Palette.accent : Palette.textSecondary
        liveDot.isHidden = !event.isLive
        homeRow.configure(event.home, score: event.homeScore)
        awayRow.configure(event.away, score: event.awayScore)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [event.header, event.statusText,
                              "\(event.home.name) \(event.homeScore)", "\(event.away.name) \(event.awayScore)"]
            .joined(separator: ", ")
    }
}

/// Строка команды в карточке: кружок, название, счёт крупно.
private final class TeamScoreRow: UIView {
    private let badge = TeamBadgeView()
    private let nameLabel = UILabel()
    private let scoreLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        nameLabel.font = Typography.text(17, .semibold)
        nameLabel.textColor = Palette.textPrimary
        scoreLabel.font = Typography.display(24)
        scoreLabel.textColor = Palette.textPrimary
        scoreLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        [badge, nameLabel, scoreLabel].forEach(addSubview)
        badge.snp.makeConstraints { $0.leading.top.bottom.equalToSuperview() }
        nameLabel.snp.makeConstraints {
            $0.leading.equalTo(badge.snp.trailing).offset(10)
            $0.centerY.equalTo(badge)
        }
        scoreLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview()
            $0.leading.greaterThanOrEqualTo(nameLabel.snp.trailing).offset(12)
            $0.centerY.equalTo(badge)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ team: TodayState.TeamItem, score: String) {
        badge.configure(abbreviation: team.abbreviation, logoURL: team.logoURL)
        nameLabel.text = team.name
        scoreLabel.text = score
    }
}
