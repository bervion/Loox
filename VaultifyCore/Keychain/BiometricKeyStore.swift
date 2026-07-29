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

    /// Why a biometric-gated read or write failed. The cases the failure POLICY
    /// cares about are kept apart on purpose: a dismissed prompt must never read
    /// as a rejected face (see `BiometricAuth.classify`).
    enum Failure: Error {
        case accessControl
        case store(OSStatus)
        /// The user dismissed the prompt. Not an authentication failure.
        case cancelled
        /// Biometry ran and rejected, or is locked out after repeated failures.
        case denied
        /// The item is gone: never provisioned, or `.biometryCurrentSet`
        /// invalidated it because the enrolled biometrics changed.
        case invalidated
        case unavailable
    }

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
    ///
    /// The `SecItemCopyMatching` below blocks its thread until biometry answers,
    /// and after a device wake the daemon can take the prompt and never come
    /// back — which used to strand the continuation forever, freezing whatever
    /// awaited it. Cancelling the surrounding task now invalidates the very
    /// `LAContext` the query is using (the supported way to unblock a pending
    /// biometric keychain read) AND resumes, so this call always finishes.
    static func retrieve(reason: String) async throws -> [UInt8] {
        let read = PendingRead(reason: reason)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: read.context,
        ]
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                read.attach(continuation)
                DispatchQueue.global(qos: .userInitiated).async {
                    var result: AnyObject?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    switch status {
                    case errSecSuccess:
                        if let data = result as? Data {
                            read.finish(.success(Array(data)))
                        } else {
                            read.finish(.failure(Failure.store(status)))
                        }
                    case errSecUserCanceled:
                        read.finish(.failure(Failure.cancelled))
                    case errSecAuthFailed:
                        read.finish(.failure(Failure.denied))
                    case errSecItemNotFound:
                        read.finish(.failure(Failure.invalidated))
                    default:
                        read.finish(.failure(Failure.store(status)))
                    }
                }
            }
        } onCancel: {
            read.cancel()
        }
    }

    /// Owns the one biometric read in flight: its `LAContext` and its single
    /// resume. The keychain thread and the cancellation handler race for that
    /// resume, and resuming a continuation twice traps, so exactly one of them
    /// wins and the loser's result is dropped — a late success never reaches a
    /// caller, and its buffer is released with the dropped `Result`.
    private nonisolated final class PendingRead: @unchecked Sendable {
        let context: LAContext
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[UInt8], Error>?
        private var finished = false

        init(reason: String) {
            context = LAContext()
            context.localizedReason = reason
        }

        /// Hand over the continuation. A cancellation that beat the query to it
        /// is resumed here instead of being lost.
        func attach(_ continuation: CheckedContinuation<[UInt8], Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: Failure.cancelled)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func finish(_ result: Result<[UInt8], Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }

        /// Unblock the keychain call, then resume — invalidating the context is
        /// what makes a pending biometric read return at all.
        func cancel() {
            context.invalidate()
            finish(.failure(Failure.cancelled))
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

extension BiometricKeyStore.Failure: BiometricOutcomeReporting {
    nonisolated var biometricOutcome: BiometricAuth.Outcome {
        switch self {
        case .cancelled: return .cancelled
        case .denied: return .failed
        // Nothing was attempted: the item is missing or the device cannot build
        // the access control at all, so neither is evidence about a face.
        case .invalidated, .unavailable, .accessControl: return .unavailable
        // An unattributable Keychain status is read as a failure — the safe
        // default for a security policy, and on the lock screen it advances the
        // attempt count so the master-password fallback appears instead of a
        // badge that keeps failing.
        case .store: return .failed
        }
    }
}
