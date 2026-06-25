import Foundation
import AuthenticationServices

/// Keeps the system AutoFill index (`ASCredentialIdentityStore`) in sync with
/// the unlocked vault so iOS can suggest Vaultify logins on the QuickType bar.
/// Only non-secret data (domain, username, item id) is published — never a
/// password. No-op when the user hasn't enabled Vaultify for AutoFill.
enum CredentialIdentityService {

    /// Replace the published identities with the current login items. Also publishes
    /// one-time-code (2FA) identities on iOS 18+ for items carrying a TOTP secret, so iOS
    /// suggests Vaultify on one-time-code fields too.
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
            // Replace clears all types, so re-add OTP identities afterwards (ordered).
            try? await store.replaceCredentialIdentities(identities)
            if #available(iOS 18, *) {
                let otp = oneTimeCodeIdentities(items)
                if !otp.isEmpty { try? await store.saveCredentialIdentities(otp) }
            }
        }
    }

    /// One-time-code identities for items that carry a TOTP secret + a matchable host.
    @available(iOS 18, *)
    private static func oneTimeCodeIdentities(_ items: [VaultItem]) -> [ASOneTimeCodeCredentialIdentity] {
        items.compactMap { item in
            guard item.totpField != nil, let host = item.autofillHost else { return nil }
            let user = item.usernameField?.value
            let label = (user?.isEmpty == false) ? user! : (item.title.isEmpty ? host : item.title)
            return ASOneTimeCodeCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                label: label,
                recordIdentifier: item.id)
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
