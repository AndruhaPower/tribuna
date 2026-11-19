import CoreUI
import UIKit

@MainActor
public enum FeaturePodcasts {
    public static func makeRoot() -> UIViewController {
        PlaceholderViewController(title: "Подкасты")
    }
}
