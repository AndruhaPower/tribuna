import CoreUI
import UIKit

/// Декоративная волна «Сейчас играет»: 31 столбик 4 pt, первые 12 — акцентные (рисунок макета).
/// Пульсирует только при воспроизведении; при «Уменьшении движения» стоит на месте.
final class WaveView: UIView {
    /// Высоты столбиков из макета, pt.
    private static let heights: [CGFloat] = [8, 20, 12, 24, 10, 18, 6, 22, 12, 16, 8, 20, 10, 18, 8, 22, 12, 16, 6, 20, 10, 18, 8, 24, 12, 16, 8, 20, 10, 16, 6]
    private static let accentCount = 12
    private static let barWidth: CGFloat = 4
    static let height: CGFloat = 24

    var isAnimating = false {
        didSet { if isAnimating != oldValue { updateAnimation() } }
    }

    private let bars: [CALayer]

    override init(frame: CGRect) {
        bars = Self.heights.indices.map { _ in CALayer() }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = (index < Self.accentCount ? Palette.accent : Palette.surfaceHigh).cgColor
            bar.cornerRadius = Self.barWidth / 2
            layer.addSublayer(bar)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateAnimation), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let step = (bounds.width - Self.barWidth) / CGFloat(bars.count - 1)
        for (index, bar) in bars.enumerated() {
            let height = Self.heights[index]
            bar.frame = CGRect(x: CGFloat(index) * step, y: (bounds.height - height) / 2, width: Self.barWidth, height: height)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    @objc private func updateAnimation() {
        let animates = isAnimating && window != nil && !UIAccessibility.isReduceMotionEnabled
        for (index, bar) in bars.enumerated() {
            guard animates else {
                bar.removeAnimation(forKey: "pulse")
                continue
            }
            guard bar.animation(forKey: "pulse") == nil else { continue }
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 1
            pulse.toValue = 0.35
            // Разные периоды и фазы — чтобы столбики не двигались строем.
            pulse.duration = 0.35 + Double(index % 5) * 0.07
            pulse.beginTime = CACurrentMediaTime() + Double(index % 7) * 0.05
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(pulse, forKey: "pulse")
        }
    }
}
