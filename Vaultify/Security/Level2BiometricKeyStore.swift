import Foundation
import Security
import LocalAuthentication

/// Stores the Level-2 Secret Key (L2SK) in a biometric-gated Keychain item so
/// Extra Protection can be opened with Face ID instead of retyping the Extra
/// Password. `.biometryCurrentSet` invalidates the item the moment the enrolled
/// biometrics change, so a newly enrolled face can never inherit the unlock.
///
/// Deliberately app-only, unlike `BiometricKeyStore`:
/// - no shared access group — neither the AutoFill nor the Safari extension can
///   open a sealed field, so neither has any reason to reach this key;
/// - it never touches `ExtensionSessionStore`. That coupling belongs to the
///   Vault Key (it seeds the web-extension session); tying it here would kill a
///   live browser session every time the Extra Password changed.
///
/// The item exists only while `settings.biometricUnlockEnabled` is on — the
/// Extra Password stays the source of truth and always works as the fallback.
nonisolated enum Level2BiometricKeyStore {
    static let account = "vault.level2Key"

    /// The APP-IDENTIFIER group (`WDNL2F75V7.com.bervion.vaultify`), which every
    /// query below names explicitly. This must not be left to default: the
    /// `keychain-access-groups` entitlement lists only `…vaultify.shared`, so an
    /// omitted `kSecAttrAccessGroup` would land the L2SK in the group both
    /// extensions can read. The app-identifier group is implicitly available to
    /// the app and appears in no extension's entitlements, which is exactly the
    /// isolation this store needs. (It is the same group the Vault Key was
    /// migrated OUT of, precisely because the extension could not reach it.)
    private static let accessGroup = SharedConfig.legacyKeychainGroup

    enum Failure: Error {
        /// The user dismissed the prompt. Not an authentication failure.
        case cancelled
        /// Biometry ran and rejected, or is locked out after repeated failures.
        case denied
        /// No item is provisioned, or the enrolled biometrics changed under
        /// `.biometryCurrentSet` and invalidated it.
        case notEnrolled
        case accessControl
        case store(OSStatus)
    }

    /// Whether a biometric-gated L2SK is provisioned. Never prompts.
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
        // `errSecInteractionNotAllowed` means the item is there but wants a
        // prompt we suppressed — that still counts as provisioned.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Provision (or re-provision) the item. Leads with `delete()` so a re-enrol
    /// never orphans the previous key behind a stale access-control object.
    static func store(level2Key: [UInt8]) throws {
        delete()
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil)
        else { throw Failure.accessControl }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: Data(level2Key),
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.store(status) }
    }

    /// Retrieve the L2SK, prompting for biometrics. Runs off the main actor.
    /// Distinguishes cancel from rejection so the caller can decide whether the
    /// app should lock (see `VaultSession.noteBiometricOutcome`).
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
                switch status {
                case errSecSuccess:
                    if let data = result as? Data {
                        continuation.resume(returning: Array(data))
                    } else {
                        continuation.resume(throwing: Failure.store(status))
                    }
                case errSecUserCanceled:
                    continuation.resume(throwing: Failure.cancelled)
                case errSecAuthFailed:
                    continuation.resume(throwing: Failure.denied)
                case errSecItemNotFound:
                    continuation.resume(throwing: Failure.notEnrolled)
                default:
                    continuation.resume(throwing: Failure.store(status))
                }
            }
        }
    }

    /// Removes the key from the app group AND sweeps the shared group. The sweep
    /// covers devices that ran a build where the group was left to default and
    /// the item landed where the extensions could see it — without it, "turn off
    /// Extra Protection" would leave that copy behind forever.
    @discardableResult
    static func delete() -> OSStatus {
        func remove(group: String) -> OSStatus {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrService as String: KeychainStore.service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group,
            ] as CFDictionary)
        }
        remove(group: SharedConfig.keychainAccessGroup)
        return remove(group: accessGroup)
    }
}
