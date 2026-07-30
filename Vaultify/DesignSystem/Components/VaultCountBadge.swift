import SwiftUI

/// Small pill carrying a live count beside a title or a tile label ("3" issues,
/// "5" codes). Tinted by the caller so the badge speaks in the same voice as what
/// it counts: the section's severity, or the tile's own hue.
///
/// Capped at 99 — a three-digit count would widen the pill past the label it sits
/// beside, and the exact number stops mattering long before that. The digits are
/// hidden from VoiceOver: the surrounding title owns the spoken form, which reads
/// "Needs Attention, 3 items" rather than a bare number after it.
struct VaultCountBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text(verbatim: "\(min(count, 99))")
            .vaultType(.caption)
            .fontWeight(.bold)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s1)
            .frame(minWidth: 18, minHeight: 18)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityHidden(true)
    }
}
