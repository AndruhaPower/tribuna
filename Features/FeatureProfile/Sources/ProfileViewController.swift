import Combine
import CoreDomain
import CoreUI
import SnapKit
import UIKit

/// Профиль по макету «Профиль» (с флагом 1.2 — с «Уведомлениями» и подвалом, D41). Со входом: карточка аккаунта, плитки-счётчики, «ЗАГРУЗКИ», «Удалить аккаунт».
/// Без входа: заголовок и карточка мотивации. Отступы — замер макета от верха безопасной зоны и от низа плиток.
final class ProfileViewController: UIViewController {
    private let viewModel: ProfileViewModel
    private let account: Account
    private let signedInContent = UIView()
    private let motivationCard = UIView()
    private let avatarLabel = UILabel()
    private let avatarImage = UIImageView()
    private let avatarButton = UIButton(type: .custom)
    private lazy var photoSource = PhotoSource(host: self) { [weak self] in self?.didPick($0) }
    private let nameLabel = UILabel()
    private let emailLabel = UILabel()
    private let signOutButton = WidePillButton("Выйти", style: .outline, height: 34, font: Typography.text(14, .semibold))
    private let deleteButton = textButton("Удалить аккаунт", color: Palette.destructive)
    private let bookmarksTile = CounterTile(title: "Мои закладки")
    private let subscriptionsTile = CounterTile(title: "Мои подписки")
    private let wifiSwitch = UISwitch()
    private let usageLabel = UILabel()
    private let usageTrack = UIView()
    private let usageFill = UIView()
    private var usageFillWidth: Constraint?
    private var shownFraction: Double?
    private let usageRow = UIView()
    private let clearButton = UIButton(type: .system)
    private var cancellables: Set<AnyCancellable> = []
    #if FEATURE_PROFILE2
    private let remindRow = SwitchRow(title: "Начало событий", subtitle: "За 15 минут, для закладок")
    private let episodesRow = SwitchRow(title: "Новые выпуски", subtitle: "Из моих подписок")
    private lazy var signedOutFooter = makeFooter()
    #endif

    init(viewModel: ProfileViewModel, account: Account) {
        self.viewModel = viewModel
        self.account = account
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.snp.makeConstraints {
            $0.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            $0.bottom.equalToSuperview()
        }
        let safe = UIView()
        scroll.addSubview(safe)
        safe.snp.makeConstraints {
            $0.edges.equalTo(scroll.contentLayoutGuide)
            $0.width.equalTo(scroll.frameLayoutGuide)
        }
        let accountCard = makeAccountCard()
        setUpMotivationCard()

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

        deleteButton.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .touchUpInside)

        [titleLabel, signedInContent, motivationCard].forEach(safe.addSubview)
        [accountCard, bookmarksTile, subscriptionsTile, section, card, deleteButton].forEach(signedInContent.addSubview)
        // Без 1.2 «Загрузки» идут сразу под плитками; с 1.2 — под «Уведомлениями» (D41).
        #if FEATURE_PROFILE2
        let notificationsSection = UILabel()
        notificationsSection.attributedText = NSAttributedString(string: "УВЕДОМЛЕНИЯ", attributes: [
            .font: sectionFont, .foregroundColor: Palette.textSecondary, .kern: 0.3,
        ])
        notificationsSection.accessibilityTraits = .header
        let notificationsCard = cardStack([remindRow, episodesRow])
        remindRow.toggle.addAction(UIAction { [weak self] action in
            guard let self, let toggle = action.sender as? UISwitch else { return }
            Task { if !(await self.viewModel.didToggleRemindBookmarks(toggle.isOn)) { self.offerSettings() } }
        }, for: .valueChanged)
        episodesRow.toggle.addAction(UIAction { [weak self] action in
            guard let self, let toggle = action.sender as? UISwitch else { return }
            Task { if !(await self.viewModel.didToggleNewEpisodes(toggle.isOn)) { self.offerSettings() } }
        }, for: .valueChanged)
        [notificationsSection, notificationsCard].forEach(signedInContent.addSubview)
        notificationsSection.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(20)
            $0.lastBaseline.equalTo(bookmarksTile.snp.bottom).offset(32.5)
        }
        notificationsCard.snp.makeConstraints {
            $0.top.equalTo(bookmarksTile.snp.bottom).offset(44)
            $0.leading.trailing.equalToSuperview().inset(20)
        }
        let downloadsAnchor = notificationsCard.snp.bottom
        // Подвал — со входом под «Удалить аккаунт», без входа — под мотивацией: турниры работают и без профиля.
        let signedInFooter = makeFooter()
        signedInContent.addSubview(signedInFooter)
        safe.addSubview(signedOutFooter)
        signedOutFooter.snp.makeConstraints {
            $0.top.equalTo(motivationCard.snp.bottom).offset(16)
            $0.leading.equalToSuperview().offset(20)
            $0.trailing.lessThanOrEqualToSuperview().inset(20)
        }
        #else
        let downloadsAnchor = bookmarksTile.snp.bottom
        #endif
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
        signedInContent.snp.makeConstraints {
            $0.top.equalToSuperview().offset(63)
            $0.leading.trailing.bottom.equalToSuperview()
        }
        motivationCard.snp.makeConstraints {
            $0.top.equalToSuperview().offset(63)
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.bottom.lessThanOrEqualToSuperview().inset(24)
        }
        accountCard.snp.makeConstraints {
            $0.top.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.height.equalTo(79)
        }
        bookmarksTile.snp.makeConstraints {
            $0.top.equalTo(accountCard.snp.bottom).offset(20)
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
            $0.lastBaseline.equalTo(downloadsAnchor).offset(32.5)
        }
        card.snp.makeConstraints {
            $0.top.equalTo(downloadsAnchor).offset(44)
            $0.leading.trailing.equalToSuperview().inset(20)
        }
        deleteButton.snp.makeConstraints {
            $0.top.equalTo(card.snp.bottom).offset(20)
            $0.leading.equalToSuperview().offset(20)
            #if !FEATURE_PROFILE2
            $0.bottom.equalToSuperview().inset(16)
            #endif
        }
        #if FEATURE_PROFILE2
        signedInFooter.snp.makeConstraints {
            $0.top.equalTo(deleteButton.snp.bottom).offset(12)
            $0.leading.equalToSuperview().offset(20)
            $0.trailing.lessThanOrEqualToSuperview().inset(20)
            $0.bottom.equalToSuperview().inset(16)
        }
        #endif
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

    #if FEATURE_PROFILE2
    private func makeFooter() -> UIView {
        profileFooter(openCompetitions: { [weak self] in
            guard let self else { return }
            navigationController?.pushViewController(
                CompetitionsViewController(settings: viewModel.settings, repository: viewModel.competitions), animated: true)
        }, openAbout: { [weak self] in
            self?.navigationController?.pushViewController(AboutViewController(), animated: true)
        })
    }

    /// Уведомления запрещены — объяснить и предложить Настройки (как «Напомнить» в карточке матча).
    private func offerSettings() {
        let alert = UIAlertController(title: "Уведомления выключены",
                                      message: "Чтобы получать уведомления, разрешите их для Tribuna в Настройках.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Не сейчас", style: .cancel))
        alert.addAction(UIAlertAction(title: "Настройки", style: .default) { [weak self] _ in self?.viewModel.openSettings() })
        present(alert, animated: true)
    }

    /// Нажатие на имя: смена имени (`user_metadata.full_name`).
    @objc private func editName() {
        guard viewModel.canRename, presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Как вас зовут?", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] field in
            field.text = self?.nameLabel.text == "Болельщик" ? nil : self?.nameLabel.text
            field.placeholder = "Имя"
            field.autocapitalizationType = .words
            field.textContentType = .name
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            Task {
                guard let message = await self.viewModel.didRename(name) else { return }
                let error = UIAlertController(title: "Не удалось сохранить имя", message: message, preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "OK", style: .cancel))
                self.present(error, animated: true)
            }
        })
        present(alert, animated: true)
    }
    #endif

    private func rowLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.text(16, .medium)
        label.textColor = Palette.textPrimary
        return label
    }

    /// Карточка аккаунта (замер макета): высота 79, кружок 52 с полем 16, имя SF 18 semibold, почта SF 14, «Выйти» 34 pt.
    private func makeAccountCard() -> UIView {
        let card = UIView()
        card.backgroundColor = Palette.surface
        card.layer.cornerRadius = 18
        let avatar = UIView()
        avatar.backgroundColor = Palette.surfaceHigh
        avatar.layer.cornerRadius = 26
        avatarLabel.font = Typography.display(20)
        avatarLabel.textColor = Palette.textPrimary
        avatarLabel.textAlignment = .center
        avatar.isAccessibilityElement = false
        avatarImage.contentMode = .scaleAspectFill
        avatarImage.layer.cornerRadius = 26
        avatarImage.clipsToBounds = true
        // Нажатие на кружок — фото профиля (D43).
        avatarButton.accessibilityLabel = "Фото профиля"
        avatarButton.accessibilityHint = "Сделать или выбрать фото"
        avatarButton.addAction(UIAction { [weak self] _ in self?.showPhotoMenu() }, for: .touchUpInside)
        nameLabel.font = Typography.text(18, .semibold)
        nameLabel.textColor = Palette.textPrimary
        emailLabel.font = Typography.text(14)
        emailLabel.textColor = Palette.textSecondary
        [nameLabel, emailLabel].forEach { $0.lineBreakMode = .byTruncatingTail }
        signOutButton.addAction(UIAction { [weak self] _ in self?.confirmSignOut() }, for: .touchUpInside)
        [avatar, nameLabel, emailLabel, signOutButton].forEach(card.addSubview)
        [avatarLabel, avatarImage, avatarButton].forEach(avatar.addSubview)
        avatarImage.snp.makeConstraints { $0.edges.equalToSuperview() }
        avatarButton.snp.makeConstraints { $0.edges.equalToSuperview() }
        avatar.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(16)
            $0.centerY.equalToSuperview()
            $0.size.equalTo(52)
        }
        avatarLabel.snp.makeConstraints { $0.center.equalToSuperview() }
        nameLabel.snp.makeConstraints {
            $0.leading.equalTo(avatar.snp.trailing).offset(14.5)
            $0.trailing.lessThanOrEqualTo(signOutButton.snp.leading).offset(-10)
            $0.firstBaseline.equalTo(card.snp.top).offset(36.25)
        }
        emailLabel.snp.makeConstraints {
            $0.leading.equalTo(nameLabel)
            $0.trailing.lessThanOrEqualTo(signOutButton.snp.leading).offset(-10)
            $0.firstBaseline.equalTo(card.snp.top).offset(54.75)
        }
        signOutButton.snp.makeConstraints {
            $0.trailing.equalToSuperview().inset(16)
            $0.centerY.equalToSuperview()
        }
        signOutButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        #if FEATURE_PROFILE2
        // Имя меняется нажатием на имя; кружок — фото профиля (D43), «Выйти» — своя кнопка.
        nameLabel.isUserInteractionEnabled = true
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(editName)))
        nameLabel.accessibilityTraits = .button
        nameLabel.accessibilityHint = "Изменить имя"
        #endif
        return card
    }

    /// Без входа: три пункта пользы и «Создать профиль» / «У меня есть профиль» — открывают лист на своём шаге.
    private func setUpMotivationCard() {
        motivationCard.backgroundColor = Palette.surface
        motivationCard.layer.cornerRadius = 18
        let create = WidePillButton("Создать профиль", style: .accent)
        create.addAction(UIAction { [weak self] _ in self?.openSignIn(.signUp) }, for: .touchUpInside)
        let signIn = WidePillButton("У меня есть профиль", style: .outline)
        signIn.addAction(UIAction { [weak self] _ in self?.openSignIn(.signIn) }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [benefitsView(), create, signIn])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[0])
        motivationCard.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 20, left: 16, bottom: 16, right: 16)) }
    }

    private func openSignIn(_ start: SignInStart) {
        guard presentedViewController == nil else { return }
        present(FeatureProfile.makeSignIn(account: account, reason: .profile, startAt: start) { _ in }, animated: true)
    }

    private func render(_ state: ProfileState) {
        signedInContent.isHidden = state.account == nil
        motivationCard.isHidden = state.account != nil || state.isResolving
        #if FEATURE_PROFILE2
        signedOutFooter.isHidden = motivationCard.isHidden
        #endif
        if let card = state.account {
            avatarLabel.text = card.initial
            avatarImage.image = state.avatar.flatMap(UIImage.init(data:))
            avatarLabel.isHidden = avatarImage.image != nil
            nameLabel.text = card.name
            emailLabel.text = card.email
        }
        signOutButton.isEnabled = !state.isBusy
        avatarButton.isEnabled = !state.isBusy
        deleteButton.isEnabled = !state.isBusy
        bookmarksTile.value = state.bookmarks
        subscriptionsTile.value = state.subscriptions
        if wifiSwitch.isOn != state.wifiOnly { wifiSwitch.setOn(state.wifiOnly, animated: false) }
        #if FEATURE_PROFILE2
        if remindRow.toggle.isOn != state.remindBookmarks { remindRow.toggle.setOn(state.remindBookmarks, animated: true) }
        if episodesRow.toggle.isOn != state.notifyNewEpisodes { episodesRow.toggle.setOn(state.notifyNewEpisodes, animated: true) }
        #endif
        usageLabel.text = state.usage
        usageTrack.isHidden = state.usageFraction == nil
        // Множитель у ограничения не меняется — пересобираем, только когда доля другая.
        if state.usageFraction != shownFraction {
            shownFraction = state.usageFraction
            usageFillWidth?.deactivate()
            usageFill.snp.makeConstraints {
                usageFillWidth = $0.width.equalToSuperview().multipliedBy(state.usageFraction ?? 0).constraint
            }
        }
        usageRow.accessibilityLabel = "Занято"
        usageRow.accessibilityValue = state.usage
        clearButton.isEnabled = state.canClear
    }

    /// Сделать фото (если есть камера), выбрать из галереи, удалить — если фото есть.
    private func showPhotoMenu() {
        guard presentedViewController == nil else { return }
        let sheet = UIAlertController(title: "Фото профиля", message: nil, preferredStyle: .actionSheet)
        if PhotoSource.hasCamera {
            sheet.addAction(UIAlertAction(title: "Сделать фото", style: .default) { [weak self] _ in self?.photoSource.openCamera() })
        }
        sheet.addAction(UIAlertAction(title: "Выбрать из галереи", style: .default) { [weak self] _ in self?.photoSource.openLibrary() })
        if viewModel.state.avatar != nil {
            sheet.addAction(UIAlertAction(title: "Удалить фото", style: .destructive) { [weak self] _ in
                guard let self else { return }
                Task { self.showPhotoError(await self.viewModel.didRemovePhoto()) }
            })
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        sheet.popoverPresentationController?.sourceView = avatarButton
        present(sheet, animated: true)
    }

    private func didPick(_ image: UIImage) {
        guard let jpeg = AvatarImage.jpeg(from: image) else { return }
        Task { showPhotoError(await viewModel.didPickPhoto(jpeg)) }
    }

    private func showPhotoError(_ message: String?) {
        guard let message else { return }
        let alert = UIAlertController(title: "Не удалось сохранить фото", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    private func confirmClear() {
        let alert = UIAlertController(title: "Удалить все загрузки?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in self?.viewModel.didConfirmClear() })
        present(alert, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(title: ProfileTexts.signOutConfirm, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Выйти", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { await self.viewModel.didConfirmSignOut() }
        })
        present(alert, animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: ProfileTexts.deleteConfirm, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                guard let message = await self.viewModel.didConfirmDelete() else { return }
                let error = UIAlertController(title: "Не удалось удалить аккаунт", message: message, preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "OK", style: .cancel))
                self.present(error, animated: true)
            }
        })
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
