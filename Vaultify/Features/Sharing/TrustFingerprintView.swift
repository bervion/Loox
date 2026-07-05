import SwiftUI

/// The one-time out-of-band trust ceremony (ADR-4): both people read the same
/// short code — derived from the owner's signing key and the recipient's
/// participant key — over a call or in person. Confirming TOFU-pins the pair;
/// a later key change is rejected, not silently re-pinned.
struct TrustFingerprintView: View {
    let code: String
    let recipientLabel: String
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: Space.s5) {
            PolarisIcon(Icons.shield, size: Metric.iconTile)
                .themedForeground(.accent)
            Text("Compare this code")
                .vaultType(.section)
                .themedForeground()
            Text("Ask \(recipientLabel) to read the code shown on their device. Confirm only if both codes match exactly — this is what proves you're sharing with the right person.")
                .vaultType(.callout)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Text(verbatim: code)
                .font(.vaultCode(size: 28))
                .monospacedDigit()
                .themedForeground()
                .padding(.vertical, Space.s4)
                .padding(.horizontal, Space.s5)
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
            Button {
                onConfirm()
            } label: {
                Text("The codes match")
                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
    }
}
