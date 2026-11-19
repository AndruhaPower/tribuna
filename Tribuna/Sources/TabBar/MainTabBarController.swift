import CoreUI
import SnapKit
import UIKit

/// Контейнер вкладок со своим таб-баром. Сюда же над таб-баром ляжет мини-плеер (D15).
final class MainTabBarController: UIViewController {
    struct Tab {
        let item: TabBarView.Item
        let root: UIViewController
    }

    private let navigationControllers: [UINavigationController]
    private let tabBar: TabBarView
    private var selectedIndex: Int?

    init(tabs: [Tab]) {
        navigationControllers = tabs.map { UINavigationController(rootViewController: $0.root) }
        tabBar = TabBarView(items: tabs.map(\.item))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        view.addSubview(tabBar)
        tabBar.snp.makeConstraints { $0.leading.trailing.bottom.equalToSuperview() }
        tabBar.onSelect = { [weak self] in self?.select($0) }
        select(0)
    }

    func select(_ index: Int) {
        let target = navigationControllers[index]
        // Повторный тап по активной вкладке — к её корню, как в системном таб-баре.
        guard index != selectedIndex else {
            target.popToRootViewController(animated: true)
            return
        }
        if let selectedIndex {
            let current = navigationControllers[selectedIndex]
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(target)
        view.insertSubview(target.view, belowSubview: tabBar)
        target.view.snp.makeConstraints { $0.edges.equalToSuperview() }
        target.additionalSafeAreaInsets.bottom = TabBarView.contentHeight
        target.didMove(toParent: self)
        selectedIndex = index
        tabBar.selectedIndex = index
    }
}
