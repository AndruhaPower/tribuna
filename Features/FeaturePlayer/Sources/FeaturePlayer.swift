import CoreUI
import UIKit

@MainActor
public enum FeaturePlayer {
    public static func makeRoot() -> UIViewController {
        PlaceholderViewController(title: "Плеер")
    }
}
