import SwiftUI

/// One passkey slot in the share-config sheet (capability v2): rpId +
/// user name, and a three-mode menu. `askEachTime` keeps the private key on
/// the owner's device (INV-07); hand-over routes through the parent's
/// irreversibility warning like TOTP seeds (INV-08).
struct PasskeyCapabilityRow: View {
    let passkey: PasskeyInfo
    @Binding var capability: FieldCapability
    var requestHandOver: (FieldCapability) -> Void = { _ in }

    var body: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.passkey, size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: passkey.relyingParty)
                    .vaultType(.body).themedForeground()
                    .lineLimit(1)
                Text(verbatim: passkey.userName)
                    .vaultType(.footnote).themedForeground(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button { capability = .passkey(.none) } label: { Text("Off") }
                Button { capability = .passkey(.askEachTime) } label: { Text("Ask each time") }
                Button { requestHandOver(.passkey(.shared)) } label: {
                    Label("Hand over key…", image: Icons.alert)
                }
            } label: {
                HStack(spacing: Space.s1) {
                    Text(modeTitle).vaultType(.callout)
                    PolarisIcon(Icons.chevronDown, size: 14)
                }
                .themedForeground(.accentText)
            }
        }
        .frame(minHeight: Metric.hitMin)
    }

    private var modeTitle: LocalizedStringKey {
        switch capability {
        case .passkey(.askEachTime): "Ask each time"
        case .passkey(.shared): "Key handed over"
        default: "Off"
        }
    }
}
