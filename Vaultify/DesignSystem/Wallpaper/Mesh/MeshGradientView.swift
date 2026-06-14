import SwiftUI
import UIKit

/// Animated multi-point mesh gradient — Telegram's technique without Metal: a static
/// rendered frame at rest, and on each `phase` bump it bakes the interpolated frames
/// and plays them via `CAKeyframeAnimation` on the layer's `contents` (GPU-composited,
/// zero ongoing cost). Honors the app's Reduce Motion (`animated == false`).
struct MeshGradientView: UIViewRepresentable {
    let colors: [UInt32]
    let phase: Int
    var animated: Bool = true

    func makeUIView(context: Context) -> MeshHostView {
        let view = MeshHostView()
        view.update(colors: colors, phase: phase, animated: false)
        return view
    }

    func updateUIView(_ view: MeshHostView, context: Context) {
        view.update(colors: colors, phase: phase, animated: animated)
    }
}

/// UIView whose layer shows the mesh frame; morphs between phases on demand.
final class MeshHostView: UIView {
    private var colors: [UInt32] = []
    private var phase = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(colors: [UInt32], phase: Int, animated: Bool) {
        let colorsChanged = colors != self.colors
        let phaseChanged = phase != self.phase
        self.colors = colors

        if colorsChanged || (!animated && phaseChanged) {
            self.phase = phase
            renderStatic()
        } else if phaseChanged {
            morph(from: self.phase, to: phase)
            self.phase = phase
        } else if layer.contents == nil {
            renderStatic()
        }
    }

    private func renderStatic() {
        layer.removeAnimation(forKey: "contents")
        layer.contents = MeshGradientRenderer.image(colors: colors, positions: MeshMath.positions(phase: phase))?.cgImage
    }

    /// Bake the interpolated frames (80×80, cheap) and play them via Core Animation.
    private func morph(from: Int, to: Int) {
        guard !colors.isEmpty else { renderStatic(); return }
        let duration = 0.5
        let frameCount = 16
        let fromPoints = MeshMath.positions(phase: from)
        let toPoints = MeshMath.positions(phase: to)

        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            let t = CGFloat(i) / CGFloat(frameCount - 1)
            let points = zip(fromPoints, toPoints).map { MeshMath.interpolate($0, $1, at: t) }
            if let cg = MeshGradientRenderer.image(colors: colors, positions: points)?.cgImage {
                frames.append(cg)
            }
        }
        guard let last = frames.last else { renderStatic(); return }

        layer.contents = last
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.duration = duration
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = true
        layer.removeAnimation(forKey: "contents")
        layer.add(animation, forKey: "contents")
    }
}
