import SwiftUI

/// Centered biometric affordance for the lock screen: the Face ID / Touch ID
/// glyph takes the sparkle's spot at the heart of the breathing mark (a circular
/// progress replaces it while authenticating). The whole mark is the tap target
/// for a retry.
///
/// Uses the system biometric SF Symbol (the recognised affordance) — Polaris ships no
/// biometric glyph, so this is a deliberate exception to the Polaris-only icon rule.
struct BiometricBadge: View {
    /// Snapshotted by the lock screen: naming the biometry means probing the
    /// biometry daemon, which must never happen inside a `body`.
    let capability: BiometricCapability
    let authenticating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if authenticating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: capability.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        // White like the sparkle it replaces — part of the brand
                        // mark's artwork, not a themed surface.
                        .foregroundStyle(.white)
                }
            }
            // The mark itself is the control: full-logo hit area, well past 44pt.
            .frame(width: 132, height: 132)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(authenticating)
        .animation(.easeInOut(duration: 0.2), value: authenticating)
        .accessibilityLabel(Text("Unlock with \(capability.displayName)"))
    }
}
