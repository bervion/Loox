import Foundation
import AuthenticationServices

@MainActor
private enum CredentialIdentityRefreshGate {
    private static var generation = 0
    private static var tail: Task<Void, Never>?

    static func next() -> Int {
        generation += 1
        return generation
    }

    static func isCurrent(_ token: Int) -> Bool {
        token == generation
    }

    static func enqueue(_ operation: @escaping () async -> Void) {
        let previous = tail
        tail = Task {
            _ = await previous?.value
            await operation()
        }
    }
}

/// Keeps the system AutoFill index (`ASCredentialIdentityStore`) in sync with
/// the unlocked vault so iOS can suggest Vaultify logins on the QuickType bar.
/// Only non-secret data (domain, username, item id) is published — never a
/// password or passkey private key. No-op when the user hasn't enabled Vaultify
/// for AutoFill.
enum CredentialIdentityService {
    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment.keys.contains { $0.hasPrefix("XCTest") }
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }

    /// Replace the published identities with the current login items. Also publishes
    /// passkey identities and one-time-code (2FA) identities on iOS 18+.
    @MainActor
    static func refresh(items: [VaultItem], passkeys: [PasskeyInfo]) {
        guard !isRunningUnitTests else { return }
        let token = CredentialIdentityRefreshGate.next()
        let passwordIdentities: [ASPasswordCredentialIdentity] = items.compactMap { item in
            guard item.passwordField?.value.isEmpty == false,
                  let user = item.usernameField?.value, !user.isEmpty,
                  let host = item.autofillHost else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                user: user,
                recordIdentifier: item.id)
        }
        let passkeyIdentities = passkeys.map { $0.credentialIdentity() }
        CredentialIdentityRefreshGate.enqueue {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled,
                  await CredentialIdentityRefreshGate.isCurrent(token) else { return }
            // Replace clears all types, so re-add OTP identities afterwards (ordered).
            let passwordEntries = passwordIdentities.map { $0 as any ASCredentialIdentity }
            try? await store.replaceCredentialIdentities(passwordEntries)
            guard await CredentialIdentityRefreshGate.isCurrent(token) else { return }
            var secondary = passkeyIdentities.map { $0 as any ASCredentialIdentity }
            if #available(iOS 18, *) {
                let otp = oneTimeCodeIdentities(items)
                secondary.append(contentsOf: otp.map { $0 as any ASCredentialIdentity })
            }
            if !secondary.isEmpty {
                try? await store.saveCredentialIdentities(secondary)
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
    @MainActor
    static func clear() {
        guard !isRunningUnitTests else { return }
        let token = CredentialIdentityRefreshGate.next()
        CredentialIdentityRefreshGate.enqueue {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled,
                  await CredentialIdentityRefreshGate.isCurrent(token) else { return }
            try? await store.removeAllCredentialIdentities()
        }
    }
}
