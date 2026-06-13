import Foundation
import AuthenticationServices

/// Keeps the system AutoFill index (`ASCredentialIdentityStore`) in sync with
/// the unlocked vault so iOS can suggest Vaultify logins on the QuickType bar.
/// Only non-secret data (domain, username, item id) is published — never a
/// password. No-op when the user hasn't enabled Vaultify for AutoFill.
enum CredentialIdentityService {

    /// Replace the published identities with the current login items.
    static func refresh(items: [VaultItem]) {
        let identities: [ASPasswordCredentialIdentity] = items.compactMap { item in
            guard item.passwordField?.value.isEmpty == false,
                  let user = item.usernameField?.value, !user.isEmpty,
                  let host = item.autofillHost else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                user: user,
                recordIdentifier: item.id)
        }
        Task {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled else { return }
            try? await store.replaceCredentialIdentities(identities)
        }
    }

    /// Drop all published identities (called when the vault locks).
    static func clear() {
        Task {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled else { return }
            try? await store.removeAllCredentialIdentities()
        }
    }
}
