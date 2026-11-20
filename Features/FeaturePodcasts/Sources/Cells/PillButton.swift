import CoreUI
import UIKit

/// Кнопка-пилюля 36 pt из макета: акцентная («Слушать», «Подписаться») или контурная («Вы подписаны», «Скачать»).
final class PillButton: UIButton {
    enum Style {
        case accent, outline
    }

    static let height: CGFloat = 36

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = Self.height / 2
        layer.borderColor = Palette.track.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// SF шире шрифта макета (D18) — поля чуть уже замера (справа 13 вместо 15.5), чтобы ширина пилюли была ближе к макету.
    /// Поле слева и промежуток до текста по значку (замер): у `download` край значка в 17.5 pt от края, текст в 9.5 pt от значка.
    private static let iconInsets: [String: (leading: CGFloat, padding: CGFloat)] = ["download": (15, 6)]

    /// `icon` — значок CoreUI (`play`, `pause`) или фичи (`download`) слева от текста.
    func configure(title: String, icon: String?, style: Style) {
        let foreground = style == .accent ? Palette.onAccent : Palette.textPrimary
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: Typography.text(15, .semibold),
            .foregroundColor: foreground,
        ]))
        // Значок 16 pt: треугольник play в нём с полем ≈5 pt — край значка в 17.5 pt от края пилюли, как в макете.
        configuration.image = icon.flatMap { Icon.image($0) ?? UIImage(named: $0, in: .module, compatibleWith: nil) }.map { image in
            UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 16, height: 16)) }
                .withRenderingMode(.alwaysTemplate)
        }
        let insets = icon.flatMap { Self.iconInsets[$0] } ?? (leading: 12, padding: 5)
        configuration.imagePadding = insets.padding
        configuration.baseForegroundColor = foreground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: icon == nil ? 14 : insets.leading, bottom: 0, trailing: 13)
        self.configuration = configuration
        backgroundColor = style == .accent ? Palette.accent : .clear
        layer.borderWidth = style == .accent ? 0 : 1
        accessibilityLabel = title
    }
}
