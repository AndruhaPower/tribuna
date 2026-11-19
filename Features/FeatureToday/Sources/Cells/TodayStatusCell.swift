import CoreUI
import SnapKit
import UIKit

/// Загрузка, «Матчей нет» или ошибка с «Повторить».
final class TodayStatusCell: UICollectionViewCell {
    static let height: CGFloat = 200

    var onRetry: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.color = Palette.textSecondary
        messageLabel.font = Typography.text(15)
        messageLabel.textColor = Palette.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        retryButton.setTitle("Повторить", for: .normal)
        retryButton.setTitleColor(Palette.accent, for: .normal)
        retryButton.titleLabel?.font = Typography.text(15, .semibold)
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// `message == nil` — загрузка.
    func configure(message: String?, showsRetry: Bool) {
        if message == nil { spinner.startAnimating() } else { spinner.stopAnimating() }
        spinner.isHidden = message != nil
        messageLabel.text = message
        messageLabel.isHidden = message == nil
        retryButton.isHidden = !showsRetry
    }
}
