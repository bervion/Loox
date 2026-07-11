import Foundation
import CryptoKit

/// Device-local cache of known-leak lookups. DELIBERATELY not synced: entries
/// are a signal about the user's passwords, so they stay on this device.
///
/// Keys are HMAC-SHA256(device secret, password) — one-way, and a password
/// change naturally misses the old entry. The file itself is AES-GCM sealed
/// under the second half of the same Keychain secret. Values carry only a
/// breach count and a timestamp.
actor AuditLocalCache {
    struct Entry: Codable {
        let count: Int
        let checkedAt: Date
    }

    /// Entries older than this are stale and re-checked on the next full audit.
    static let ttl: TimeInterval = 30 * 24 * 3600

    private let hmacKey: SymmetricKey
    private let aesKey: [UInt8]
    private let fileURL: URL
    private var entries: [String: Entry]?   // loaded lazily

    private static let keychainAccount = "audit-pwned-cache-secret"
    private static var defaultFileURL: URL {
        SharedConfig.containerURL.appending(path: "audit-pwned-cache.bin")
    }

    /// Production cache: 64-byte secret created once in the Keychain
    /// (HMAC key ‖ file key), file in the App Group container.
    init() throws {
        let secret = try Self.loadOrCreateSecret()
        self.init(secret: secret, fileURL: Self.defaultFileURL)
    }

    /// Erase-Vault hook: the cache holds signals about the erased vault's
    /// passwords and must die with it (file + Keychain secret).
    nonisolated static func clearPersisted() {
        try? FileManager.default.removeItem(at: defaultFileURL)
        _ = KeychainStore.delete(account: keychainAccount)
    }

    /// Injectable variant for tests.
    init(secret: [UInt8], fileURL: URL) {
        precondition(secret.count == 64)
        hmacKey = SymmetricKey(data: Array(secret[0..<32]))
        aesKey = Array(secret[32..<64])
        self.fileURL = fileURL
    }

    private static func loadOrCreateSecret() throws -> [UInt8] {
        if let data = try KeychainStore.get(account: keychainAccount), data.count == 64 {
            return Array(data)
        }
        let secret = CryptoRandom.bytes(64)
        try KeychainStore.set(Data(secret), account: keychainAccount)
        return secret
    }

    // MARK: - API

    /// Fresh cached count for a password, or nil (unknown or stale).
    func count(for password: String, now: Date = .now) -> Int? {
        guard let entry = loadedEntries()[key(for: password)],
              now.timeIntervalSince(entry.checkedAt) < Self.ttl else { return nil }
        return entry.count
    }

    /// Record completed lookups (only ever whole-prefix results — a cancelled
    /// run stores nothing partial for the affected prefix).
    func store(counts: [String: Int], now: Date = .now) {
        var current = loadedEntries()
        for (password, count) in counts {
            current[key(for: password)] = Entry(count: count, checkedAt: now)
        }
        entries = current
        persist(current)
    }

    func wipe() {
        entries = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Internals

    private func key(for password: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(password.utf8), using: hmacKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private func loadedEntries() -> [String: Entry] {
        if let entries { return entries }
        guard let sealed = try? Data(contentsOf: fileURL),
              let plain = try? AESGCM.open(sealed, key: aesKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: plain) else {
            entries = [:]
            return [:]
        }
        entries = decoded
        return decoded
    }

    private func persist(_ entries: [String: Entry]) {
        guard let plain = try? JSONEncoder().encode(entries),
              let sealed = try? AESGCM.seal(plain, key: aesKey) else { return }
        try? sealed.write(to: fileURL, options: .atomic)
    }
}
