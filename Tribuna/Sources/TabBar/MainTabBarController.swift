import CoreUI
import FeaturePlayer
import SnapKit
import UIKit

/// Контейнер вкладок со своим таб-баром и мини-плеером над ним (D15, D19, D25).
/// Пока мини-плеер показан, вкладки получают отступ снизу и на него — последний элемент списка не перекрыт.
final class MainTabBarController: UIViewController {
    struct Tab {
        let item: TabBarView.Item
        let root: UIViewController
    }

    private let navigationControllers: [UINavigationController]
    private let tabBar: TabBarView
    private let miniPlayer: MiniPlayerView
    private var selectedIndex: Int?

    /// Мини-плеер — карточка с полями 12 pt по бокам и 12 pt над таб-баром (замер макета «Сегодня»).
    private static let miniPlayerGap: CGFloat = 12

    private var bottomInset: CGFloat {
        TabBarView.contentHeight + (miniPlayer.isVisible ? MiniPlayerView.height + Self.miniPlayerGap : 0)
    }

    init(tabs: [Tab], miniPlayer: MiniPlayerView) {
        navigationControllers = tabs.map { UINavigationController(rootViewController: $0.root) }
        tabBar = TabBarView(items: tabs.map(\.item))
        self.miniPlayer = miniPlayer
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
        view.addSubview(miniPlayer)
        miniPlayer.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(Self.miniPlayerGap)
            $0.bottom.equalTo(tabBar.snp.top).offset(-Self.miniPlayerGap)
        }
        select(0)
        miniPlayer.onVisibilityChange = { [weak self] visible in
            self?.miniPlayerVisibilityChanged(visible, animated: self?.view.window != nil)
        }
    }

    private func miniPlayerVisibilityChanged(_ visible: Bool, animated: Bool) {
        miniPlayer.isHidden = false
        UIView.animate(withDuration: animated ? 0.25 : 0, delay: 0, options: [.beginFromCurrentState]) { [self] in
            miniPlayer.alpha = visible ? 1 : 0
            miniPlayer.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 16)
            for navigation in navigationControllers {
                navigation.additionalSafeAreaInsets.bottom = bottomInset
            }
            view.layoutIfNeeded()
        } completion: { [self] _ in
            // За время анимации мини-плеер могли снова показать.
            if !miniPlayer.isVisible { miniPlayer.isHidden = true }
        }
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
        target.additionalSafeAreaInsets.bottom = bottomInset
        target.didMove(toParent: self)
        selectedIndex = index
        tabBar.selectedIndex = index
    }
}
