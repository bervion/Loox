import SwiftUI

/// The onboarding Continue button: a full-width capsule filled with the theme
/// ACCENT — the button/action colour. The link hue (`accentText`) is reserved for
/// hyperlinks and text-link buttons, so a pinned CTA never paints link blue. The
/// label uses the WCAG-derived `accentForeground` pairing.
///
/// Disabled paints the OPAQUE control surface and the disabled-text token, never
/// `.opacity` — this CTA is pinned over content that scrolls behind it, and a
/// translucent bar would let that content bleed through. Optional busy spinner.
struct BrandCapsuleCTA: View {
    var title: LocalizedStringKey = "Continue"
    var enabled: Bool = true
    var busy: Bool = false
    /// Paints the destructive pair instead of the accent, for a step whose one
    /// action cannot be undone (a hand-over).
    var destructive: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        let fill = destructive ? theme.destructiveFill : theme.accentFill
        let label = destructive ? theme.onDestructive : theme.accentForeground
        Button(action: action) {
            Text(title)
                .vaultType(.body).fontWeight(.medium)
                .foregroundStyle(Color(rgb: enabled ? label : theme.textDisabled))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(Color(rgb: enabled ? fill : theme.controlBackground),
                            in: Capsule())
                .prominentButtonLoading(busy, tint: Color(rgb: label))
        }
        .buttonStyle(SolidCapsuleButtonStyle())
        .disabled(!enabled || busy)
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .padding(.horizontal, Space.s6)
        .padding(.bottom, Space.s4)
        // Some call sites pin this CTA outside the clamped step column — clamp
        // here too so it can never render as a screen-spanning bar on iPad.
        .vaultContentWidth(.form)
    }
}
