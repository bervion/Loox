import SwiftUI

/// One-shot success flourish shown over the app the instant the vault unlocks:
/// the brand symbol with the Loox memoji giving a wink, then it clears to the
/// unlocked app underneath. Reuses the looping memoji player — we only show it
/// briefly, so it reads as a single wink. The caller skips it under Reduce
/// Motion, and `onFinished` hands control back after `duration`.
struct LooxWinkView: View {
    let onFinished: () -> Void
    /// How long the wink is shown before handing off to the app.
    var duration: TimeInterval = 1.4

    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            // Symbol sized off the narrower edge so it centres on any device.
            let side = min(geo.size.width * 0.62, 280)
            let canvasScale = side / LooxCanvas.size.width
            let disc = LooxTheme.centerDiameter * canvasScale
            let theme = LooxTheme.vault // the wink clip lives on the vault theme

            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ZStack {
                    // Six circles behind (sparkle off so it never covers the face).
                    LooxLogoBreatheView(ready: true, showSparkle: false)

                    // Centred memoji disc: pastel tint + the winking head, zoomed
                    // and nudged down to sit optically centred, clipped to the disc.
                    ZStack {
                        Circle().fill(theme.tint)
                        LooxMemojiPlayerView(resourceName: theme.memoji, restartKey: 0)
                            .frame(width: disc * theme.memojiZoom, height: disc * theme.memojiZoom)
                            .offset(y: disc * theme.memojiDrop)
                            .frame(width: disc, height: disc)
                            .clipShape(Circle())
                    }
                    // The inner frame fills the canvas with no letterboxing, so
                    // the disc's centre maps straight from canvas coordinates.
                    .frame(width: disc, height: disc)
                    .position(x: LooxCanvas.center.x * canvasScale,
                              y: LooxCanvas.center.y * canvasScale)
                }
                .frame(width: side, height: LooxCanvas.size.height * canvasScale)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
            }
        }
        .task {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { appeared = true }
            try? await Task.sleep(for: .seconds(duration))
            onFinished()
        }
        .accessibilityHidden(true)
    }
}
