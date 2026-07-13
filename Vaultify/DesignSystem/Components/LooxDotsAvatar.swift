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

    /// Two rings, radii as fractions of the HALF-size; dot radius ∝ ring radius
    /// (the swirl's rule), counts tuned for a small mark.
    private let rings: [(rf: CGFloat, count: Int)] = [(0.56, 8), (0.85, 14)]

    var body: some View {
        let accent = Color(rgb: env.theme.active.accent)
        ZStack {
            Circle().fill(Color(rgb: env.theme.active.accentSoft).opacity(0.45))
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
            for (k, ring) in rings.enumerated() {
                let radius = ring.rf * half
                let dotR = 0.16 * radius / CGFloat(k + 1) + 0.02 * half // gentle growth outward
                let offset = Double(k % 2) * (.pi / Double(ring.count))
                for i in 0..<ring.count {
                    let a = 2 * .pi * Double(i) / Double(ring.count) + offset
                    let x = c.x + radius * cos(a)
                    let y = c.y + radius * sin(a)
                    gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                                   width: 2 * dotR, height: 2 * dotR)),
                            with: .color(accent.opacity(0.5)))
                }
            }
        }
        .accessibilityHidden(true)
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
