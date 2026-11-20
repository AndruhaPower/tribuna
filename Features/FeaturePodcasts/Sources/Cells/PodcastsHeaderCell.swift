import CoreUI
import SnapKit
import UIKit

/// Шапка вкладки: заголовок «Подкасты» и переключатель «Подборка» / «Подписки N» / «Загрузки». Отступы — от верха безопасной зоны,
/// замер макета: переключатель 44 pt с 61.5 pt, подложка `surface` со скруглением 14, выбранный сегмент `surfaceHigh` с полем 4 pt
/// и скруглением 10; три сегмента по 111 pt с промежутком 4.5 pt.
final class PodcastsHeaderCell: UICollectionViewCell {
    static let height: CGFloat = 105.5

    var onSelect: ((PodcastsState.Segment) -> Void)?

    private var segments: [PodcastsState.Segment: SegmentButton] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        let titleFont = Typography.screenTitle
        let title = UILabel()
        title.font = titleFont
        title.textColor = Palette.textPrimary
        title.text = "Подкасты"
        title.accessibilityTraits = .header

        let box = UIView()
        box.backgroundColor = Palette.surface
        box.layer.cornerRadius = 14
        let stack = UIStackView()
        stack.spacing = 4.5
        stack.distribution = .fillEqually
        for (segment, text) in [(PodcastsState.Segment.catalog, "Подборка"), (.subscriptions, "Подписки"), (.downloads, "Загрузки")] {
            let button = SegmentButton(title: text)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(segment) }, for: .touchUpInside)
            segments[segment] = button
            stack.addArrangedSubview(button)
        }

        [title, box].forEach(contentView.addSubview)
        box.addSubview(stack)
        title.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(20)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(15.5 + titleFont.capHeight)
        }
        box.snp.makeConstraints {
            $0.top.equalToSuperview().offset(61.5)
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.height.equalTo(44)
        }
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(4) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(selected: PodcastsState.Segment, badge: Int?) {
        for (segment, button) in segments {
            button.configure(isSelected: segment == selected, badge: segment == .subscriptions ? badge : nil)
        }
    }
}

/// Сегмент: текст и белый кружок-бейдж 18 pt с числом в 7.5 pt справа.
private final class SegmentButton: UIControl {
    private let titleLabel = UILabel()
    private let badge = UILabel()
    private let text: String

    init(title: String) {
        text = title
        super.init(frame: .zero)
        layer.cornerRadius = 10
        titleLabel.text = title
        badge.font = Typography.text(12, .bold)
        badge.textColor = Palette.background
        badge.backgroundColor = Palette.textPrimary
        badge.textAlignment = .center
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        let stack = UIStackView(arrangedSubviews: [titleLabel, badge])
        stack.spacing = 7.5
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        stack.snp.makeConstraints { $0.center.equalToSuperview() }
        badge.snp.makeConstraints {
            $0.height.equalTo(18)
            $0.width.greaterThanOrEqualTo(18)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    func configure(isSelected: Bool, badge count: Int?) {
        backgroundColor = isSelected ? Palette.surfaceHigh : .clear
        titleLabel.font = Typography.text(15, isSelected ? .semibold : .medium)
        titleLabel.textColor = isSelected ? Palette.textPrimary : Palette.textSecondary
        badge.isHidden = count == nil
        badge.text = count.map(String.init)
        accessibilityLabel = text
        accessibilityValue = count.map { PodcastsFormatter.newLabel($0) }
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
