import Combine
import CoreUI
import UIKit

/// Лист входа (D21 — координатор, когда экранов больше одного): навигация повторяет `state.path` модели.
/// Новый шаг модели — push; «назад» навигации — `didPop`; итог — закрыть лист и `completion`.
final class SignInCoordinator: UINavigationController, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private let model: SignInModel
    private var cancellables: Set<AnyCancellable> = []

    init(model: SignInModel, completion: @escaping @MainActor (Bool) -> Void) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        presentationController?.delegate = self
        model.onFinish = { [weak self] signedIn in
            guard let self, presentingViewController != nil else { return completion(signedIn) }
            dismiss(animated: true) { completion(signedIn) }
        }
        setViewControllers(model.state.path.map(screen), animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.tintColor = Palette.textPrimary
        view.backgroundColor = Palette.background
        model.$state.map(\.path).removeDuplicates()
            .sink { [weak self] in self?.follow($0) }
            .store(in: &cancellables)
        // Пока идёт запрос, лист не закрыть и назад не уйти: итог запроса не должен потеряться.
        model.$state.map(\.isLoading).removeDuplicates()
            .sink { [weak self] in self?.lock($0) }
            .store(in: &cancellables)
    }

    private func lock(_ isLoading: Bool) {
        isModalInPresentation = isLoading
        interactivePopGestureRecognizer?.isEnabled = !isLoading
        for controller in viewControllers {
            controller.navigationItem.setHidesBackButton(isLoading, animated: false)
            controller.navigationItem.rightBarButtonItem?.isEnabled = !isLoading
        }
    }

    private func follow(_ path: [SignInStep]) {
        guard path.count > viewControllers.count, let step = path.last else { return }
        view.endEditing(true)
        pushViewController(screen(step), animated: true)
    }

    private func screen(_ step: SignInStep) -> UIViewController {
        let controller: UIViewController = step == .motivation ? MotivationViewController(model: model) : FormViewController(model: model, step: step)
        controller.navigationItem.backButtonDisplayMode = .minimal
        // На мотивации есть «Не сейчас»; на остальных шагах — «Закрыть» (и для VoiceOver, где жест вниз неочевиден).
        if step != .motivation {
            let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.model.dismissed() })
            close.accessibilityLabel = "Закрыть"
            controller.navigationItem.rightBarButtonItem = close
        }
        return controller
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        model.didPop(toDepth: viewControllers.count)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        model.dismissed()
    }
}
