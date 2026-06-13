import Foundation
import Security

/// Thin wrapper over the Keychain (generic-password class). All items are
/// `WhenUnlockedThisDeviceOnly` — never synced to iCloud Keychain or backups.
nonisolated enum KeychainStore {
    static let service = "com.bervion.vaultify"

    enum Failure: Error { case unexpectedStatus(OSStatus) }

    static func set(_ data: Data, account: String) throws {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
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

    static func get(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.unexpectedStatus(status) }
        return result as? Data
    }

    @discardableResult
    static func delete(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
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
