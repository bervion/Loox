import SwiftUI

/// Unlock-success flourish: the brand animation's opening act, played over the
/// freshly-unlocked app. The six-circle logo glides from the lock screen's spot
/// down to centre while it morphs and bursts into the vault cluster — the
/// winking memoji ringed by capability bubbles (the same `LooxCloudAnimationView`
/// scene the welcome landing opens with) — then fades into the app. The caller
/// skips it under Reduce Motion.
struct LooxWinkView: View {
    let onFinished: () -> Void
    /// Total act length before the fade hand-off: ~0.3s of the logo, then the
    /// burst into the first cluster scene.
    var duration: TimeInterval = 1.3
    /// Skip most of the loop's logo phase (burst hits at 1.6s) so only ~0.3s
    /// of resting logo plays before the morph.
    private let clockStart: TimeInterval = 1.3

    /// Fresh controller per unlock; its loop clock is rewound to `clockStart`
    /// on appear so the act always plays the same slice.
    @StateObject private var controller = LooxLaunchController()
    @State private var visible = false
    /// Drives the glide: false = at the lock screen's logo spot (small),
    /// true = settled at centre (full size).
    @State private var settled = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.62, 280)
            // The lock screen's mark is 132pt, centred slightly above the middle
            // (title + subtitle sit below it) — start there and glide down.
            let startScale = 132 / side
            ZStack {
                Color.platformBackground.ignoresSafeArea()
                LooxCloudAnimationView(controller: controller)
                    .frame(width: side, height: side * 0.82)
                    .scaleEffect(settled ? 1 : startScale)
                    .position(x: geo.size.width / 2,
                              y: geo.size.height * (settled ? 0.5 : 0.42))
            }
        }
        .opacity(visible ? 1 : 0)
        .task {
            // Rewind the loop clock so the burst lands ~0.3s in.
            controller.loopEpoch = Date.now.addingTimeInterval(-clockStart)
            withAnimation(.easeIn(duration: 0.15)) { visible = true }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { settled = true }
            try? await Task.sleep(for: .seconds(duration))
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
            try? await Task.sleep(for: .seconds(0.3))
            onFinished()
        }
        .accessibilityHidden(true)
    }
}
