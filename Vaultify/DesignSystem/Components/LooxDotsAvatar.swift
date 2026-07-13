import SwiftUI

/// The Loox default avatar: the brand spark centred in TWO static rings of
/// dots — the same even-angle, half-step-interleaved layout as the restore
/// swirl, scaled down — tinted softly from the theme accent. Shown wherever an
/// identity has no custom photo.
///
/// With `animatesCamera` the spark morphs into a camera glyph and back on a
/// bubbly spring loop — the Profile screen's "add a photo" invitation. The
/// rings themselves never animate. Reduce Motion holds the spark.
struct LooxDotsAvatar: View {
    var size: CGFloat
    var animatesCamera: Bool = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCamera = false

    /// Measured off the Apple Account mark: two CLOSE rings of 18 dots each
    /// (inner at 79% of the outer radius, half-step interleaved), outer dots
    /// ~1.5x larger, with per-dot size/opacity variation for the sparkle. No
    /// background disc.
    private let perRing = 18
    private let outerRF: CGFloat = 0.86   // of the half-size
    private let innerRF: CGFloat = 0.86 * 0.79

    @State private var revealing = false
    @State private var revealStart = Date.now
    /// Reveal choreography (measured off the reference): dots emanate from near
    /// the logo, growing and fading in while the pattern swirls ~57° ease-out;
    /// the outer ring leads, the inner follows ~0.15s later.
    private let revealTravel: Double = 0.55
    private let revealStagger: Double = 0.15
    private var revealDur: Double { revealTravel + revealStagger }

    /// Brand dot blue (#61C0FF) — fixed, softer than the accent by design.
    private let dotColor = Color(rgb: 0x61C0FF)

    var body: some View {
        let accent = Color(rgb: env.theme.active.accent)
        ZStack {
            // Card-white CORE disc (inside the rings, hugging the glyph) so the
            // centre lifts off grouped-gray canvases while the dots radiate
            // beyond it onto the page.
            Circle()
                .fill(Color(rgb: env.theme.active.elevatedBackground))
                .frame(width: size * 0.55, height: size * 0.55)
            dotsLayer(accent: dotColor)
            centerGlyph(accent: accent)
        }
        .frame(width: size, height: size)
        .task(id: animatesCamera) {
            guard animatesCamera, !reduceMotion else { showCamera = false; return }
            // One-shot ring reveal on appear, then the canvas freezes settled.
            revealStart = .now
            revealing = true
            Task {
                try? await Task.sleep(for: .seconds(revealDur + 0.05))
                revealing = false
            }
            // Bubbly swap loop: spark ↔ camera every beat, springy like a bubble.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                    showCamera.toggle()
                }
            }
        }
    }

    /// Ticks only during the reveal; otherwise a single settled frame.
    @ViewBuilder private func dotsLayer(accent: Color) -> some View {
        if revealing && !reduceMotion {
            TimelineView(.animation) { context in
                dotsCanvas(t: context.date.timeIntervalSince(revealStart), accent: accent)
            }
        } else {
            dotsCanvas(t: revealDur, accent: accent)
        }
    }

    private func dotsCanvas(t: Double, accent: Color) -> some View {
        Canvas { gc, canvasSize in
            let half = min(canvasSize.width, canvasSize.height) / 2
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let spawn = 0.30 * half   // just outside the centre glyph
            // (ring radius, base dot radius); OUTER first — it leads the reveal.
            let rings: [(radius: CGFloat, dotR: CGFloat)] = [
                (outerRF * half, 0.082 * half),
                (innerRF * half, 0.055 * half),
            ]
            for (k, ring) in rings.enumerated() {
                let p = easeOutCubic(max(0, min(1, (t - Double(k) * revealStagger) / revealTravel)))
                guard p > 0.001 else { continue }
                let radius = spawn + (ring.radius - spawn) * p
                let spin = -(57 * Double.pi / 180) * (1 - p)   // swirl into place
                // Interleave parity by final slot (inner ring offset 0).
                let offset = Double((k + 1) % 2) * (.pi / Double(perRing)) + spin
                for i in 0..<perRing {
                    let a = 2 * .pi * Double(i) / Double(perRing) + offset
                    let x = c.x + radius * cos(a)
                    let y = c.y + radius * sin(a)
                    // Deterministic sparkle: each dot gets its own size/opacity.
                    let h1 = hash(k, i, 1), h2 = hash(k, i, 2)
                    let dotR = ring.dotR * (0.85 + 0.3 * h1) * (0.6 + 0.4 * p)
                    // #61C0FF is already soft — sparkle in the upper opacity band.
                    let alpha = (0.55 + 0.45 * h2) * p
                    gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                                   width: 2 * dotR, height: 2 * dotR)),
                            with: .color(accent.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// Deterministic per-dot pseudo-random in [0, 1) (fract-sin hash).
    private func hash(_ k: Int, _ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(k) * 12.9898 + Double(i) * 78.233 + Double(salt) * 37.719) * 43758.5453
        return x - floor(x)
    }

    /// Spark (or, while inviting, the camera) — both tinted the theme accent,
    /// swapping with a scale "bubble" transition.
    @ViewBuilder private func centerGlyph(accent: Color) -> some View {
        ZStack {
            if showCamera {
                PolarisIcon(Icons.camera, size: size * 0.30)
                    .foregroundStyle(accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image("LooxSpark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size * 0.34, height: size * 0.34)
                    .foregroundStyle(accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
