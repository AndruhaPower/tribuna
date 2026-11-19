import CoreUI
import SnapKit
import UIKit

/// Плоский таб-бар из макета (D19). Системный в iOS 26 рисуется плавающим «стеклом».
final class TabBarView: UIView {
    struct Item {
        let title: String
        /// Имя картинки в Assets.xcassets (иконки Lucide, линия 2 pt).
        let icon: String
    }

    /// Высота без нижней безопасной зоны; столько же добавляем вкладкам в additionalSafeAreaInsets.
    static let contentHeight: CGFloat = 49

    var onSelect: ((Int) -> Void)?
    var selectedIndex = 0 {
        didSet { updateSelection() }
    }

    private var itemViews: [TabBarItemView] = []

    init(items: [Item]) {
        super.init(frame: .zero)
        backgroundColor = Palette.tabBar

        let border = UIView()
        border.backgroundColor = Palette.tabBarBorder
        addSubview(border)
        border.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
            $0.height.equalTo(1)
        }

        itemViews = items.enumerated().map { index, item in
            let view = TabBarItemView(item: item)
            view.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            return view
        }
        let stack = UIStackView(arrangedSubviews: itemViews)
        stack.distribution = .fillEqually
        addSubview(stack)
        stack.snp.makeConstraints {
            $0.top.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(12)
            $0.height.equalTo(Self.contentHeight)
            $0.bottom.equalTo(safeAreaLayoutGuide)
        }
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private func updateSelection() {
        for (index, view) in itemViews.enumerated() {
            view.isSelected = index == selectedIndex
        }
    }
}

/// Вкладка: иконка 22 pt с верхом на 9.5 pt ниже края бара (масштаб каждой иконки подогнан viewBox в SVG), базовая линия подписи на 47.7 pt — замерено по макету.
private final class TabBarItemView: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override var isSelected: Bool {
        didSet { update() }
    }

    init(item: TabBarView.Item) {
        super.init(frame: .zero)
        iconView.image = UIImage(named: item.icon)
        iconView.contentMode = .scaleAspectFit
        titleLabel.text = item.title
        titleLabel.textAlignment = .center

        addSubview(iconView)
        addSubview(titleLabel)
        iconView.snp.makeConstraints {
            $0.top.equalToSuperview().offset(9.5)
            $0.centerX.equalToSuperview()
            $0.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.firstBaseline.equalTo(snp.top).offset(47.7)
        }

        isAccessibilityElement = true
        accessibilityLabel = item.title
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private func update() {
        let color = isSelected ? Palette.textPrimary : Palette.textSecondary
        iconView.tintColor = color
        titleLabel.textColor = color
        titleLabel.font = Typography.text(11, isSelected ? .semibold : .medium)
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
