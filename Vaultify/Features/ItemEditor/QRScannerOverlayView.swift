#if os(iOS)
import UIKit

/// Telegram-style scanner overlay: a dimmed surround with a centered focus hole
/// and four rounded-corner "L" brackets. On detection the frame springs/snaps
/// onto the QR's bounds and the surround darkens. Springs match Telegram's feel
/// (stiffness 900 / damping 88 / mass 5).
final class QRScannerOverlayView: UIView {
    private let dimLayer = CAShapeLayer()
    private let bracketsLayer = CAShapeLayer()

    private let holeRadius: CGFloat = 14
    private let bracketRadius: CGFloat = 8
    private let bracketArm: CGFloat = 28
    private let dimIdle: Float = 0.55
    private let dimFocused: Float = 0.82

    private var focusedRect: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.cgColor
        dimLayer.opacity = dimIdle
        layer.addSublayer(dimLayer)

        bracketsLayer.fillColor = UIColor.clear.cgColor
        bracketsLayer.strokeColor = UIColor.white.cgColor
        bracketsLayer.lineWidth = 4
        bracketsLayer.lineCap = .round
        bracketsLayer.lineJoin = .round
        layer.addSublayer(bracketsLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimLayer.frame = bounds
        bracketsLayer.frame = bounds
        applyFocus(focusedRect ?? idleRect, animated: false)
    }

    /// Centered focus square shown while searching.
    var idleRect: CGRect {
        let side = min(min(bounds.width, bounds.height) * 0.66, 300)
        return CGRect(x: (bounds.width - side) / 2,
                      y: (bounds.height - side) / 2 - 24,
                      width: side, height: side)
    }

    /// Snap onto a detected QR rect (in this view's coordinates), or back to idle.
    func focus(on rect: CGRect?) {
        if let rect {
            let side = max(max(rect.width, rect.height) * 1.3, 90)
            let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            focusedRect = square
            applyFocus(square, animated: true)
            animateDim(to: dimFocused)
        } else {
            focusedRect = nil
            applyFocus(idleRect, animated: true)
            animateDim(to: dimIdle)
        }
    }

    /// Spring the frame in from 40% scale + fade the dim in (screen entry).
    func playEntryAnimation() {
        let scale = makeSpring(keyPath: "transform.scale", from: 0.4, to: 1.0)
        bracketsLayer.add(scale, forKey: "entryScale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.4
        bracketsLayer.add(fade, forKey: "entryFade")
        dimLayer.add(fade, forKey: "entryFade")
    }

    // MARK: Drawing

    private func applyFocus(_ rect: CGRect, animated: Bool) {
        let dim = dimPath(hole: rect)
        let brackets = bracketsPath(rect)
        if animated {
            springPath(dimLayer, to: dim)
            springPath(bracketsLayer, to: brackets)
        } else {
            dimLayer.removeAnimation(forKey: "path")
            bracketsLayer.removeAnimation(forKey: "path")
            dimLayer.path = dim
            bracketsLayer.path = brackets
        }
    }

    private func dimPath(hole: CGRect) -> CGPath {
        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(roundedRect: hole, cornerRadius: holeRadius))
        path.usesEvenOddFillRule = true
        return path.cgPath
    }

    /// Four rounded "L" corner brackets hugging `r`.
    private func bracketsPath(_ r: CGRect) -> CGPath {
        let p = UIBezierPath()
        let a = bracketArm, rad = bracketRadius
        // Top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + rad + a))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(withCenter: CGPoint(x: r.minX + rad, y: r.minY + rad), radius: rad,
                 startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX + rad + a, y: r.minY))
        // Top-right
        p.move(to: CGPoint(x: r.maxX - rad - a, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
        p.addArc(withCenter: CGPoint(x: r.maxX - rad, y: r.minY + rad), radius: rad,
                 startAngle: .pi * 1.5, endAngle: .pi * 2, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + rad + a))
        // Bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - rad - a))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(withCenter: CGPoint(x: r.maxX - rad, y: r.maxY - rad), radius: rad,
                 startAngle: 0, endAngle: .pi * 0.5, clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX - rad - a, y: r.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: r.minX + rad + a, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addArc(withCenter: CGPoint(x: r.minX + rad, y: r.maxY - rad), radius: rad,
                 startAngle: .pi * 0.5, endAngle: .pi, clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rad - a))
        return p.cgPath
    }

    // MARK: Animation helpers

    private func springPath(_ shapeLayer: CAShapeLayer, to path: CGPath) {
        let animation = makeSpring(keyPath: "path",
                                   from: shapeLayer.presentation()?.path ?? shapeLayer.path,
                                   to: path)
        shapeLayer.path = path
        shapeLayer.add(animation, forKey: "path")
    }

    private func animateDim(to opacity: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = dimLayer.presentation()?.opacity ?? dimLayer.opacity
        animation.toValue = opacity
        animation.duration = 0.4
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dimLayer.opacity = opacity
        dimLayer.add(animation, forKey: "dimOpacity")
    }

    private func makeSpring(keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.stiffness = 900
        animation.damping = 88
        animation.mass = 5
        animation.initialVelocity = 0
        animation.duration = animation.settlingDuration
        animation.fromValue = from
        animation.toValue = to
        return animation
    }
}
#endif
