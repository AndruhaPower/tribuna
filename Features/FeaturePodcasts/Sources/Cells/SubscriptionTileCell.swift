import CoreUI
import SnapKit
import UIKit

/// Плитка подписки: обложка 96 pt и «2 новых» под ней; пока обложки нет — плашка с названием (Unbounded), как в макете.
/// На настоящих обложках название уже нарисовано, а надпись поверх картинки не читается, — поэтому с обложкой она скрыта. Замер макета:
/// базовая линия названия в 82 pt от верха плитки, подписи — в 115 pt; до заголовка «Новые выпуски» — 124 pt.
final class SubscriptionTileCell: UICollectionViewCell {
    static let height: CGFloat = 124
    private static let artworkHeight: CGFloat = 96

    private let artwork = RemoteImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.backgroundColor = Palette.surfaceRaised
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 16
        titleLabel.font = Typography.display(16)
        titleLabel.textColor = Palette.textPrimary
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        subtitleLabel.font = Typography.text(13)
        subtitleLabel.textColor = Palette.textSecondary

        [artwork, titleLabel, subtitleLabel].forEach(contentView.addSubview)
        artwork.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
            $0.height.equalTo(Self.artworkHeight)
        }
        titleLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(10)
            $0.lastBaseline.equalTo(contentView.snp.top).offset(82)
        }
        subtitleLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.firstBaseline.equalTo(contentView.snp.top).offset(115)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(_ tile: SubscriptionTile) {
        if artwork.url != tile.artworkURL {
            titleLabel.isHidden = false
            artwork.setImage(url: tile.artworkURL, maxPixelSize: Self.artworkHeight * 3) { [weak self] in self?.titleLabel.isHidden = true }
        }
        titleLabel.text = tile.title
        subtitleLabel.text = tile.subtitle
        accessibilityLabel = [tile.title, tile.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
