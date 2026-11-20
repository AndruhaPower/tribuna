import CoreUI
import SnapKit
import UIKit

/// Пилюля во всю ширину: акцентная («Создать профиль», «Войти») или контурная («У меня есть профиль», «Выйти»).
final class WidePillButton: UIButton {
    enum Style { case accent, outline }

    static let height: CGFloat = 50
    var isLoading = false { didSet { setNeedsUpdateConfiguration(); accessibilityValue = isLoading ? "Загрузка" : nil } }

    init(_ title: String, style: Style, height: CGFloat = WidePillButton.height, font: UIFont = Typography.text(17, .semibold)) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        self.configuration = configuration
        layer.cornerRadius = height / 2
        layer.borderColor = Palette.track.cgColor
        layer.borderWidth = style == .outline ? 1 : 0
        let foreground = style == .accent ? Palette.onAccent : Palette.textPrimary
        configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            let active = button.isEnabled || isLoading
            let color = active ? foreground : style == .accent ? Palette.textSecondary : foreground.withAlphaComponent(0.4)
            button.configuration?.attributedTitle = isLoading ? nil : AttributedString(title, attributes: AttributeContainer([.font: font, .foregroundColor: color]))
            button.configuration?.showsActivityIndicator = isLoading
            button.configuration?.baseForegroundColor = foreground
            if style == .accent { button.backgroundColor = active ? Palette.accent : Palette.surfaceHigh }
        }
        accessibilityLabel = title
        snp.makeConstraints { $0.height.equalTo(height) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}

/// Текстовая кнопка: «Не сейчас», «Забыли пароль?», «Отправить ещё раз», «Удалить аккаунт».
@MainActor func textButton(_ title: String, color: UIColor = Palette.textSecondary, weight: UIFont.Weight = .semibold) -> UIButton {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.plain()
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
    button.configuration = configuration
    button.configurationUpdateHandler = { button in
        button.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: Typography.text(16, weight),
            .foregroundColor: button.isEnabled ? color : color.withAlphaComponent(0.4),
        ]))
    }
    return button
}

/// Поле листа входа: `surface`, скругление 14, высота 52.
final class FormField: UITextField {
    init(placeholder: String) {
        super.init(frame: .zero)
        backgroundColor = Palette.surface
        layer.cornerRadius = 14
        font = Typography.text(17)
        textColor = Palette.textPrimary
        tintColor = Palette.accent
        attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: Palette.placeholder])
        accessibilityLabel = placeholder
        autocorrectionType = .no
        spellCheckingType = .no
        snp.makeConstraints { $0.height.equalTo(52) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    private let inset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    override func textRect(forBounds bounds: CGRect) -> CGRect { super.textRect(forBounds: bounds).inset(by: inset) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { super.editingRect(forBounds: bounds).inset(by: inset) }
    override func rightViewRect(forBounds bounds: CGRect) -> CGRect { super.rightViewRect(forBounds: bounds).offsetBy(dx: -8, dy: 0) }

    /// Пароль с кнопкой «показать/скрыть».
    func makeSecure() {
        isSecureTextEntry = true
        let toggle = UIButton(type: .system)
        toggle.tintColor = Palette.textSecondary
        toggle.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        let update = { [weak self, weak toggle] in
            guard let self, let toggle else { return }
            toggle.setImage(UIImage(systemName: isSecureTextEntry ? "eye" : "eye.slash"), for: .normal)
            toggle.accessibilityLabel = isSecureTextEntry ? "Показать пароль" : "Скрыть пароль"
        }
        toggle.addAction(UIAction { [weak self] _ in
            self?.isSecureTextEntry.toggle()
            update()
        }, for: .touchUpInside)
        update()
        rightView = toggle
        rightViewMode = .always
    }
}

/// Три пункта пользы с галочкой — в листе и в Профиле без входа.
@MainActor func benefitsView() -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 14
    for text in SignInTexts.benefits {
        let icon = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        icon.tintColor = Palette.accent
        icon.contentMode = .center
        let circle = UIView()
        circle.backgroundColor = Palette.accentHalo
        circle.layer.cornerRadius = 13
        circle.addSubview(icon)
        icon.snp.makeConstraints { $0.center.equalToSuperview() }
        circle.snp.makeConstraints { $0.size.equalTo(26) }
        let label = UILabel()
        label.text = text
        label.font = Typography.text(16, .medium)
        label.textColor = Palette.textPrimary
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [circle, label])
        row.spacing = 12
        row.alignment = .center
        row.isAccessibilityElement = true
        row.accessibilityLabel = text
        stack.addArrangedSubview(row)
    }
    return stack
}
