import SwiftUI

/// The Loox six-circle symbol as a calm, self-contained breathing mark — the
/// resting brand logo WITHOUT the cluster/memoji choreography of the full
/// `LooxCloudAnimationView`. Renders the six gradient circles, the radial
/// glow, and (optionally) the white sparkle from `LooxCanvas`, scaled
/// aspect-fit into its frame.
///
/// Used where the symbol should read as "alive but idle": the lock screen
/// while waiting to authenticate (`ready == false` → dimmed + desaturated),
/// and as the backdrop of the unlock wink (`showSparkle == false`, so the
/// centred memoji is not covered by the star).
struct LooxLogoBreatheView: View {
    /// When false the mark reads as "not ready yet" — dimmed and desaturated.
    var ready: Bool = true
    /// The centred white sparkle. Turn off when another element occupies the
    /// centre (the wink memoji disc).
    var showSparkle: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            // Slow ~4s breathe: a gentle scale + glow/sparkle pulse. Reduce
            // Motion holds it perfectly still.
            let phase = reduceMotion
                ? 0
                : sin(context.date.timeIntervalSinceReferenceDate * (2 * .pi / 4))
            GeometryReader { geo in
                let scale = min(geo.size.width / LooxCanvas.size.width,
                                geo.size.height / LooxCanvas.size.height)
                let origin = CGPoint(
                    x: (geo.size.width - LooxCanvas.size.width * scale) / 2,
                    y: (geo.size.height - LooxCanvas.size.height * scale) / 2)

                ZStack {
                    ForEach(0..<6, id: \.self) { i in
                        let d = LooxCanvas.logoDiameter * scale
                        Circle()
                            .fill(LooxCanvas.logoGradients[i].linear)
                            .opacity(LooxCanvas.logoOpacities[i])
                            .frame(width: d, height: d)
                            .position(x: origin.x + LooxCanvas.logoCenters[i].x * scale,
                                      y: origin.y + LooxCanvas.logoCenters[i].y * scale)
                    }

                    let gd = LooxCanvas.glowDiameter * scale
                    Circle()
                        .fill(RadialGradient(
                            colors: [.white.opacity(0.40 + 0.12 * phase), .white.opacity(0)],
                            center: .center, startRadius: 0, endRadius: gd / 2))
                        .frame(width: gd, height: gd)
                        .position(x: origin.x + LooxCanvas.glowCenter.x * scale,
                                  y: origin.y + LooxCanvas.glowCenter.y * scale)

                    if showSparkle {
                        let sd = LooxCanvas.starDiameter * scale
                        LooxStarShape()
                            .fill(.white)
                            .frame(width: sd, height: sd)
                            .position(x: origin.x + LooxCanvas.center.x * scale,
                                      y: origin.y + LooxCanvas.center.y * scale)
                    }
                }
                .scaleEffect(1 + 0.02 * phase, anchor: .center)
            }
        }
        .opacity(ready ? 1 : 0.55)
        .saturation(ready ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.5), value: ready)
        .accessibilityHidden(true)
    }
}
