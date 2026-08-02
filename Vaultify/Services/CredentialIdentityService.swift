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
        // The QuickType index is host-scoped and persona-agnostic: the OS matches a
        // saved login by its website at fill time, with no notion of the active
        // identity. A strictly-anonymous identity's saved login is still an owned
        // item and will be offered on its own site — this is site-scoped, not
        // cross-identity correlation inside the app, so it doesn't widen suggestions
        // across identities. Suppressing a login from QuickType per identity would
        // need a per-item identity tag (not yet modeled) and is intentionally left
        // for later; document any change here.
        // One identity per website host, so a login with several websites is suggested
        // on every one of its domains.
        let ownedPasswordIdentities: [ASPasswordCredentialIdentity] = lastOwnedItems.flatMap { item -> [ASPasswordCredentialIdentity] in
            // Template capability first (the resolver keeps developer secrets
            // and unknown kinds out of QuickType), then the value-level
            // exclusions: extra-protected credentials can't fill (the value is
            // sealed ciphertext), so a QuickType suggestion would be a dead
            // end — and a sealed username would even surface ciphertext on
            // the bar.
            guard ItemCapabilityResolver.capabilities(for: item).loginAutoFill,
                  let passwordField = item.passwordField, !passwordField.value.isEmpty,
                  !passwordField.isExtraProtected,
                  let userField = item.usernameField, !userField.isEmpty,
                  !userField.isExtraProtected else { return [] }
            let user = userField.value
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
        // metadata-only and covers BOTH usable modes (user decision 260705 —
        // askEachTime taps route into the owner-approval ceremony in the
        // extension). Tier-0 items never reach the cache, so unapproved
        // devices register nothing.
        let sharedPasskeyIdentities: [ASPasskeyCredentialIdentity] = lastSharedEntries
            .flatMap { entry in
                (entry.passkeys ?? []).filter(Self.canCompleteAssertion).map { slot in
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

    /// Whether tapping this shared slot on the QuickType bar can actually
    /// finish a sign-in. Suggesting one that cannot is the same dead end an
    /// Extra-Protected login would be: the OS offers the credential, the user
    /// taps it, and the sheet can only show an error.
    ///
    /// Hand-over needs the delivered private key to sign locally — a slot
    /// whose key never arrived (a projection built before the blob landed, or
    /// a share downgraded since) has nothing to sign with. Ask-each-time
    /// needs nothing local by design: the owner signs it. A slot with no
    /// capability grants nothing at all.
    private static func canCompleteAssertion(_ slot: SharedPasskeyEntry) -> Bool {
        switch slot.mode {
        case .shared: return slot.privateKeyRaw != nil
        case .askEachTime: return true
        case .none: return false
        }
    }

    /// One-time-code identities for items that carry a TOTP secret + a matchable host.
    @available(iOS 18, *)
    private static func oneTimeCodeIdentities(_ items: [VaultItem]) -> [ASOneTimeCodeCredentialIdentity] {
        items.flatMap { item -> [ASOneTimeCodeCredentialIdentity] in
            // Capability-gated (a developer item's seed is not an authenticator
            // entry); totpField already excludes sealed seeds; the label must
            // not leak a sealed username's ciphertext either.
            guard ItemCapabilityResolver.isTOTPSource(item) else { return [] }
            let userField = item.usernameField
            let user = (userField?.isExtraProtected == true) ? nil : userField?.value
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
