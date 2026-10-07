import Foundation

/// Apple's attestation environment is independent of the backend host. Debug
/// can use production attestation while still talking to the relay's prod API.
nonisolated enum AppAttestEnvironment: String, Sendable {
    case development
    case production

    static var current: AppAttestEnvironment {
        #if DEBUG
        // Generated from the same APP_ATTEST_ENVIRONMENT setting as the
        // entitlement. An absent or unresolved value keeps local Debug runs in
        // development; iOS has no public API for reading our own entitlement.
        let configured = Bundle.main.object(forInfoDictionaryKey: "LooxAppAttestEnvironment") as? String
        return configured.flatMap(AppAttestEnvironment.init(rawValue:)) ?? .development
        #else
        // Apple always uses production for distributed apps, even if the source
        // entitlement named development. Release state must follow that rule.
        return .production
        #endif
    }
}

/// Keychain persistence for one App Attest key id and its server-registration
/// marker, scoped to both the backend and Apple's attestation environment.
///
/// Required invariants for state that can outlive a single app installation:
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
///    Host alone is insufficient: relay uses its production API in Debug too,
///    while Apple's development and production keys are separate. Both the
///    Keychain state and the install marker must include that environment. The
///    predecessor host-only state cannot prove which environment minted it, so
///    it is ignored and purged when a fresh key is minted.
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
    /// Shared by every store instance: relay creates a store per request, so an
    /// instance-local lock cannot protect a compare-and-reset across requests.
    private static let lock = NSLock()
    private let keyIdAccount: String
    private let registeredAccount: String
    /// Same scoping as the Keychain accounts, but in a store that dies with the
    /// install. Its absence is how a reinstall is detected.
    private let installMarkerKey: String
    private let defaults: UserDefaults
    /// Predecessor account names, including ambiguous host-only state, dropped
    /// when a fresh key is minted.
    private let legacyAccounts: [String]
    private let legacyInstallMarkerKey: String

    init(namespace: String, apiBase: URL, environment: AppAttestEnvironment = .current,
         legacyAccounts: [String] = [],
         defaults: UserDefaults = .standard) {
        let host = apiBase.host ?? "unknown-host"
        let scope = "\(host)#\(environment.rawValue)"
        keyIdAccount = "\(namespace)-app-attest-key-id@\(scope)"
        registeredAccount = "\(namespace)-app-attest-registered@\(scope)"
        installMarkerKey = "\(namespace)-app-attest-install@\(scope)"
        self.legacyAccounts = legacyAccounts + [
            "\(namespace)-app-attest-key-id@\(host)",
            "\(namespace)-app-attest-registered@\(host)",
        ]
        legacyInstallMarkerKey = "\(namespace)-app-attest-install@\(host)"
        self.defaults = defaults
    }

    /// False when the Keychain outlived the install that wrote it — the Enclave
    /// key is gone even though its id and marker are still here.
    private var installOwnsKeychainStateUnlocked: Bool { defaults.bool(forKey: installMarkerKey) }

    /// The persisted key id — the exact `X-Loox-App-Attest-Key-Id` header
    /// string. nil until a key has been minted for this backend.
    var storedKeyId: String? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return storedKeyIdUnlocked
    }

    private var storedKeyIdUnlocked: String? {
        guard installOwnsKeychainStateUnlocked else { return nil }
        guard let data = try? KeychainStore.get(account: keyIdAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Persist before anything else can fail — a key is unreachable without
    /// its id, and Apple mints it only once.
    func persist(keyId: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try KeychainStore.set(Data(keyId.utf8), account: keyIdAccount)
        defaults.set(true, forKey: installMarkerKey)
    }

    /// True only when the marker names EXACTLY this key id.
    func isRegistered(keyId: String) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard installOwnsKeychainStateUnlocked else { return false }
        guard let data = try? KeychainStore.get(account: registeredAccount),
              let marked = String(data: data, encoding: .utf8) else { return false }
        return marked == keyId
    }

    func markRegistered(keyId: String) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try KeychainStore.set(Data(keyId.utf8), account: registeredAccount)
    }

    func reset() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        resetUnlocked()
    }

    /// A late rejection of K1 must not erase K2 enrolled by another request.
    /// Compare the persisted id and clear all its state under one shared lock.
    @discardableResult
    func reset(ifKeyIdMatches rejectedKeyId: String) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard storedKeyIdUnlocked == rejectedKeyId else { return false }
        resetUnlocked()
        return true
    }

    private func resetUnlocked() {
        KeychainStore.delete(account: keyIdAccount)
        KeychainStore.delete(account: registeredAccount)
        defaults.removeObject(forKey: installMarkerKey)
    }

    func purgeLegacy() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        for account in legacyAccounts { KeychainStore.delete(account: account) }
        defaults.removeObject(forKey: legacyInstallMarkerKey)
    }
}
