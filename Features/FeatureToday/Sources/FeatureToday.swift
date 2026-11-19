import CoreUI
import UIKit

@MainActor
public enum FeatureToday {
    public static func makeRoot() -> UIViewController {
        PlaceholderViewController(title: "Сегодня")
    }
}
