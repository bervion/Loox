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
    var logoFraction: CGFloat = 0.28
    /// Radial zigzag amplitude (fraction of dimension) that interleaves the dots.
    private let zig: CGFloat = 0.016

    private let duration: Double = 1.9
    private let entry: Double = 1.4      // per-ring spiral-in time
    private let delayStep: Double = 0.12 // stagger between rings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var animating = true

    private struct Ring { let rf: CGFloat; let count: Int; let dotBase: CGFloat; let offset: Double }
    private let rings: [Ring] = LooxSwirlAnimationView.makeRings()

    /// Four bands with a big centre gap; each rotated a little, and drawn with a
    /// per-dot radial zigzag + size variation so the dots interleave (woven look)
    /// instead of lining up into straight radial spokes.
    private static func makeRings() -> [Ring] {
        let n = 4
        return (0..<n).map { k in
            let f = Double(k) / Double(n - 1)               // 0…1 inner → outer
            let rf = 0.25 + f * 0.225                        // 0.25 … 0.475 (roomy centre gap)
            let count = max(12, Int((2 * .pi * rf / 0.076).rounded()))
            let dotBase = 0.009 + f * 0.008                  // small inner → large outer
            return Ring(rf: CGFloat(rf), count: count, dotBase: CGFloat(dotBase), offset: Double(k) * 0.13)
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
            let spin = (1.4 * .pi) * (1 - rp)              // spiral-in, unwinds to the layout
            for i in 0..<ring.count {
                let base = 2 * .pi * Double(i) / Double(ring.count) + ring.offset
                let a = base + spin
                // Alternate dots slightly in/out so bands interleave (woven look).
                let zigOffset = (i % 2 == 0) ? -zig : zig
                let radius = (ring.rf + zigOffset) * d * rp
                let x = c.x + radius * cos(a)
                let y = c.y + radius * sin(a)
                // Deterministic per-dot size variation for an organic, non-uniform feel.
                let variation = 0.78 + 0.32 * (0.5 + 0.5 * sin(Double(idx) * 12.9898 + Double(i) * 78.233))
                let dotR = ring.dotBase * d * variation * rp
                guard dotR > 0.2 else { continue }
                gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                               width: 2 * dotR, height: 2 * dotR)),
                        with: .color(.white.opacity(rp)))
            }
        }
    }

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
    private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}
