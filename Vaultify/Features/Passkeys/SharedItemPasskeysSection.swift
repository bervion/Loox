import SwiftUI

/// Read-only "Passkeys" section on a RECIPIENT's shared-item detail. Mirrors
/// `ItemPasskeysSection` visually but surfaces shared-passkey metadata only
/// (relying party / user / mode) — the private key never appears in-app;
/// AutoFill is the only use path (decision 260705). Empty until authorized.
struct SharedItemPasskeysSection: View {
    let itemID: String
    @Environment(AppEnvironment.self) private var env

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
                            Divider().padding(.leading, Space.s4)
                        }
                    }
                }
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
                // Same card treatment as the other detail-screen cards — elevation
                // over a raw black/white stroke, tracking the live theme.
                .elevation(.level1)
                // The rows carry no action on purpose, so the screen has to say
                // where a shared passkey IS used. Without this the section reads
                // as a broken control next to the TOTP section's live Request
                // button, and the recipient keeps tapping a row that cannot do
                // anything: the private key never comes into the app.
                usageNote
            }
        }
    }

    @ViewBuilder
    private var usageNote: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Sign in with a shared passkey from the AutoFill suggestions on the website. The private key stays with the owner, so it never opens here.")
            if passkeys.contains(where: { $0.mode == .askEachTime }) {
                Text("When a sign-in needs approval, the owner has to have Loox open to answer.")
            }
        }
        .vaultType(.footnote)
        .themedForeground(.secondary)
        .padding(.horizontal, Space.s1)
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
            VaultIcon(Icons.personLockFilled, size: 22).foregroundStyle(Self.passkeyPurple)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(
            LinearGradient(colors: [.clear, Self.passkeyPurple.opacity(0.22)],
                           startPoint: .center, endPoint: .trailing)
        )
    }

    /// Names WHERE the passkey works, not just whether it is on — "Ready to
    /// use" on a row that does nothing when tapped is what made this section
    /// read as broken.
    private func modeLabel(_ mode: PasskeyFieldCapability) -> LocalizedStringKey {
        switch mode {
        case .shared: "Ready in AutoFill"
        case .askEachTime: "Owner approves each sign-in"
        case .none: "Not shared"
        }
    }

    private static let passkeyPurple = Color(rgb: 0x8B5CF6)
}
