import SwiftUI

/// Read-only "Passkeys" section on a RECIPIENT's shared-item detail. Mirrors
/// `ItemPasskeysSection` visually but surfaces shared-passkey metadata only
/// (relying party / user / mode) — the private key never appears in-app;
/// AutoFill is the only use path (decision 260705). Empty until authorized.
struct SharedItemPasskeysSection: View {
    let itemID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    private var passkeys: [SharedPasskeyDisplay] {
        env.sharedItems.sharedPasskeys(itemID: itemID)
    }

    var body: some View {
        if !passkeys.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Passkeys")
                    .vaultType(.sectionLabel)
                    .themedForeground(.secondary)
                    .padding(.horizontal, Space.s1)
                VStack(spacing: 0) {
                    ForEach(Array(passkeys.enumerated()), id: \.element.id) { index, passkey in
                        row(passkey)
                        if index < passkeys.count - 1 {
                            Divider().padding(.leading, Space.gutter)
                        }
                    }
                }
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.black : Color.white, lineWidth: 1)
                )
            }
        }
    }

    private func row(_ passkey: SharedPasskeyDisplay) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: passkey.relyingParty)
                    .vaultType(.body).themedForeground().lineLimit(1)
                Text(modeLabel(passkey.mode))
                    .vaultType(.caption).themedForeground(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            PolarisIcon(Icons.personLockFilled, size: 22).foregroundStyle(Self.passkeyPurple)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s3)
        .background(
            LinearGradient(colors: [.clear, Self.passkeyPurple.opacity(0.22)],
                           startPoint: .center, endPoint: .trailing)
        )
    }

    private func modeLabel(_ mode: PasskeyFieldCapability) -> LocalizedStringKey {
        switch mode {
        case .shared: "Ready to use"
        case .askEachTime: "Ask owner each time"
        case .none: "Off"
        }
    }

    private static let passkeyPurple = Color(rgb: 0x8B5CF6)
}
