import Combine
import CoreUI
import SnapKit
import UIKit

/// Профиль по макету «Профиль» без карточки аккаунта и уведомлений: плитки-счётчики сразу под заголовком, секция «ЗАГРУЗКИ».
/// Отступы — замер макета от верха безопасной зоны и от низа плиток.
final class ProfileViewController: UIViewController {
    private let viewModel: ProfileViewModel
    private let bookmarksTile = CounterTile(title: "Мои закладки")
    private let subscriptionsTile = CounterTile(title: "Мои подписки")
    private let wifiSwitch = UISwitch()
    private let usageLabel = UILabel()
    private let usageTrack = UIView()
    private let usageFill = UIView()
    private var usageFillWidth: Constraint?
    private let usageRow = UIView()
    private let clearButton = UIButton(type: .system)
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let safe = view.safeAreaLayoutGuide

        let titleFont = Typography.screenTitle
        let titleLabel = UILabel()
        titleLabel.font = titleFont
        titleLabel.textColor = Palette.textPrimary
        titleLabel.text = "Профиль"
        titleLabel.accessibilityTraits = .header

        let sectionFont = Typography.text(14, .semibold)
        let section = UILabel()
        section.attributedText = NSAttributedString(string: "ЗАГРУЗКИ", attributes: [
            .font: sectionFont, .foregroundColor: Palette.textSecondary, .kern: 0.3,
        ])
        section.accessibilityTraits = .header

        let card = UIView()
        card.backgroundColor = Palette.surface
        card.layer.cornerRadius = 18

        // Только по Wi-Fi.
        let wifiRow = UIView()
        let wifiLabel = rowLabel("Только по Wi-Fi")
        wifiLabel.isAccessibilityElement = false
        wifiSwitch.onTintColor = Palette.switchOn
        wifiSwitch.thumbTintColor = Palette.background
        wifiSwitch.accessibilityLabel = "Только по Wi-Fi"
        wifiSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.didToggleWifiOnly(wifiSwitch.isOn)
        }, for: .valueChanged)

        // Занято.
        let usageTitle = rowLabel("Занято")
        usageLabel.font = Typography.text(16)
        usageLabel.textColor = Palette.textSecondary
        usageLabel.textAlignment = .right
        usageTrack.backgroundColor = Palette.track
        usageTrack.layer.cornerRadius = 3
        usageTrack.clipsToBounds = true
        usageFill.backgroundColor = Palette.textSecondary
        usageRow.isAccessibilityElement = true

        // Очистить загрузки.
        var clear = UIButton.Configuration.plain()
        clear.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        clearButton.configuration = clear
        clearButton.contentHorizontalAlignment = .leading
        clearButton.configurationUpdateHandler = { button in
            button.configuration?.attributedTitle = AttributedString("Очистить загрузки", attributes: AttributeContainer([
                .font: Typography.text(16, .semibold),
                .foregroundColor: button.isEnabled ? Palette.destructive : Palette.destructive.withAlphaComponent(0.4),
            ]))
        }
        clearButton.addAction(UIAction { [weak self] _ in self?.confirmClear() }, for: .touchUpInside)

        [titleLabel, bookmarksTile, subscriptionsTile, section, card].forEach(view.addSubview)
        [wifiRow, usageRow, clearButton].forEach(card.addSubview)
        [wifiLabel, wifiSwitch].forEach(wifiRow.addSubview)
        [usageTitle, usageLabel, usageTrack].forEach(usageRow.addSubview)
        usageTrack.addSubview(usageFill)
        let separators = [UIView(), UIView()]
        separators.forEach {
            $0.backgroundColor = Palette.separator
            card.addSubview($0)
        }

        titleLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(20)
            $0.firstBaseline.equalTo(safe.snp.top).offset(15.5 + titleFont.capHeight)
        }
        bookmarksTile.snp.makeConstraints {
            $0.top.equalTo(safe).offset(63)
            $0.leading.equalToSuperview().offset(20)
            $0.height.equalTo(79)
        }
        subscriptionsTile.snp.makeConstraints {
            $0.top.bottom.width.equalTo(bookmarksTile)
            $0.leading.equalTo(bookmarksTile.snp.trailing).offset(10)
            $0.trailing.equalToSuperview().inset(20)
        }
        section.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(20)
            $0.lastBaseline.equalTo(bookmarksTile.snp.bottom).offset(32.5)
        }
        card.snp.makeConstraints {
            $0.top.equalTo(bookmarksTile.snp.bottom).offset(44)
            $0.leading.trailing.equalToSuperview().inset(20)
        }
        wifiRow.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
            $0.height.equalTo(58)
        }
        separators[0].snp.makeConstraints {
            $0.top.equalTo(wifiRow.snp.bottom)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(1)
        }
        usageRow.snp.makeConstraints {
            $0.top.equalTo(separators[0].snp.bottom)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(60)
        }
        separators[1].snp.makeConstraints {
            $0.top.equalTo(usageRow.snp.bottom)
            $0.leading.trailing.equalToSuperview()
            $0.height.equalTo(1)
        }
        clearButton.snp.makeConstraints {
            $0.top.equalTo(separators[1].snp.bottom)
            $0.leading.trailing.bottom.equalToSuperview()
            $0.height.equalTo(48)
        }
        wifiLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(16)
            $0.centerY.equalToSuperview()
        }
        wifiSwitch.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
        }
        usageTitle.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(16)
            $0.firstBaseline.equalTo(usageRow.snp.top).offset(28.5)
        }
        usageLabel.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(16)
            $0.leading.greaterThanOrEqualTo(usageTitle.snp.trailing).offset(8)
            $0.firstBaseline.equalTo(usageTitle)
        }
        usageTrack.snp.makeConstraints {
            $0.top.equalToSuperview().offset(40)
            $0.leading.trailing.equalToSuperview().inset(16)
            $0.height.equalTo(6)
        }
        usageFill.snp.makeConstraints {
            $0.top.bottom.leading.equalToSuperview()
            usageFillWidth = $0.width.equalToSuperview().multipliedBy(0).constraint
        }

        viewModel.$state.sink { [weak self] in self?.render($0) }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.viewModel.didEnterForeground() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func rowLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.text(16, .medium)
        label.textColor = Palette.textPrimary
        return label
    }

    private func render(_ state: ProfileState) {
        bookmarksTile.value = state.bookmarks
        subscriptionsTile.value = state.subscriptions
        if wifiSwitch.isOn != state.wifiOnly { wifiSwitch.setOn(state.wifiOnly, animated: false) }
        usageLabel.text = state.usage
        usageTrack.isHidden = state.usageFraction == nil
        usageFillWidth?.deactivate()
        usageFill.snp.makeConstraints {
            usageFillWidth = $0.width.equalToSuperview().multipliedBy(state.usageFraction ?? 0).constraint
        }
        usageRow.accessibilityLabel = "Занято"
        usageRow.accessibilityValue = state.usage
        clearButton.isEnabled = state.canClear
    }

    private func confirmClear() {
        let alert = UIAlertController(title: "Удалить все загрузки?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in self?.viewModel.didConfirmClear() })
        present(alert, animated: true)
    }
}

/// Плитка-счётчик: число Unbounded 24 и подпись SF 14 semibold (замер макета). Пока не нажимается.
private final class CounterTile: UIView {
    private let valueLabel = UILabel()

    var value: String? {
        get { valueLabel.text }
        set {
            valueLabel.text = newValue
            accessibilityValue = newValue
        }
    }

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor = Palette.surfaceRaised
        layer.cornerRadius = 18
        valueLabel.font = Typography.display(24)
        valueLabel.textColor = Palette.textPrimary
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Typography.text(14, .semibold)
        titleLabel.textColor = Palette.textPrimary
        [valueLabel, titleLabel].forEach(addSubview)
        valueLabel.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(14)
            $0.firstBaseline.equalTo(snp.top).offset(37.75)
        }
        titleLabel.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(14)
            $0.firstBaseline.equalTo(snp.top).offset(62.5)
        }
        isAccessibilityElement = true
        accessibilityLabel = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}
