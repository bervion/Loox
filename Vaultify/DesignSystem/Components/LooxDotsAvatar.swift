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

    var body: some View {
        let accent = Color(rgb: env.theme.active.accent)
        ZStack {
            dotRings(accent: accent)
            centerGlyph(accent: accent)
        }
        .frame(width: size, height: size)
        .task(id: animatesCamera) {
            guard animatesCamera, !reduceMotion else { showCamera = false; return }
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

    private func dotRings(accent: Color) -> some View {
        Canvas { gc, canvasSize in
            let half = min(canvasSize.width, canvasSize.height) / 2
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            // (ring radius, base dot radius) per the measured proportions.
            let rings: [(radius: CGFloat, dotR: CGFloat)] = [
                (innerRF * half, 0.055 * half),
                (outerRF * half, 0.082 * half),
            ]
            for (k, ring) in rings.enumerated() {
                let offset = Double(k % 2) * (.pi / Double(perRing)) // interleave
                for i in 0..<perRing {
                    let a = 2 * .pi * Double(i) / Double(perRing) + offset
                    let x = c.x + ring.radius * cos(a)
                    let y = c.y + ring.radius * sin(a)
                    // Deterministic sparkle: each dot gets its own size/opacity.
                    let h1 = hash(k, i, 1), h2 = hash(k, i, 2)
                    let dotR = ring.dotR * (0.85 + 0.3 * h1)
                    let alpha = 0.35 + 0.4 * h2
                    gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                                   width: 2 * dotR, height: 2 * dotR)),
                            with: .color(accent.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }

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
