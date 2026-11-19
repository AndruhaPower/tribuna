import CoreUI
import UIKit

@MainActor
public enum FeatureMatch {
    public static func makeRoot() -> UIViewController {
        PlaceholderViewController(title: "Матч")
    }
}
