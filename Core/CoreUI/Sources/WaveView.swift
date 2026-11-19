import UIKit

/// Декоративная волна: столбики из рисунка макета, первые `accentCount` — акцентные.
/// Пульсирует только при воспроизведении; при «Уменьшении движения» стоит на месте.
public final class WaveView: UIView {
    public struct Style {
        /// Высоты столбиков из макета, pt.
        let heights: [CGFloat]
        let barWidth: CGFloat
        let accentCount: Int
        let accent: UIColor
        let rest: UIColor

        public init(heights: [CGFloat], barWidth: CGFloat, accentCount: Int, accent: UIColor, rest: UIColor) {
            self.heights = heights
            self.barWidth = barWidth
            self.accentCount = accentCount
            self.accent = accent
            self.rest = rest
        }

        /// Высота самого высокого столбика.
        public var height: CGFloat { heights.max() ?? 0 }
    }

    public var isAnimating = false {
        didSet { if isAnimating != oldValue { updateAnimation() } }
    }

    private let style: Style
    private let bars: [CALayer]

    public init(style: Style) {
        self.style = style
        bars = style.heights.indices.map { _ in CALayer() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = (index < style.accentCount ? style.accent : style.rest).cgColor
            bar.cornerRadius = style.barWidth / 2
            layer.addSublayer(bar)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateAnimation), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let step = (bounds.width - style.barWidth) / CGFloat(bars.count - 1)
        for (index, bar) in bars.enumerated() {
            let height = style.heights[index]
            bar.frame = CGRect(x: CGFloat(index) * step, y: (bounds.height - height) / 2, width: style.barWidth, height: height)
        }
    }

    override public func didMoveToWindow() {
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
