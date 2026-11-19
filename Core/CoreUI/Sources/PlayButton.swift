import UIKit

/// Что рисовать на кнопке воспроизведения.
public enum PlayControl: Hashable, Sendable {
    case play, pause
    /// Подключение: индикатор вместо значка, нажатие отменяет.
    case loading
}

/// Значки дизайн-системы из ассетов CoreUI (Lucide, шаблонные).
public enum Icon {
    @MainActor public static func image(_ name: String) -> UIImage? {
        UIImage(named: name, in: .module, compatibleWith: nil)
    }
}

/// Круглая кнопка play/pause; при подключении вместо значка — индикатор, нажатие отменяет.
public final class PlayButton: UIButton {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let iconSize: CGFloat?

    /// `iconSize` — сторона значка, pt; nil — размер из ассета (20 pt).
    public init(tint: UIColor, iconSize: CGFloat? = nil) {
        self.iconSize = iconSize
        super.init(frame: .zero)
        tintColor = tint
        spinner.color = tint
        spinner.isUserInteractionEnabled = false
        addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// `label` — уже готовый текст VoiceOver из состояния.
    public func configure(_ control: PlayControl, label: String) {
        let icon: String? = switch control {
        case .play: "play"
        case .pause: "pause"
        case .loading: nil
        }
        setImage(icon.flatMap(Icon.image).map(scaled), for: .normal)
        if control == .loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        accessibilityLabel = label
    }

    /// Векторный ассет перерисовывается в нужный размер без потери чёткости.
    private func scaled(_ image: UIImage) -> UIImage {
        guard let iconSize else { return image }
        let size = CGSize(width: iconSize, height: iconSize)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .withRenderingMode(.alwaysTemplate)
    }
}
