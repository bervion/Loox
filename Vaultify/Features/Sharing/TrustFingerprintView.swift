import SwiftUI

/// Owner-side one-tap activation (ADR-4, single-confirm model): the recipient
/// pairs automatically, so the OWNER is the sole enforcement point — this
/// screen pins the recipient's key and publishes the grant. The safety code
/// (derived from both keys, also shown on the recipient's shared-item screen)
/// enables optional out-of-band comparison; a later key change is rejected,
/// not silently re-pinned.
struct TrustFingerprintView: View {
    let code: String
    let recipientLabel: String
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: Space.s5) {
            PolarisIcon(Icons.shield, size: Metric.iconTile)
                .themedForeground(.accent)
            Text("Ready to activate")
                .vaultType(.section)
                .themedForeground()
            Text("\(recipientLabel) has joined. Activate to give them access. To be sure it's really them, you can compare this safety code with the one shown at the bottom of the shared item on their device.")
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
                Text("Activate Sharing")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.gutter)
    }
}
