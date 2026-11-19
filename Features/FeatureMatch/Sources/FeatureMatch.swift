import CoreUI
import UIKit

@MainActor
public enum FeatureMatch {
    /// Заглушка карточки матча: заголовок «Ливерпуль — Арсенал».
    public static func make(title: String) -> UIViewController {
        PlaceholderViewController(title: title)
    }
}
