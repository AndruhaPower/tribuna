import CoreUI
import SnapKit
import UIKit

/// Строка списка из макета «Подкасты»: обложка 52 pt, подпись сверху (у выпуска), название, вторая строка,
/// полоска загрузки и кнопки-пилюли под текстом. Высота по содержимому: без кнопки 85 pt, с кнопкой 130 pt, с полоской 100 pt (замер),
/// длинное название — в две строки. Ячейка списка (`UICollectionViewListCell`) — ради свайпа в «Загрузках».
final class ListRowCell: UICollectionViewListCell {
    struct Content {
        let artworkURL: URL
        /// Подпись над названием («● Новый · Вне игры»); nil — без неё, название поднимается.
        let caption: String?
        let isCaptionActive: Bool
        let title: String
        let subtitle: String
        let button: (title: String, icon: String?, style: PillButton.Style)?
        /// Контурная «Скачать» справа от кнопки.
        var showsDownloadButton = false
        /// VoiceOver для «Скачать»; nil — «Скачать».
        var downloadButtonAccessibilityLabel: String?
        /// Полоска загрузки под текстом; nil — без неё.
        var progress: Double?
        let accessibilityLabel: String
        /// VoiceOver для пилюли; nil — по её названию.
        var buttonAccessibilityLabel: String?
    }

    static let estimatedHeight: CGFloat = 85
    /// Обложка 52 pt, в макете отрисована 104 px; берём с запасом на чёткость.
    private static let artworkPixels: CGFloat = 52 * 3

    var onButton: (() -> Void)?
    var onDownload: (() -> Void)?

    private let artwork = RemoteImageView()
    private let captionLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let button = PillButton()
    private let downloadButton = PillButton()
    private let progressBar = ProgressBar()
    private let separator = UIView()
    private var titleBelowCaption: Constraint?
    private var titleAtTop: Constraint?
    private var separatorBelowButton: Constraint?
    private var separatorBelowBar: Constraint?
    private var buttonBelowSubtitle: Constraint?
    private var buttonBelowBar: Constraint?

    private let captionFont = Typography.text(13, .medium)
    private let titleFont = Typography.text(17, .semibold)
    private let subtitleFont = Typography.text(13)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        artwork.backgroundColor = Palette.surfaceRaised
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 12
        captionLabel.font = captionFont
        titleLabel.font = titleFont
        titleLabel.textColor = Palette.textPrimary
        titleLabel.numberOfLines = 2
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = Palette.textSecondary
        button.addAction(UIAction { [weak self] _ in self?.onButton?() }, for: .touchUpInside)
        downloadButton.configure(title: "Скачать", icon: "download", style: .outline)
        downloadButton.addAction(UIAction { [weak self] _ in self?.onDownload?() }, for: .touchUpInside)
        separator.backgroundColor = Palette.separator

        [artwork, captionLabel, titleLabel, subtitleLabel, progressBar, button, downloadButton, separator].forEach(contentView.addSubview)
        // Замер от верха строки (низа разделителя): обложка с 16 pt; базовые линии подписи 27, названия 48.5, второй строки 67.5;
        // кнопка в 14 pt под второй строкой, разделитель в 11.5 pt под кнопкой или в 16 pt под обложкой.
        artwork.snp.makeConstraints {
            $0.leading.equalToSuperview()
            $0.top.equalToSuperview().offset(16)
            $0.size.equalTo(52)
        }
        captionLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(65)
            $0.trailing.lessThanOrEqualToSuperview()
            $0.firstBaseline.equalTo(contentView.snp.top).offset(27)
        }
        titleLabel.snp.makeConstraints {
            $0.leading.equalTo(captionLabel)
            $0.trailing.lessThanOrEqualToSuperview()
            titleBelowCaption = $0.firstBaseline.equalTo(contentView.snp.top).offset(48.5).constraint
            // Без подписи верх заглавных — на 2 pt ниже верха обложки, как у подписи.
            titleAtTop = $0.firstBaseline.equalTo(contentView.snp.top).offset(18 + titleFont.capHeight).constraint
        }
        subtitleLabel.snp.makeConstraints {
            $0.leading.equalTo(captionLabel)
            $0.trailing.lessThanOrEqualToSuperview()
            $0.firstBaseline.equalTo(titleLabel.snp.lastBaseline).offset(19)
        }
        // Полоска 6 pt на всю ширину текста: верх в 13.5 pt под второй строкой, разделитель в 12 pt под ней.
        progressBar.snp.makeConstraints {
            $0.leading.equalTo(captionLabel).offset(-1)
            $0.trailing.equalToSuperview()
            $0.top.equalTo(subtitleLabel.snp.lastBaseline).offset(13.5)
            $0.height.equalTo(6)
        }
        button.snp.makeConstraints {
            $0.leading.equalTo(captionLabel)
            buttonBelowSubtitle = $0.top.equalTo(subtitleLabel.snp.lastBaseline).offset(14).constraint
            buttonBelowBar = $0.top.equalTo(progressBar.snp.bottom).offset(14).constraint
            $0.height.equalTo(PillButton.height)
        }
        // «Скачать» в 8 pt справа от «Слушать».
        downloadButton.snp.makeConstraints {
            $0.leading.equalTo(button.snp.trailing).offset(8)
            $0.top.height.equalTo(button)
        }
        separator.snp.makeConstraints {
            $0.leading.trailing.bottom.equalToSuperview()
            $0.height.equalTo(1)
            $0.top.greaterThanOrEqualTo(artwork.snp.bottom).offset(16)
            $0.top.greaterThanOrEqualTo(subtitleLabel.snp.lastBaseline).offset(16.5)
            separatorBelowButton = $0.top.equalTo(button.snp.bottom).offset(11.5).constraint
            separatorBelowBar = $0.top.greaterThanOrEqualTo(progressBar.snp.bottom).offset(12).constraint
            // Без кнопки — как можно выше.
            $0.top.equalTo(artwork.snp.bottom).offset(16).priority(.low)
        }
        titleAtTop?.deactivate()
        buttonBelowBar?.deactivate()
        // VoiceOver: строка — один элемент-кнопка, кнопка-пилюля — отдельный.
        isAccessibilityElement = false
        contentView.isAccessibilityElement = true
        contentView.accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override var accessibilityElements: [Any]? {
        get { [contentView, button, downloadButton].filter { !$0.isHidden } }
        set {}
    }

    /// Точка «●» в SF 13 вдвое крупнее макета (5.5 pt) — рисуем её шрифтом 8 pt, приподнятой к середине строчных.
    private static func caption(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        if text.hasPrefix("●") {
            result.addAttributes([.font: Typography.text(8), .baselineOffset: 1], range: NSRange(location: 0, length: 1))
        }
        return result
    }

    func configure(_ content: Content, isLast: Bool) {
        if artwork.url != content.artworkURL { artwork.setImage(url: content.artworkURL, maxPixelSize: Self.artworkPixels) }
        captionLabel.isHidden = content.caption == nil
        captionLabel.attributedText = content.caption.map(Self.caption)
        captionLabel.textColor = content.isCaptionActive ? Palette.textPrimary : Palette.textSecondary
        if content.caption == nil {
            titleBelowCaption?.deactivate()
            titleAtTop?.activate()
        } else {
            titleAtTop?.deactivate()
            titleBelowCaption?.activate()
        }
        titleLabel.text = content.title
        subtitleLabel.text = content.subtitle
        if let value = content.button {
            button.configure(title: value.title, icon: value.icon, style: value.style)
            button.accessibilityLabel = content.buttonAccessibilityLabel ?? value.title
            button.isHidden = false
            separatorBelowButton?.activate()
        } else {
            button.isHidden = true
            separatorBelowButton?.deactivate()
        }
        downloadButton.isHidden = !content.showsDownloadButton
        downloadButton.accessibilityLabel = content.downloadButtonAccessibilityLabel ?? "Скачать"
        progressBar.isHidden = content.progress == nil
        progressBar.progress = content.progress ?? 0
        if content.progress == nil {
            separatorBelowBar?.deactivate()
            buttonBelowBar?.deactivate()
            buttonBelowSubtitle?.activate()
        } else {
            separatorBelowBar?.activate()
            buttonBelowSubtitle?.deactivate()
            buttonBelowBar?.activate()
        }
        separator.isHidden = isLast
        contentView.accessibilityLabel = content.accessibilityLabel
        contentView.accessibilityValue = content.progress.map { "\(Int(($0 * 100).rounded())) %" }
    }
}

/// Полоска загрузки: дорожка `track`, заполнение `textPrimary`, скругление по высоте (макет).
private final class ProgressBar: UIView {
    private let fill = UIView()

    var progress: Double = 0 {
        didSet { setNeedsLayout() }
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = Palette.track
        fill.backgroundColor = Palette.textPrimary
        clipsToBounds = true
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * min(max(progress, 0), 1), height: bounds.height)
        fill.layer.cornerRadius = bounds.height / 2
    }
}
