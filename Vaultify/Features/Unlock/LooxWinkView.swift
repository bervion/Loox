import SwiftUI

/// Unlock-success flourish: the REAL brand animation's opening act, played over
/// the freshly-unlocked app. The six-circle logo morphs and bursts into the
/// vault cluster — the winking memoji ringed by capability bubbles (the same
/// `LooxCloudAnimationView` scene the welcome landing opens with) — then fades
/// out and hands control to the app. The caller skips it under Reduce Motion.
struct LooxWinkView: View {
    let onFinished: () -> Void
    /// How long the opening act runs before the hand-off: through the logo
    /// morph (~1.6s) and the full first cluster scene, ending just before the
    /// loop would swap to the second theme (4.7s).
    var duration: TimeInterval = 4.2

    /// Fresh controller → the loop clock starts at the LOGO phase, so the act
    /// always plays from the top (and the wink clip rewinds with it).
    @StateObject private var controller = LooxLaunchController()
    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.62, 280)
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                LooxCloudAnimationView(controller: controller)
                    .frame(width: side, height: side * 0.82)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .opacity(visible ? 1 : 0)
        .task {
            withAnimation(.easeIn(duration: 0.2)) { visible = true }
            try? await Task.sleep(for: .seconds(duration))
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
            try? await Task.sleep(for: .seconds(0.3))
            onFinished()
        }
        .accessibilityHidden(true)
    }
}
