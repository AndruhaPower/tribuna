import CoreUI
import UIKit

@MainActor
public enum FeatureProfile {
    public static func makeRoot() -> UIViewController {
        PlaceholderViewController(title: "Профиль")
    }
}
