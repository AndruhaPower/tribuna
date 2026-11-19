import CoreUI
import UIKit

@MainActor
public enum FeatureBookmarks {
    public static func makeRoot() -> UIViewController {
        PlaceholderViewController(title: "Закладки")
    }
}
