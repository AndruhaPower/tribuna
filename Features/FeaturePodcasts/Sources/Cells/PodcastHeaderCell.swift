import CoreUI
import SnapKit
import UIKit

/// Шапка экрана подкаста (макета нет — язык макета «Подкасты»): обложка 120 pt, название Unbounded, автор,
/// «Подписаться» (акцентная пилюля) / «Вы подписаны» (контурная). Высота по содержимому.
final class PodcastHeaderCell: UICollectionViewCell {
    static let estimatedHeight: CGFloat = 200
    private static let artworkSize: CGFloat = 120

    var onSubscribe: (() -> Void)?

    private let artwork = RemoteImageView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let button = PillButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.backgroundColor = Palette.surfaceRaised
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 16
        titleLabel.font = Typography.display(20)
        titleLabel.textColor = Palette.textPrimary
        titleLabel.numberOfLines = 4
        titleLabel.accessibilityTraits = .header
        authorLabel.font = Typography.text(15)
        authorLabel.textColor = Palette.textSecondary
        authorLabel.numberOfLines = 2
        button.addAction(UIAction { [weak self] _ in self?.onSubscribe?() }, for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [titleLabel, authorLabel])
        text.axis = .vertical
        text.spacing = 6
        [artwork, text, button].forEach(contentView.addSubview)
        artwork.snp.makeConstraints {
            $0.top.leading.equalToSuperview()
            $0.size.equalTo(Self.artworkSize)
        }
        text.snp.makeConstraints {
            $0.top.equalTo(artwork)
            $0.leading.equalTo(artwork.snp.trailing).offset(16)
            $0.trailing.equalToSuperview()
        }
        button.snp.makeConstraints {
            $0.leading.equalToSuperview()
            $0.top.greaterThanOrEqualTo(artwork.snp.bottom).offset(16)
            $0.top.greaterThanOrEqualTo(text.snp.bottom).offset(16)
            $0.top.equalTo(artwork.snp.bottom).offset(16).priority(.low)
            $0.height.equalTo(PillButton.height)
            $0.bottom.equalToSuperview().inset(8)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ header: PodcastState.Header) {
        if artwork.url != header.artworkURL { artwork.setImage(url: header.artworkURL, maxPixelSize: Self.artworkSize * 3) }
        titleLabel.text = header.title
        authorLabel.text = header.author
        button.configure(title: header.isSubscribed ? "Вы подписаны" : "Подписаться", icon: nil, style: header.isSubscribed ? .outline : .accent)
    }
}
