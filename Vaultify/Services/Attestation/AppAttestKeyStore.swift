import Foundation

/// Keychain persistence for one App Attest key id and its server-registration
/// marker, scoped to the backend that actually attested the key.
///
/// Two invariants the earlier flat account names could not hold, each of which
/// bricked attestation with no path back:
///
/// 1. **Scoped by backend host.** The server's key store is keyed by deploy
///    environment, so a key registered against staging is `key_unknown` to
///    production. Keychain items survive app deletion, but the Secure Enclave
///    App Attest key does not — so a DEBUG run (staging) followed by deleting
///    the app and installing a Release build (production) left the device
///    presenting production a key only staging had ever seen. Scoping the
///    accounts by host means the two environments can never see each other's
///    state, and a build switch starts clean instead of poisoned.
///
/// 2. **The marker IS the key id.** A bare "registered" flag outlives the key
///    it vouched for: after a reinstall the flag said "registered" while the
///    Enclave key behind it was gone, so registration was skipped and every
///    assertion was signed by a key the server had never seen. Storing the id
///    and requiring equality means a marker can only ever authorize the exact
///    key it was written for.
///
/// 3. **A reinstall invalidates everything here.** Both items above live in the
///    Keychain, which survives app deletion — but the Enclave key they describe
///    does not. After a reinstall the id and the marker still agree with each
///    other, so registration was skipped and every assertion was signed with a
///    key that no longer existed. Apple answers that with `invalidInput`, not
///    `invalidKey`, so the one recovery path never fired and reinstalling — the
///    obvious thing a stuck user tries — could not help. The install marker
///    below lives in `UserDefaults`, which IS cleared on deletion, so Keychain
///    state is trusted only while the install that created it is still there.
nonisolated struct AppAttestKeyStore {
    private let keyIdAccount: String
    private let registeredAccount: String
    /// Same scoping as the Keychain accounts, but in a store that dies with the
    /// install. Its absence is how a reinstall is detected.
    private let installMarkerKey: String
    private let defaults: UserDefaults
    /// Pre-scoping account names, dropped when a fresh key is minted so the
    /// dead state cannot be mistaken for live state by a later reader.
    private let legacyAccounts: [String]

    init(namespace: String, apiBase: URL, legacyAccounts: [String] = [],
         defaults: UserDefaults = .standard) {
        let scope = apiBase.host ?? "unknown-host"
        keyIdAccount = "\(namespace)-app-attest-key-id@\(scope)"
        registeredAccount = "\(namespace)-app-attest-registered@\(scope)"
        installMarkerKey = "\(namespace)-app-attest-install@\(scope)"
        self.legacyAccounts = legacyAccounts
        self.defaults = defaults
    }

    /// False when the Keychain outlived the install that wrote it — the Enclave
    /// key is gone even though its id and marker are still here.
    private var installOwnsKeychainState: Bool { defaults.bool(forKey: installMarkerKey) }

    /// The persisted key id — the exact `X-Loox-App-Attest-Key-Id` header
    /// string. nil until a key has been minted for this backend.
    var storedKeyId: String? {
        guard installOwnsKeychainState else { return nil }
        guard let data = try? KeychainStore.get(account: keyIdAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Persist before anything else can fail — a key is unreachable without
    /// its id, and Apple mints it only once.
    func persist(keyId: String) throws {
        try KeychainStore.set(Data(keyId.utf8), account: keyIdAccount)
        defaults.set(true, forKey: installMarkerKey)
    }

    /// True only when the marker names EXACTLY this key id.
    func isRegistered(keyId: String) -> Bool {
        guard installOwnsKeychainState else { return false }
        guard let data = try? KeychainStore.get(account: registeredAccount),
              let marked = String(data: data, encoding: .utf8) else { return false }
        return marked == keyId
    }

    func markRegistered(keyId: String) throws {
        try KeychainStore.set(Data(keyId.utf8), account: registeredAccount)
    }

    func reset() {
        KeychainStore.delete(account: keyIdAccount)
        KeychainStore.delete(account: registeredAccount)
        defaults.removeObject(forKey: installMarkerKey)
    }

    func purgeLegacy() {
        for account in legacyAccounts { KeychainStore.delete(account: account) }
    }
}
