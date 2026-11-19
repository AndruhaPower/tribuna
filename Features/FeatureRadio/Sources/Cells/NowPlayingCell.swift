import CoreUI
import SnapKit
import UIKit

/// Карточка «Сейчас играет» 176 pt: значок, название, подпись, play/pause и волна.
/// Все отступы — замер макета от края карточки (ширина 350 pt).
final class NowPlayingCell: UICollectionViewCell {
    static let height: CGFloat = 176

    var onPlayPause: (() -> Void)?

    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let button = PlayButton(tint: Palette.onAccent)
    private let wave = WaveView(style: NowPlayingCell.waveStyle)
    private let shimmer = CAGradientLayer()
    private var isPlaying = false

    /// 31 столбик 4 pt, первые 12 — акцентные (рисунок макета «Эфир»).
    private static let waveStyle = WaveView.Style(
        heights: [8, 20, 12, 24, 10, 18, 6, 22, 12, 16, 8, 20, 10, 18, 8, 22, 12, 16, 6, 20, 10, 18, 8, 24, 12, 16, 8, 20, 10, 16, 6],
        barWidth: 4, accentCount: 12, accent: Palette.accent, rest: Palette.surfaceHigh
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Palette.surfaceRaised
        contentView.layer.cornerRadius = 24
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = Palette.track.cgColor

        // Переливающийся фон при воспроизведении; скругление обрезает сам слой.
        shimmer.colors = [
            Palette.surfaceRaised, Palette.surfaceHigh, Palette.accent.withAlphaComponent(0.15), Palette.surfaceHigh, Palette.surfaceRaised,
        ].map(\.cgColor)
        shimmer.cornerRadius = 24
        shimmer.masksToBounds = true
        shimmer.isHidden = true
        contentView.layer.insertSublayer(shimmer, at: 0)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(updateShimmer), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        // Core Animation снимает анимации при уходе в фон.
        center.addObserver(self, selector: #selector(updateShimmer), name: UIApplication.willEnterForegroundNotification, object: nil)

        let dot = UIView()
        dot.backgroundColor = Palette.accent
        dot.layer.cornerRadius = 2.75
        let captionFont = Typography.text(13, .bold)
        let caption = UILabel()
        caption.attributedText = NSAttributedString(string: "СЕЙЧАС ИГРАЕТ", attributes: [
            .font: captionFont,
            .foregroundColor: Palette.accent,
            .kern: 0.2,
        ])
        let iconBox = UIView()
        iconBox.backgroundColor = Palette.surfaceHigh
        iconBox.layer.cornerRadius = 16
        let icon = UIImageView(image: Icon.image("audio-lines"))
        icon.tintColor = Palette.textPrimary
        let nameFont = Typography.display(18)
        nameLabel.font = nameFont
        nameLabel.textColor = Palette.textPrimary
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        let subtitleFont = Typography.text(14)
        subtitleLabel.font = subtitleFont
        button.backgroundColor = Palette.accent
        button.layer.cornerRadius = 26
        button.addAction(UIAction { [weak self] _ in self?.onPlayPause?() }, for: .touchUpInside)

        [dot, caption, iconBox, nameLabel, subtitleLabel, button, wave].forEach(contentView.addSubview)
        iconBox.addSubview(icon)
        dot.snp.makeConstraints {
            $0.size.equalTo(5.5)
            $0.centerX.equalTo(contentView.snp.leading).offset(24.5)
            $0.centerY.equalTo(contentView.snp.top).offset(28.5)
        }
        caption.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(33)
            $0.firstBaseline.equalTo(dot.snp.centerY).offset(captionFont.capHeight / 2)
        }
        iconBox.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(21)
            $0.top.equalToSuperview().offset(49.5)
            $0.size.equalTo(64)
        }
        icon.snp.makeConstraints { $0.center.equalToSuperview() }
        button.snp.makeConstraints {
            $0.size.equalTo(52)
            $0.trailing.equalToSuperview().inset(21)
            $0.centerY.equalTo(iconBox)
        }
        nameLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(99.5)
            $0.trailing.lessThanOrEqualTo(button.snp.leading).offset(-8)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(64.5 + nameFont.capHeight)
        }
        subtitleLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(100)
            $0.trailing.lessThanOrEqualTo(button.snp.leading).offset(-8)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(89.5 + subtitleFont.capHeight)
        }
        // Столбики с 21 pt до 27.5 pt от правого края, середина в 141.25 pt от верха.
        wave.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(21)
            $0.trailing.equalToSuperview().inset(27.5)
            $0.centerY.equalTo(contentView.snp.top).offset(141.25)
            $0.height.equalTo(Self.waveStyle.height)
        }
        // VoiceOver: карточка — кнопка «открыть плеер», play/pause — отдельный элемент.
        isAccessibilityElement = false
        nameLabel.isAccessibilityElement = false
        subtitleLabel.isAccessibilityElement = false
        caption.isAccessibilityElement = false
        contentView.accessibilityElements = [summary, button]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private lazy var summary: UIAccessibilityElement = {
        let element = UIAccessibilityElement(accessibilityContainer: contentView)
        element.accessibilityTraits = .button
        element.accessibilityHint = "Открыть плеер"
        return element
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        summary.accessibilityFrameInContainerSpace = contentView.bounds
        shimmer.frame = contentView.bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateShimmer()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isPlaying = false
        updateShimmer()
    }

    @objc private func updateShimmer() {
        let animates = isPlaying && window != nil && !UIAccessibility.isReduceMotionEnabled
        shimmer.isHidden = !animates
        shimmer.removeAnimation(forKey: "shimmer")
        guard animates else { return }
        // Градиент вдвое шире карточки, сдвигается слева направо и обратно.
        shimmer.startPoint = CGPoint(x: -1, y: 0)
        shimmer.endPoint = CGPoint(x: 0, y: 0.4)
        let group = CAAnimationGroup()
        let start = CABasicAnimation(keyPath: "startPoint")
        start.toValue = CGPoint(x: 0, y: 0)
        let end = CABasicAnimation(keyPath: "endPoint")
        end.toValue = CGPoint(x: 1, y: 0.4)
        group.animations = [start, end]
        group.duration = 5
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmer.add(group, forKey: "shimmer")
    }

    func configure(_ card: RadioState.NowPlaying) {
        nameLabel.text = card.name
        subtitleLabel.text = card.subtitle
        subtitleLabel.textColor = card.isError ? Palette.destructive : Palette.textSecondary
        button.configure(card.button, label: card.actionLabel)
        wave.isAnimating = card.isAnimating
        isPlaying = card.isAnimating
        updateShimmer()
        summary.accessibilityLabel = "Сейчас играет: \(card.name)"
        summary.accessibilityValue = card.subtitle
    }
}
