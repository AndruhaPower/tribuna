import CoreUI
import UIKit

/// Круглая кнопка play/pause; при подключении вместо значка — индикатор, нажатие отменяет.
final class PlayButton: UIButton {
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(tint: UIColor) {
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
    func configure(_ button: RadioState.Button, label: String) {
        let icon: String? = switch button {
        case .play: "play"
        case .pause: "pause"
        case .loading: nil
        }
        setImage(icon.flatMap { UIImage(named: $0, in: .module, compatibleWith: nil) }, for: .normal)
        if button == .loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        accessibilityLabel = label
    }
}
