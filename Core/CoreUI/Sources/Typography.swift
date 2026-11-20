import CoreText
import UIKit

/// Шрифты — D18. Unbounded: заголовки экранов, логотип, счёт, цифры профиля. Всё остальное — системный SF Pro.
@MainActor
public enum Typography {
    public enum DisplayWeight: Int {
        case medium = 500
        case bold = 700
    }

    /// Unbounded. Файл вариативный, вес задаётся осью `wght`.
    public static func display(_ size: CGFloat, _ weight: DisplayWeight = .bold) -> UIFont {
        let wghtAxis = 0x7767_6874 // 'wght'
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: "Unbounded",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtAxis: weight.rawValue],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        // Без шрифта в бандле UIKit молча подставит системный — ловим это в отладке.
        assert(font.familyName == "Unbounded", "Unbounded не зарегистрирован: проверь UIAppFonts в Project.swift")
        return font
    }

    /// SF Pro.
    public static func text(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// SF с цифрами одной ширины: время в плеере не дрожит при смене цифр.
    public static func digits(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    /// 30 pt — замер заголовка «Сегодня» по макету.
    public static var screenTitle: UIFont { display(30) }
}
