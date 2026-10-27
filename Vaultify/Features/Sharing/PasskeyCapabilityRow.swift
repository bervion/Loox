import SwiftUI

/// One passkey slot in the share-config sheet (capability v2): rpId +
/// user name, and a three-mode menu. `askEachTime` keeps the private key on
/// the owner's device (INV-07); hand-over goes through the same confirmation
/// as TOTP seeds (INV-08), decided by `ShareCapabilityDraft`.
struct PasskeyCapabilityRow: View {
    let passkey: PasskeyInfo
    let capability: FieldCapability
    /// Every mode the owner picks (see `FieldCapabilityRow.onSelect`).
    let onSelect: (FieldCapability) -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            VaultIcon(Icons.passkey, size: Metric.iconInline)
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
                Button { onSelect(.passkey(.none)) } label: { Text("Off") }
                Button { onSelect(.passkey(.askEachTime)) } label: { Text("Ask each time") }
                Button { onSelect(.passkey(.shared)) } label: {
                    Label { Text("Hand over key…") } icon: { VaultIcon(Icons.alert) }
                }
            } label: {
                HStack(spacing: Space.s1) {
                    Text(modeTitle).vaultType(.callout)
                    VaultIcon(Icons.chevronDown, size: 14)
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
