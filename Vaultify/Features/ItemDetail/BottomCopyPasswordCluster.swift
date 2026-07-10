import SwiftUI

/// Floating bottom "Copy Password" affordance (T3 bottom ergonomics): the
/// password field is often the one value worth a re-copy after scrolling
/// down to review other fields, so a login item with a password gets a
/// one-tap shortcut once that row has scrolled out of view. Always mounted
/// by the caller for a qualifying item (so the layout's reserved bottom
/// clearance never jumps); `visible` only toggles its opacity/hit-testing —
/// fade only, no slide, and collapses instantly under Reduce Motion.
struct BottomCopyPasswordCluster: View {
    let visible: Bool
    let action: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        Button {
            // Guard like DetailFieldRow.copy(): a re-tap during the feedback
            // window must not restart the reset task and truncate the state.
            guard !copied else { return }
            action()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            HStack(spacing: Space.s2) {
                CopyMorphIcon(copied: copied, size: Metric.iconInline)
                Text(copied ? appString("Copied") : appString("Copy Password"))
                    .vaultType(.headline)
            }
            .padding(.horizontal, Space.s6)
            .frame(height: Metric.controlLarge)
            .frame(minWidth: Metric.hitMin)
        }
        .buttonStyle(.plain)
        .foregroundStyle(env.theme.active.color(.onAccent))
        .background(env.theme.active.color(.accent), in: Capsule())
        .elevation(.level2)
        .padding(.bottom, Space.s6)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(.vault(Motion.standard, reduceMotion: reduceMotion), value: visible)
    }
}
