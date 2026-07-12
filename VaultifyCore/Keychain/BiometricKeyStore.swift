import Foundation
import Security
import LocalAuthentication

/// Stores the Vault Key in a biometric-gated Keychain item. The key is held in
/// Secure-Enclave-protected storage and released only after a successful Face ID
/// / Touch ID evaluation. `.biometryCurrentSet` invalidates the item if the
/// enrolled biometrics change.
nonisolated enum BiometricKeyStore {
    static let account = "vault.biometricKey"

    /// Shared keychain access group so BOTH the app and the AutoFill extension can
    /// read the biometric-gated Vault Key. Must be team-prefixed (see `SharedConfig`).
    private static let accessGroup = SharedConfig.keychainAccessGroup

    enum Failure: Error { case accessControl, store(OSStatus), cancelled, unavailable }

    /// Whether a biometric-gated key is currently provisioned (no prompt shown).
    static var isEnrolled: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func store(vaultKey: [UInt8]) throws {
        delete()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error)
        else { throw Failure.accessControl }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: Data(vaultKey),
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.store(status) }
    }

    /// Retrieve the Vault Key, prompting for biometrics. Runs off the main actor.
    static func retrieve(reason: String) async throws -> [UInt8] {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: Array(data))
                } else if status == errSecUserCanceled || status == errSecAuthFailed {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: Failure.store(status))
                }
            }
        }
    }

    /// Remove the biometric key from BOTH the shared group and the legacy per-app group, so
    /// disabling biometrics (or re-storing) never leaves an orphaned key in either location —
    /// regardless of whether the one-time shared-group migration has run yet.
    @discardableResult
    static func delete() -> OSStatus {
        // Losing (or re-provisioning) the biometric key must also end any web
        // extension session minted from it — the session item has no biometric
        // ACL, so it would otherwise outlive a biometric invalidation.
        ExtensionSessionStore.clear()
        KeychainStore.delete(account: account, accessGroup: SharedConfig.legacyKeychainGroup)
        return KeychainStore.delete(account: account, accessGroup: accessGroup)
    }
}
