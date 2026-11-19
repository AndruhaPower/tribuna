import CoreUI
import SnapKit
import UIKit

/// Плоский таб-бар из макета (D19). Системный в iOS 26 рисуется плавающим «стеклом».
final class TabBarView: UIView {
    struct Item {
        let title: String
        let symbol: String
    }

    /// Высота без нижней безопасной зоны; столько же добавляем вкладкам в additionalSafeAreaInsets.
    static let contentHeight: CGFloat = 49

    var onSelect: ((Int) -> Void)?
    var selectedIndex = 0 {
        didSet { updateButtons() }
    }

    private let items: [Item]
    private var buttons: [UIButton] = []

    init(items: [Item]) {
        self.items = items
        super.init(frame: .zero)
        backgroundColor = Palette.tabBar

        let border = UIView()
        border.backgroundColor = Palette.tabBarBorder
        addSubview(border)
        border.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
            $0.height.equalTo(1)
        }

        buttons = items.indices.map { index in
            let button = UIButton(configuration: .plain())
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            return button
        }
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.distribution = .fillEqually
        addSubview(stack)
        stack.snp.makeConstraints {
            $0.top.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(12)
            $0.height.equalTo(Self.contentHeight)
            $0.bottom.equalTo(safeAreaLayoutGuide)
        }
        updateButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private func updateButtons() {
        for (index, button) in buttons.enumerated() {
            let isSelected = index == selectedIndex
            let color = isSelected ? Palette.textPrimary : Palette.textSecondary
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: items[index].symbol)
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
            config.imagePlacement = .top
            config.imagePadding = 4
            config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 0)
            config.baseForegroundColor = color
            var title = AttributedString(items[index].title)
            title.font = Typography.text(12, isSelected ? .semibold : .medium)
            title.foregroundColor = color
            config.attributedTitle = title
            button.configuration = config
            button.contentVerticalAlignment = .top
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }
}
