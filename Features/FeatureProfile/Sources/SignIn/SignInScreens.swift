import Combine
import CoreUI
import SnapKit
import UIKit

/// Шаг «Мотивация»: «Сохраните своё», строка по поводу, три пункта, «Создать профиль» / «У меня есть профиль» / «Не сейчас».
final class MotivationViewController: UIViewController {
    private let model: SignInModel

    init(model: SignInModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let title = screenTitle("Сохраните своё")
        let stack = UIStackView(arrangedSubviews: [title])
        stack.axis = .vertical
        stack.spacing = 10
        if let reason = SignInTexts.reason(model.reason) {
            stack.addArrangedSubview(subtitle(reason))
        }
        stack.setCustomSpacing(28, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(benefitsView())

        let create = WidePillButton("Создать профиль", style: .accent)
        create.addAction(UIAction { [weak self] _ in self?.model.createProfile() }, for: .touchUpInside)
        let signIn = WidePillButton("У меня есть профиль", style: .outline)
        signIn.addAction(UIAction { [weak self] _ in self?.model.haveProfile() }, for: .touchUpInside)
        let notNow = textButton("Не сейчас")
        notNow.addAction(UIAction { [weak self] _ in self?.model.notNow() }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [create, signIn, notNow])
        buttons.axis = .vertical
        buttons.spacing = 12

        [stack, buttons].forEach(view.addSubview)
        stack.snp.makeConstraints {
            $0.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            $0.leading.trailing.equalToSuperview().inset(20)
        }
        buttons.snp.makeConstraints {
            $0.top.greaterThanOrEqualTo(stack.snp.bottom).offset(24)
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.bottom.equalTo(view.safeAreaLayoutGuide).inset(8)
        }
    }
}

/// Шаги с полями: регистрация, код, вход, почта для сброса, код и новый пароль.
final class FormViewController: UIViewController, UITextFieldDelegate {
    private let model: SignInModel
    private let step: SignInStep
    private var fields: [FormField] = []
    /// Поля разных шагов делят значения модели (почта, пароль) — при возврате на шаг берём текущие.
    private var bindings: [(FormField, ReferenceWritableKeyPath<SignInModel, String>)] = []
    private let errorLabel = UILabel()
    private var submitButton: WidePillButton!
    private var resendButton: UIButton?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(model: SignInModel, step: SignInStep) {
        self.model = model
        self.step = step
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private var texts: (title: String, button: String) {
        switch step {
        case .motivation, .signUp: ("Создать профиль", "Продолжить")
        case .code: ("Код из письма", "Подтвердить")
        case .signIn: ("Вход", "Войти")
        case .forgot: ("Сброс пароля", "Получить код")
        case .resetCode: ("Новый пароль", "Сохранить и войти")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let stack = UIStackView(arrangedSubviews: [screenTitle(texts.title)])
        stack.axis = .vertical
        stack.spacing = 12
        if step == .code || step == .resetCode { stack.addArrangedSubview(subtitle(model.codeHint)) }
        if step == .forgot { stack.addArrangedSubview(subtitle("Пришлём код для нового пароля")) }
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)

        switch step {
        case .motivation: break
        case .signUp:
            addField(nameField(), to: stack)
            addField(emailField(), to: stack)
            addField(passwordField("Пароль", new: true), to: stack)
            stack.addArrangedSubview(caption("От 8 символов"))
        case .code:
            addField(codeField(), to: stack)
        case .signIn:
            addField(emailField(), to: stack)
            addField(passwordField("Пароль", new: false), to: stack)
        case .forgot:
            addField(emailField(), to: stack)
        case .resetCode:
            addField(codeField(), to: stack)
            addField(passwordField("Новый пароль", new: true), to: stack)
            stack.addArrangedSubview(caption("От 8 символов"))
        }
        errorLabel.font = Typography.text(14, .medium)
        errorLabel.textColor = Palette.destructive
        errorLabel.numberOfLines = 0
        stack.addArrangedSubview(errorLabel)

        submitButton = WidePillButton(texts.button, style: .accent)
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        stack.setCustomSpacing(20, after: errorLabel)
        stack.addArrangedSubview(submitButton)
        if step == .signIn {
            let forgot = textButton("Забыли пароль?")
            forgot.addAction(UIAction { [weak self] _ in self?.model.forgotPassword() }, for: .touchUpInside)
            stack.addArrangedSubview(forgot)
        }
        if step == .code || step == .resetCode {
            let resend = textButton("Отправить ещё раз")
            resend.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.model.resend() }
            }, for: .touchUpInside)
            stack.addArrangedSubview(resend)
            resendButton = resend
        }

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.addSubview(stack)
        scroll.snp.makeConstraints {
            $0.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            $0.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        stack.snp.makeConstraints {
            $0.top.equalToSuperview().offset(16)
            $0.bottom.equalToSuperview().inset(16)
            $0.leading.trailing.equalTo(scroll.frameLayoutGuide).inset(20)
        }
        model.$state.sink { [weak self] in self?.render($0) }.store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        for (field, keyPath) in bindings where field.text != model[keyPath: keyPath] { field.text = model[keyPath: keyPath] }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if fields.allSatisfy({ !$0.isFirstResponder }) {
            (fields.first { ($0.text ?? "").isEmpty } ?? fields.first)?.becomeFirstResponder()
        }
        guard resendButton != nil, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func render(_ state: SignInState) {
        // Состояние общее для всех шагов — рисуем только свой, верхний.
        guard state.path.last == step else { return }
        submitButton.isEnabled = state.canSubmit
        submitButton.isLoading = state.isLoading
        resendButton?.isEnabled = state.canResend
        errorLabel.text = state.error
        errorLabel.isHidden = state.error == nil
        fields.forEach { $0.isEnabled = !state.isLoading }
    }

    private func submit() {
        Task { await model.submit() }
    }

    // MARK: - Поля

    private func addField(_ field: FormField, to stack: UIStackView) {
        field.delegate = self
        fields.append(field)
        stack.addArrangedSubview(field)
    }

    private func bind(_ field: FormField, _ keyPath: ReferenceWritableKeyPath<SignInModel, String>) {
        bindings.append((field, keyPath))
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field else { return }
            model[keyPath: keyPath] = field.text ?? ""
        }, for: .editingChanged)
    }

    private func nameField() -> FormField {
        let field = FormField(placeholder: "Имя")
        field.textContentType = .name
        field.autocapitalizationType = .words
        bind(field, \.name)
        return field
    }

    private func emailField() -> FormField {
        let field = FormField(placeholder: "Почта")
        field.textContentType = .username
        field.keyboardType = .emailAddress
        field.autocapitalizationType = .none
        bind(field, \.email)
        return field
    }

    private func passwordField(_ placeholder: String, new: Bool) -> FormField {
        let field = FormField(placeholder: placeholder)
        field.textContentType = new ? .newPassword : .password
        #if DEBUG
        // Симулятор закрывает `.newPassword` жёлтой плашкой «Automatic Strong Password» — ввод не виден; для сверки вёрстки — без неё.
        if ProcessInfo.processInfo.arguments.contains("-ProfileMock") { field.textContentType = .password }
        #endif
        field.autocapitalizationType = .none
        field.makeSecure()
        bind(field, \.password)
        return field
    }

    private func codeField() -> FormField {
        let field = FormField(placeholder: "Код из 6 цифр")
        field.textContentType = .oneTimeCode
        field.keyboardType = .numberPad
        field.font = Typography.digits(20, .semibold)
        bind(field, \.code)
        return field
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let index = fields.firstIndex(where: { $0 === textField }), index + 1 < fields.count {
            fields[index + 1].becomeFirstResponder()
        } else {
            submit()
        }
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard (textField as? FormField)?.textContentType == .oneTimeCode else { return true }
        let text = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        return text.count <= 6 && text.allSatisfy(\.isNumber)
    }
}

// MARK: - Подписи

/// Заголовок шага — Unbounded (заголовок экрана, D18).
@MainActor func screenTitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = Typography.display(26)
    label.textColor = Palette.textPrimary
    label.numberOfLines = 0
    label.accessibilityTraits = .header
    return label
}

@MainActor private func subtitle(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = Typography.text(16)
    label.textColor = Palette.textSecondary
    label.numberOfLines = 0
    return label
}

@MainActor private func caption(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = Typography.text(13)
    label.textColor = Palette.textSecondary
    return label
}
