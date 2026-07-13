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
    private let logoEdge: CGFloat = 0.15       // reveal emanation origin

    // Timings.
    private let revealDur: Double = 1.3
    private let loopDur: Double = 2.6
    private let dismissDur: Double = 0.7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var ticking = true
    @State private var runID = 0

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
        let d = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)

        // Reduce Motion: a calm, fully settled ring set (nothing for dismiss).
        if reduceMotion {
            if mode != .dismiss { drawSettled(gc, c, d) }
            return
        }

        switch mode {
        case .reveal:  drawReveal(gc, c, d, t)
        case .loop:    drawLoop(gc, c, d, t)
        case .dismiss: drawDismiss(gc, c, d, t)
        }
    }

    /// One-shot: each ring emanates from the logo edge out to its position and stays.
    private func drawReveal(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        for k in 0..<4 {
            let rp = easeOutCubic(clamp01((t - Double(k) * 0.10) / 0.6))
            guard rp > 0.001 else { continue }
            let rf = ringInner + CGFloat(k) * ringStep
            let radius = (logoEdge + (rf - logoEdge) * rp) * d
            let spin = (0.35 * .pi) * (1 - rp)
            ring(gc, c, radius: radius, dotR: dotK * radius, alpha: rp,
                 angleOffset: Double(k % 2) * halfStep + spin)
        }
    }

    /// Continuous loading swirl: generations stream out FROM THE LOGO, each dot
    /// twisting as it travels (spiral arms), growing and fading to 0 at the outer
    /// ring, then wrapping (invisible at the wrap point).
    private func drawLoop(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        let gens = 5
        let twist = 0.6 * Double.pi                // gentle spiral per dot lifetime
        for g in 0..<gens {
            let u = ((t / loopDur) + Double(g) / Double(gens)).truncatingRemainder(dividingBy: 1)
            let radius = (logoEdge + CGFloat(u) * (ringOuter - logoEdge)) * d
            let fadeIn = min(u / 0.12, 1)          // avoid a pop at the wrap/spawn
            let alpha = fadeIn * (1 - u)           // 1 near the logo → 0 at the outer ring
            guard alpha > 0.01 else { continue }
            ring(gc, c, radius: radius, dotR: dotK * radius, alpha: alpha,
                 angleOffset: Double(g % 2) * halfStep + twist * u)
        }
    }

    /// One-shot: the settled rings expand outward and fade away to nothing.
    private func drawDismiss(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        let p = easeOutCubic(clamp01(t / dismissDur))
        let alpha = 1 - p
        guard alpha > 0.01 else { return }
        for k in 0..<4 {
            let rf = ringInner + CGFloat(k) * ringStep
            let radius = rf * d * (1 + CGFloat(p) * 0.5)
            ring(gc, c, radius: radius, dotR: dotK * radius, alpha: alpha,
                 angleOffset: Double(k % 2) * halfStep)
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
