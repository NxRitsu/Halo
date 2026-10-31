import AppKit
import SwiftUI

/// Small animated equalizer bars.
///
/// The bars are animated with Core Animation, which runs in the render server: the app itself
/// does no work per frame, so playback costs no CPU. Animations are removed when paused.
struct EqualizerView: NSViewRepresentable {
    var isAnimating: Bool
    var color: NSColor

    func makeNSView(context: Context) -> EqualizerBarsView {
        EqualizerBarsView()
    }

    func updateNSView(_ view: EqualizerBarsView, context: Context) {
        view.update(color: color, isAnimating: isAnimating)
    }
}

final class EqualizerBarsView: NSView {
    private static let barCount = 4
    private static let restingScale: CGFloat = 0.25
    /// Duration of each bar's cycle: different values keep the bars out of sync.
    private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.36, 0.48]

    private var bars: [CALayer] = []
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.setAffineTransform(CGAffineTransform(scaleX: 1, y: Self.restingScale))
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let count = CGFloat(Self.barCount)
        let spacing = max(bounds.width * 0.12, 1.5)
        let barWidth = (bounds.width - spacing * (count - 1)) / count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (barWidth + spacing) + barWidth / 2, y: bounds.midY)
            bar.cornerRadius = barWidth / 2
        }
        CATransaction.commit()
    }

    func update(color: NSColor, isAnimating: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        guard isAnimating != self.isAnimating else { return }
        self.isAnimating = isAnimating
        for (index, bar) in bars.enumerated() {
            if isAnimating {
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = Self.restingScale
                animation.toValue = 1
                animation.duration = Self.durations[index % Self.durations.count]
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.beginTime = CACurrentMediaTime() + Double(index) * 0.08
                bar.add(animation, forKey: "equalizer")
            } else {
                bar.removeAnimation(forKey: "equalizer")
            }
        }
    }
}
