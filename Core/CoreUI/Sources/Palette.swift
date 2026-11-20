import UIKit

/// Цвета из макетов docs/design (сняты по пикселям PNG). Приложение только в тёмной теме — см. D13.
public enum Palette {
    public static let background = UIColor(hex: 0x0B1020)
    public static let tabBar = UIColor(hex: 0x0E1428)
    public static let tabBarBorder = UIColor(hex: 0x1E2742)
    /// Карточки, списки, чипсы, поле поиска, контурные кнопки.
    public static let surface = UIColor(hex: 0x141B30)
    /// Выделенные карточки: «Мои события», «Сейчас играет», мини-плеер.
    public static let surfaceRaised = UIColor(hex: 0x1C2540)
    /// Аббревиатуры команд, подложки иконок, выбранный сегмент.
    public static let surfaceHigh = UIColor(hex: 0x2A3557)
    /// Строки команд матча в турнирной таблице.
    public static let highlight = UIColor(hex: 0x21283C)
    public static let separator = UIColor(hex: 0x222B47)
    /// Контуры кнопок, дорожки прогресса и слайдера.
    public static let track = UIColor(hex: 0x26304D)
    public static let textPrimary = UIColor(hex: 0xEEF1F8)
    public static let textSecondary = UIColor(hex: 0x9AA4BD)
    /// Подсказка в пустом поле поиска («Станция или жанр»).
    public static let placeholder = UIColor(hex: 0x757575)
    public static let accent = UIColor(hex: 0xFFB020)
    /// Ореол вокруг точки логотипа (акцент 18 % на фоне).
    public static let accentHalo = UIColor(hex: 0x372D20)
    /// Текст и иконки на акцентной кнопке.
    public static let onAccent = UIColor(hex: 0x1A1300)
    /// Плашка LIVE на карточке матча.
    public static let accentMuted = UIColor(hex: 0x35302E)
    /// Тусклые столбики волны в карточке плеера.
    public static let waveDim = UIColor(hex: 0x1F2844)
    /// Включённый переключатель (Профиль; бегунок — `background`).
    public static let switchOn = UIColor(hex: 0xC9D0E0)
    public static let destructive = UIColor(hex: 0xFF8A7A)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
