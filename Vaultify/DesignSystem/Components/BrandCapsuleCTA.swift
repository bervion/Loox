import SwiftUI

/// The onboarding Continue button: a full-width capsule, brand blue when
/// enabled, opaque spec-gray when disabled (#EFEFF0 / #BABABD — never
/// translucent over content lifted by the keyboard). Optional busy spinner.
struct BrandCapsuleCTA: View {
    var title: LocalizedStringKey = "Continue"
    var enabled: Bool = true
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .vaultType(.body).fontWeight(.medium)
                .foregroundStyle(enabled ? .white : Color(rgb: 0xBABABD))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(enabled ? Color(rgb: 0x0065F4) : Color(rgb: 0xEFEFF0),
                            in: Capsule())
                .prominentButtonLoading(busy)
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
