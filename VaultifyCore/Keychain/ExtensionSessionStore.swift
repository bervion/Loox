import Foundation
import Security

/// Short-lived "unlocked" session shared between the app and the Safari web
/// extension so a popup open within the window needs no fresh Face ID.
///
/// The item holds the Vault Key bytes plus a sliding-expiry header in the
/// shared keychain access group, `WhenUnlockedThisDeviceOnly`, data-protection
/// keychain, and deliberately NO biometric ACL — that absence IS the session:
/// while it exists (device unlocked, window not elapsed) our own team-signed
/// binaries can read the key without user presence. Bounds on that trade-off:
///   - lifetime = the app's auto-lock window, hard-capped at `maxTTL`, sliding
///     on each use (refreshed like the app's `lastActivity` model);
///   - unreadable while the device is locked (accessibility class);
///   - expired or malformed payloads self-delete on read;
///   - cleared when the app locks, on vault erase / biometric invalidation
///     (`BiometricKeyStore.delete`), and never written when auto-lock is
///     "immediate".
/// The key never crosses the native→JS bridge; this store is native-only.
nonisolated enum ExtensionSessionStore {
    static let account = "vault.extensionSession"

    /// Hard ceiling on any session lifetime, regardless of the app's auto-lock
    /// window (a 1-hour auto-lock must not leave a 1-hour no-biometric key).
    static let maxTTL: TimeInterval = 15 * 60
    /// Session window used before the app has mirrored its auto-lock setting.
    static let defaultTTL: TimeInterval = 300

    // MARK: - Storage seam

    /// Live storage = one generic-password item in the shared access group;
    /// tests inject an in-memory backend to exercise TTL logic deterministically.
    struct Backend: Sendable {
        var read: @Sendable () -> Data?
        var write: @Sendable (Data) -> Bool
        var delete: @Sendable () -> Void
    }

    static let keychainBackend = Backend(
        read: {
            (try? KeychainStore.get(account: account,
                                    accessGroup: SharedConfig.keychainAccessGroup)) ?? nil
        },
        write: { data in
            (try? KeychainStore.set(data, account: account,
                                    accessGroup: SharedConfig.keychainAccessGroup)) != nil
        },
        delete: {
            KeychainStore.delete(account: account,
                                 accessGroup: SharedConfig.keychainAccessGroup)
        })

    // MARK: - API

    /// Store the Vault Key for `ttl` seconds (clamped to `maxTTL`). A TTL of
    /// zero or less (auto-lock "immediate") clears any existing session instead —
    /// strict users keep today's per-operation Face ID. Best-effort: a write
    /// failure just means the next operation re-prompts.
    static func save(vaultKey: [UInt8], ttl: TimeInterval,
                     now: Date = .now, backend: Backend = keychainBackend) {
        guard ttl > 0 else {
            backend.delete()
            return
        }
        var blob = encode(ttl: min(ttl, maxTTL), lastActivity: now, key: vaultKey)
        _ = backend.write(blob)
        blob.resetBytes(in: 0..<blob.count)
    }

    /// The session key, or nil when absent/expired (expired and malformed items
    /// self-delete). A hit slides the window by rewriting `lastActivity = now`.
    static func retrieve(now: Date = .now, backend: Backend = keychainBackend) -> [UInt8]? {
        guard var data = backend.read() else { return nil }
        defer { data.resetBytes(in: 0..<data.count) }
        guard let payload = decode(data) else {
            backend.delete()
            return nil
        }
        let window = min(payload.ttl, maxTTL)
        guard now.timeIntervalSince(payload.lastActivity) < window else {
            backend.delete()
            return nil
        }
        var refreshed = encode(ttl: window, lastActivity: now, key: payload.key)
        _ = backend.write(refreshed)
        refreshed.resetBytes(in: 0..<refreshed.count)
        return payload.key
    }

    /// Drop the session immediately (app lock, vault erase, biometric changes).
    static func clear(backend: Backend = keychainBackend) {
        backend.delete()
    }

    /// The session window mirrored from the app's auto-lock setting
    /// (`SharedConfig.autoLockSecondsKey`): 0 = immediate = no session ever,
    /// missing = `defaultTTL`, anything else clamped to `maxTTL`.
    static func configuredTTL(defaults: UserDefaults = SharedConfig.sharedDefaults) -> TimeInterval {
        guard let raw = defaults.object(forKey: SharedConfig.autoLockSecondsKey) as? Int else {
            return defaultTTL
        }
        guard raw > 0 else { return 0 }
        return min(TimeInterval(raw), maxTTL)
    }

    // MARK: - Payload codec (version || ttl || lastActivity || key)

    private static let payloadVersion: UInt8 = 1
    private static let headerLength = 17  // 1 version + 8 ttl + 8 lastActivity

    private static func encode(ttl: TimeInterval, lastActivity: Date, key: [UInt8]) -> Data {
        var data = Data(capacity: headerLength + key.count)
        data.append(payloadVersion)
        appendUInt64(UInt64(max(0, ttl)), to: &data)
        appendUInt64(UInt64(max(0, lastActivity.timeIntervalSince1970)), to: &data)
        data.append(contentsOf: key)
        return data
    }

    private static func decode(_ data: Data) -> (ttl: TimeInterval, lastActivity: Date, key: [UInt8])? {
        guard data.count > headerLength, data[data.startIndex] == payloadVersion else { return nil }
        let ttl = TimeInterval(readUInt64(data, offset: 1))
        let lastActivity = Date(timeIntervalSince1970: TimeInterval(readUInt64(data, offset: 9)))
        let key = Array(data.dropFirst(headerLength))
        return (ttl, lastActivity, key)
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt64(_ data: Data, offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            let byte = data[data.startIndex + offset + index]
            value |= UInt64(byte) << (8 * index)
        }
        return value
    }
}
