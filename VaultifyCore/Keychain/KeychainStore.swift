import Foundation
import Security

/// Thin wrapper over the Keychain (generic-password class). All items are
/// `WhenUnlockedThisDeviceOnly` — never synced to iCloud Keychain or backups.
///
/// Every query sets `kSecUseDataProtectionKeychain = true`: on iOS this is the
/// existing behavior, but on macOS it opts into the iOS-style data-protection
/// keychain (instead of the legacy file keychain), so `kSecAttrAccessGroup`
/// sharing and `…ThisDeviceOnly` accessibility behave the same across platforms.
nonisolated enum KeychainStore {
    static let service = "com.bervion.vaultify"

    enum Failure: Error { case unexpectedStatus(OSStatus) }

    static func set(_ data: Data, account: String, accessGroup: String? = nil) throws {
        var match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { match[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemCopyMatching(match as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let update = [kSecValueData as String: data]
            let s = SecItemUpdate(match as CFDictionary, update as CFDictionary)
            guard s == errSecSuccess else { throw Failure.unexpectedStatus(s) }
        case errSecItemNotFound:
            var add = match
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let s = SecItemAdd(add as CFDictionary, nil)
            guard s == errSecSuccess else { throw Failure.unexpectedStatus(s) }
        default:
            throw Failure.unexpectedStatus(status)
        }
    }

    /// Update-only write: replaces an existing item's data and returns `false`
    /// when the item does not exist — it NEVER adds one. For values with
    /// revocation semantics (e.g. the extension unlock session), the
    /// add-or-update `set` would silently re-create an item that a concurrent
    /// delete just revoked; this call makes that race lose safely.
    static func update(_ data: Data, account: String, accessGroup: String? = nil) throws -> Bool {
        var match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { match[kSecAttrAccessGroup as String] = accessGroup }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
        return true
    }

    static func get(account: String, accessGroup: String? = nil) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
        return result as? Data
    }

    @discardableResult
    static func delete(account: String, accessGroup: String? = nil) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return SecItemDelete(query as CFDictionary)
    }

    static func setCodable(_ value: some Encodable, account: String) throws {
        try set(JSONEncoder().encode(value), account: account)
    }

    static func getCodable<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        guard let data = try get(account: account) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}
