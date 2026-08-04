import SwiftUI

/// Transient "Copied <label>" capsule driven by `ClipboardService.recentCopyLabel`.
/// Attach with `.overlay(alignment: .bottom)` on any root that performs copies
/// (main shell, onboarding) plus an animation keyed on `recentCopyLabel`.
struct CopyToastOverlay: View {
    /// Space kept below the capsule — above the tab bar in the shell, above the
    /// bottom CTA in flows that pin a button to the safe area.
    var bottomClearance: CGFloat = Metric.controlLarge + Space.s8

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let label = env.clipboard.recentCopyLabel {
            let theme = env.theme.active
            HStack(spacing: Space.s2) {
                VaultIcon(Icons.checkCircle, size: Metric.iconInline)
                    .foregroundStyle(Color(rgb: theme.success))
                Text(appString("Copied \(label)")).vaultType(.subhead).fontWeight(.medium)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            // Reduce Transparency gets an opaque capsule: the toast floats over the
            // item list, and blurred text over a busy row is exactly what that setting
            // exists to remove.
            .background {
                if reduceTransparency {
                    Capsule().fill(Color(rgb: theme.surfaceFloatingSolid))
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .elevation(.level2)
            .padding(.bottom, bottomClearance)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
