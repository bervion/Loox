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
///
/// `replaceCredentialIdentities` replaces the ENTIRE store regardless of type, so
/// owned items and recipient-side shared items (published on separate refresh
/// cadences — repository reload vs. `SharedItemsProjection.refresh`) must be
/// combined into the SAME call or one publisher would silently erase the other's
/// entries. The two "last known" caches below exist only to make that merge possible.
@MainActor
enum CredentialIdentityService {
    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment.keys.contains { $0.hasPrefix("XCTest") }
            || NSClassFromString("XCTestCase") != nil
            || NSClassFromString("XCTest.XCTestCase") != nil
    }

    private static var lastOwnedItems: [VaultItem] = []
    private static var lastPasskeys: [PasskeyInfo] = []
    private static var lastSharedEntries: [SharedCredentialEntry] = []

    /// Owned-vault side of the publish (repository reload / mutation). Also publishes
    /// passkey identities and one-time-code (2FA) identities on iOS 18+.
    static func refresh(items: [VaultItem], passkeys: [PasskeyInfo]) {
        lastOwnedItems = items
        lastPasskeys = passkeys
        publish()
    }

    /// Shared-projection side of the publish (`SharedItemsProjection.refresh`). Entries
    /// need a host AND a username to be worth a QuickType suggestion — a share with
    /// neither (e.g. TOTP-only) has nothing to suggest a service identifier for.
    static func refreshShared(_ entries: [SharedCredentialEntry]) {
        lastSharedEntries = entries
        publish()
    }

    private static func publish() {
        guard !isRunningUnitTests else { return }
        let token = CredentialIdentityRefreshGate.next()
        // One identity per website host, so a login with several websites is suggested
        // on every one of its domains.
        let ownedPasswordIdentities: [ASPasswordCredentialIdentity] = lastOwnedItems.flatMap { item -> [ASPasswordCredentialIdentity] in
            guard item.passwordField?.value.isEmpty == false,
                  let user = item.usernameField?.value, !user.isEmpty else { return [] }
            return item.autofillHosts.map { host in
                ASPasswordCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                    user: user,
                    recordIdentifier: item.id)
            }
        }
        let sharedPasswordIdentities: [ASPasswordCredentialIdentity] = lastSharedEntries.compactMap { entry in
            guard let host = entry.websiteHost, !host.isEmpty,
                  let user = entry.username, !user.isEmpty else { return nil }
            return ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                user: user,
                // `shared::` prefix — the extension branches on it, never confusing this
                // with an owned record id (VaultRepository also guards on the prefix).
                recordIdentifier: entry.itemID)
        }
        let passkeyIdentities = lastPasskeys.map { $0.credentialIdentity() }
        // Shared passkey slots (capability v2): identity registration is
        // metadata-only, allowed for BOTH modes (user decision 260705 —
        // askEachTime taps route into the approval ceremony). Tier-0 items
        // never reach the cache, so unapproved devices register nothing.
        let sharedPasskeyIdentities: [ASPasskeyCredentialIdentity] = lastSharedEntries
            .flatMap { entry in
                (entry.passkeys ?? []).map { slot in
                    ASPasskeyCredentialIdentity(
                        relyingPartyIdentifier: slot.relyingParty,
                        userName: slot.userName,
                        credentialID: slot.credentialID,
                        userHandle: slot.userHandle,
                        recordIdentifier: entry.itemID)
                }
            }
        CredentialIdentityRefreshGate.enqueue {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled,
                  CredentialIdentityRefreshGate.isCurrent(token) else { return }
            // Replace clears all types, so re-add OTP identities afterwards (ordered).
            let passwordEntries = (ownedPasswordIdentities + sharedPasswordIdentities)
                .map { $0 as any ASCredentialIdentity }
            try? await store.replaceCredentialIdentities(passwordEntries)
            guard CredentialIdentityRefreshGate.isCurrent(token) else { return }
            var secondary = (passkeyIdentities + sharedPasskeyIdentities)
                .map { $0 as any ASCredentialIdentity }
            if #available(iOS 18, *) {
                let otp = oneTimeCodeIdentities(lastOwnedItems)
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
        items.flatMap { item -> [ASOneTimeCodeCredentialIdentity] in
            guard item.totpField != nil else { return [] }
            let user = item.usernameField?.value
            return item.autofillHosts.map { host in
                let label = (user?.isEmpty == false) ? user! : (item.title.isEmpty ? host : item.title)
                return ASOneTimeCodeCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                    label: label,
                    recordIdentifier: item.id)
            }
        }
    }

    /// Drop all published identities (called when the vault locks). Same security
    /// posture for shared as for owned: while the app is locked, QuickType shows no
    /// hint — the extension's own unlock + `SharedCredentialsCache` still work.
    static func clear() {
        lastOwnedItems = []
        lastPasskeys = []
        lastSharedEntries = []
        guard !isRunningUnitTests else { return }
        let token = CredentialIdentityRefreshGate.next()
        CredentialIdentityRefreshGate.enqueue {
            let store = ASCredentialIdentityStore.shared
            guard await store.state().isEnabled,
                  CredentialIdentityRefreshGate.isCurrent(token) else { return }
            try? await store.removeAllCredentialIdentities()
        }
    }
}
