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
    var logoFraction: CGFloat = 0.26
    /// Same dot count on every ring (the even-angle rule) and dot radius as a
    /// fraction of each ring's radius, so the gaps read even everywhere.
    private let perRing = 24
    private let dotK: CGFloat = 0.047

    private let duration: Double = 1.3
    private let entry: Double = 0.7      // per-ring fade/grow time
    private let delayStep: Double = 0.08 // inner→outer emanation wave

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var animating = true

    private struct Ring { let rf: CGFloat; let offset: Double }
    private let rings: [Ring] = LooxSwirlAnimationView.makeRings()

    /// Four equally-spaced rings with a roomy centre gap. Odd rings are rotated by
    /// half the angular step so adjacent rings interleave (brick pattern), matching
    /// the reference. Every ring keeps the same dot count; dot size grows with the
    /// ring radius (see `dotK`), so gaps stay even from the inner ring outward.
    private static func makeRings() -> [Ring] {
        let per = 24
        return (0..<4).map { k in
            let rf = 0.32 + Double(k) * 0.047                 // 0.32 … 0.461
            let offset = Double(k % 2) * (.pi / Double(per))  // half-step interleave
            return Ring(rf: CGFloat(rf), offset: offset)
        }
    }

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
            let spin = (0.4 * .pi) * (1 - rp)            // gentle rotation as it settles
            // Emanate from near the logo edge (82% → 100% of the ring radius) so the
            // rings stay separated at the start instead of clumping at the centre.
            let radius = ring.rf * d * (0.82 + 0.18 * rp)
            let dotR = dotK * radius * (0.6 + 0.4 * rp)  // subtle pop-in
            guard dotR > 0.2 else { continue }
            for i in 0..<perRing {
                let a = 2 * .pi * Double(i) / Double(perRing) + ring.offset + spin
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
