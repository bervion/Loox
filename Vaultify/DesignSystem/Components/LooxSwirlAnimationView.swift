import SwiftUI

/// Apple-boot-style brand swirl, played ONCE on appear: the Loox six-circle
/// symbol sits at the centre while concentric rings of rainbow dots spiral out
/// from behind it, ring after ring, and settle into clean static rings. The dots
/// are the mesh-gradient image (`SwirlGradient`) masked into moving circles, so
/// each dot takes the gradient colour at its position.
///
/// Driven by `TimelineView(.animation)` (60fps) only for the ~2s reveal; once it
/// completes the view swaps to a single static frame so it stops ticking.
/// Reduce Motion shows the settled ring immediately. Purely decorative.
struct LooxSwirlAnimationView: View {
    /// Centre logo height as a fraction of the view's smaller dimension.
    var logoFraction: CGFloat = 0.32

    private let duration: Double = 1.9
    private let entry: Double = 1.4      // per-ring spiral-in time
    private let delayStep: Double = 0.12 // stagger between rings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var animating = true

    private struct Ring { let rf: CGFloat; let count: Int; let dotf: CGFloat; let dir: Double }
    private let rings: [Ring] = [
        Ring(rf: 0.215, count: 20, dotf: 0.0125, dir:  1),
        Ring(rf: 0.285, count: 26, dotf: 0.0130, dir: -1),
        Ring(rf: 0.355, count: 34, dotf: 0.0135, dir:  1),
        Ring(rf: 0.425, count: 42, dotf: 0.0140, dir: -1),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("SwirlGradient")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask { maskContent }
                Image("BrandSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(height: min(geo.size.width, geo.size.height) * logoFraction)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
        .onAppear(perform: replay)
    }

    @ViewBuilder private var maskContent: some View {
        if animating && !reduceMotion {
            TimelineView(.animation) { context in
                canvas(t: min(context.date.timeIntervalSince(start), duration))
            }
        } else {
            // Settled ring — no more ticking once the reveal is done.
            canvas(t: duration)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { gc, size in draw(gc, size, t) }
    }

    /// Play the one-shot reveal from the top, then freeze.
    private func replay() {
        guard !reduceMotion else { animating = false; return }
        start = .now
        animating = true
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            animating = false
        }
    }

    private func draw(_ gc: GraphicsContext, _ size: CGSize, _ t: Double) {
        let d = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for (idx, ring) in rings.enumerated() {
            // Per-ring spiral-in progress (staggered, ease-out).
            let rp = easeOutCubic(clamp01((t - Double(idx) * delayStep) / entry))
            guard rp > 0.001 else { continue }
            let radius = ring.rf * d * rp                  // grow out from centre
            let spin = ring.dir * (1.5 * .pi) * (1 - rp)   // unwind to the base angle
            let dotR = ring.dotf * d * rp
            guard dotR > 0.2 else { continue }
            for i in 0..<ring.count {
                let base = 2 * .pi * Double(i) / Double(ring.count)
                let a = base + spin
                let x = c.x + radius * cos(a)
                let y = c.y + radius * sin(a)
                gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                               width: 2 * dotR, height: 2 * dotR)),
                        with: .color(.white.opacity(rp)))
            }
        }
    }

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
    private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}
