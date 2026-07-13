import SwiftUI

/// Apple-boot-style brand swirl: the Loox six-circle symbol centred in rings of
/// rainbow dots (the `SwirlGradient` mesh masked into moving circles, so each dot
/// takes the gradient colour at its position). A reusable loading/brand indicator
/// with three modes:
///
/// - `.reveal` — plays once: dots emanate from the logo and settle into the four
///   static rings, then hold. (Default; the calm brand mark.)
/// - `.loop` — a continuous loading pulse: dots stream outward from the inner ring
///   to the outer ring, growing and fading to alpha 0 as they reach it, forever.
/// - `.dismiss` — the settled rings burst outward and fade to nothing, once.
///
/// Same mathematical layout throughout: four equally-spaced rings, 24 dots each,
/// odd rings offset half a step (interleave), dot radius ∝ ring radius. Driven by
/// `TimelineView(.animation)` at 60fps; it stops ticking once a one-shot completes.
struct LooxSwirlAnimationView: View {
    enum Mode: Equatable { case reveal, loop, dismiss }

    var mode: Mode = .reveal
    /// Centre logo height as a fraction of the view's smaller dimension.
    var logoFraction: CGFloat = 0.26

    // Layout (fractions of the view's smaller dimension).
    private let perRing = 24
    private let dotK: CGFloat = 0.047
    private let ringInner: CGFloat = 0.32      // ring 1
    private let ringStep: CGFloat = 0.047      // → ring 4 at 0.461
    private var ringOuter: CGFloat { ringInner + 3 * ringStep }
    private var halfStep: Double { .pi / Double(perRing) }
    /// Emanation origin: the logo's edge — dots are born under the mark and
    /// travel out, never popping up in the white gap.
    private var spawnR: CGFloat { logoFraction * 0.5 }
    /// Total pattern swirl during a journey (~57°, ease-out), also measured.
    private let swirl: Double = 57 * .pi / 180

    // Timings (from the reference: ~0.2s ring stagger, ~1s travel per ring).
    private let ringStagger: Double = 0.20
    private let travel: Double = 1.0
    private var revealDur: Double { 3 * ringStagger + travel }   // 1.6s
    private let dismissDur: Double = 1.0
    /// Slow constant rotation layered over the loop cycle so the pattern never
    /// visibly stalls (rad/s ≈ 15°/s).
    private let loopDrift: Double = 15 * .pi / 180

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var ticking = true
    @State private var runID = 0

    /// Drawing area beyond the nominal frame so the spreading rings spill past
    /// the square instead of being cut off at its edge.
    private let overscan: CGFloat = 1.8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("SwirlGradient")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width * overscan, height: geo.size.height * overscan)
                    .mask { maskContent }
                    .frame(width: geo.size.width * overscan, height: geo.size.height * overscan)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                Image("BrandSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(height: min(geo.size.width, geo.size.height) * logoFraction)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
        .onAppear(perform: restart)
        .onChange(of: mode) { _, _ in restart() }
    }

    @ViewBuilder private var maskContent: some View {
        if ticking && !reduceMotion {
            TimelineView(.animation) { context in
                canvas(t: context.date.timeIntervalSince(start))
            }
        } else {
            // Frozen frame once a one-shot finishes (or under Reduce Motion).
            canvas(t: frozenTime)
        }
    }

    private var frozenTime: Double {
        switch mode {
        case .reveal: return revealDur       // settled rings
        case .loop:   return 0               // Reduce Motion: hold the settled look
        case .dismiss: return dismissDur     // fully dismissed (empty)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { gc, size in draw(gc, size, t) }
    }

    /// Restart the animation from the top; loop keeps ticking, one-shots stop.
    private func restart() {
        start = .now
        runID += 1
        let id = runID
        ticking = true
        guard !reduceMotion else { ticking = false; return }
        let stopAfter: Double? = mode == .loop ? nil : (mode == .reveal ? revealDur : dismissDur)
        if let stopAfter {
            Task {
                try? await Task.sleep(for: .seconds(stopAfter + 0.05))
                if runID == id { ticking = false }
            }
        }
    }

    // MARK: Drawing

    private func draw(_ gc: GraphicsContext, _ size: CGSize, _ t: Double) {
        // The canvas is overscan-sized; ring geometry stays relative to the
        // NOMINAL frame so only the spill-over gains room, not the layout.
        let d = min(size.width, size.height) / overscan
        let c = CGPoint(x: size.width / 2, y: size.height / 2)

        // Reduce Motion: a calm, fully settled ring set (nothing for dismiss).
        if reduceMotion {
            if mode != .dismiss { drawSettled(gc, c, d) }
            return
        }

        switch mode {
        case .reveal:  drawReveal(gc, c, d, t)
        case .loop:    drawLoop(gc, c, d, t)
        case .dismiss: drawFadeOut(gc, c, d, t)
        }
    }

    /// The measured emanation (shared by reveal and the loop's first act): the
    /// OUTER ring blooms first from just outside the logo, trailing rings launch
    /// ~0.2s apart and settle inward-last. Each ring swirls ~57° along ITS OWN
    /// journey (later rings still turning while earlier ones have settled — the
    /// staggered, non-uniform look of the reference). Dot size follows its
    /// current radius; alpha follows ring progress.
    private func drawEmanate(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double,
                             drift: Double = 0) {
        for k in 0..<4 {                            // k = 0 OUTER … 3 inner
            let p = easeOutCubic(clamp01((t - Double(k) * ringStagger) / travel))
            guard p > 0.001 else { continue }
            let rf = ringOuter - CGFloat(k) * ringStep
            let radius = (spawnR + (rf - spawnR) * p) * d
            let dotR = dotK * radius * (0.6 + 0.4 * p)
            // Interleave parity by the ring's FINAL slot (settled pattern matches
            // the static layout); the ring turns INTO its final angle as p → 1.
            ring(gc, c, radius: radius, dotR: dotR, alpha: p,
                 angleOffset: Double((3 - k) % 2) * halfStep - swirl * (1 - p) + drift)
        }
    }

    /// One-shot reveal: the emanation, frozen once settled.
    private func drawReveal(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        drawEmanate(gc, c, d, min(t, revealDur))
    }

    /// Loading loop: one full breath per cycle — the emanation plays out and
    /// flows STRAIGHT into the dispersal (no held beat), everything fades to 0,
    /// rests a blink, and starts over. The pattern never stops turning: a slow
    /// constant drift rides on top of the journey swirl.
    private func drawLoop(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        let rest = 0.2
        let cycle = revealDur + dismissDur + rest
        let tc = t.truncatingRemainder(dividingBy: cycle)
        let drift = loopDrift * tc                  // never stops turning
        if tc < revealDur {
            drawEmanate(gc, c, d, tc, drift: drift)
        } else if tc < revealDur + dismissDur {
            drawFadeOut(gc, c, d, tc - revealDur, drift: drift)
        }
        // else: rest — a blink before the next breath (the drift reset at the
        // cycle wrap is invisible: nothing is on screen).
    }

    /// The dispersal: rings scale outward and keep turning at the same time,
    /// decelerating (ease-out) — dots grow with their radius (the size formula)
    /// and fade as they spread, everything blended in one smooth motion. Used
    /// for the dismiss one-shot and the fade act of each loop cycle.
    private func drawFadeOut(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double,
                             drift: Double = 0) {
        let p = easeOutCubic(clamp01(t / dismissDur))
        let alpha = pow(1 - p, 1.3)                 // fainter as it spreads
        guard alpha > 0.01 else { return }
        for k in 0..<4 {
            let rf = ringInner + CGFloat(k) * ringStep
            let radius = rf * d * (1 + CGFloat(p) * 0.6)   // scale out, decelerating
            ring(gc, c, radius: radius, dotR: dotK * radius, alpha: alpha,
                 angleOffset: Double(k % 2) * halfStep + 0.55 * swirl * p + drift)
        }
    }

    /// The static four-ring set (Reduce Motion fallback).
    private func drawSettled(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat) {
        for k in 0..<4 {
            let rf = ringInner + CGFloat(k) * ringStep
            let radius = rf * d
            ring(gc, c, radius: radius, dotR: dotK * radius, alpha: 1,
                 angleOffset: Double(k % 2) * halfStep)
        }
    }

    /// Draw one ring of `perRing` dots at `radius` with `alpha`.
    private func ring(_ gc: GraphicsContext, _ c: CGPoint, radius: CGFloat, dotR: CGFloat,
                      alpha: Double, angleOffset: Double) {
        guard dotR > 0.2 else { return }
        for i in 0..<perRing {
            let a = 2 * .pi * Double(i) / Double(perRing) + angleOffset
            let x = c.x + radius * cos(a)
            let y = c.y + radius * sin(a)
            gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: 2 * dotR, height: 2 * dotR)),
                    with: .color(.white.opacity(alpha)))
        }
    }

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
    private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}
