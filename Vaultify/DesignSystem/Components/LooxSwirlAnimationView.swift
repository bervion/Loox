import SwiftUI

/// Apple-boot-style brand swirl: the Loox six-circle symbol at the centre with
/// concentric rings of rainbow dots orbiting it. The dots are the mesh-gradient
/// image (`SwirlGradient`) masked into moving circles, so each dot takes the
/// gradient colour at its position. Rings counter-rotate and shimmer; on appear
/// they spiral out from the centre. Driven by `TimelineView(.animation)` for a
/// smooth 60fps loop. Purely decorative.
struct LooxSwirlAnimationView: View {
    /// Centre logo height as a fraction of the view's smaller dimension.
    var logoFraction: CGFloat = 0.32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    private struct Ring { let rf: CGFloat; let count: Int; let dotf: CGFloat; let dir: Double; let phase: Double }
    private let rings: [Ring] = [
        Ring(rf: 0.215, count: 20, dotf: 0.0125, dir:  1, phase: 0.0),
        Ring(rf: 0.285, count: 26, dotf: 0.0130, dir: -1, phase: 0.6),
        Ring(rf: 0.355, count: 34, dotf: 0.0135, dir:  1, phase: 1.2),
        Ring(rf: 0.425, count: 42, dotf: 0.0140, dir: -1, phase: 1.8),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("SwirlGradient")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask { dots }
                Image("BrandSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(height: min(geo.size.width, geo.size.height) * logoFraction)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private var dots: some View {
        TimelineView(.animation) { context in
            Canvas { gc, size in
                let d = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                // Reduce Motion: hold a calm static ring (no rotation, full intro).
                let t = reduceMotion ? 0 : context.date.timeIntervalSince(start)
                let rotSpeed = 0.35, waveSpeed = 1.6

                for (idx, ring) in rings.enumerated() {
                    let intro = reduceMotion ? 1 : introProgress(t: t, delay: Double(idx) * 0.09)
                    let rot = ring.dir * t * rotSpeed
                    for i in 0..<ring.count {
                        let base = 2 * .pi * Double(i) / Double(ring.count)
                        let a = base + rot
                        let r = ring.rf * d * intro                       // spiral out from centre
                        let x = c.x + r * cos(a)
                        let y = c.y + r * sin(a)
                        let wave = 0.5 + 0.5 * sin(2 * base - t * waveSpeed + ring.phase)
                        let rad = ring.dotf * d * (0.55 + 0.55 * wave) * intro
                        let alpha = (0.45 + 0.55 * wave) * intro
                        guard rad > 0.2, alpha > 0.01 else { continue }
                        gc.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad,
                                                       width: 2 * rad, height: 2 * rad)),
                                with: .color(.white.opacity(alpha)))
                    }
                }
            }
        }
    }

    /// Ease-out 0→1 build-in (per-ring delayed) for the intro spiral, then holds.
    private func introProgress(t: Double, delay: Double) -> Double {
        let x = max(0, min(1, (t - delay) / 0.7))
        return 1 - pow(1 - x, 3) // easeOutCubic
    }
}
