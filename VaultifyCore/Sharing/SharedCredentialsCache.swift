import Foundation

/// One recipient-side shared LOGIN credential, flattened for AutoFill. Built by
/// `SharedItemsProjection.refresh` from the live grant + display envelope + shared
/// field values -- this is a DERIVED cache, never the source of truth (the projection
/// and the CloudKit shared zone are).
nonisolated struct SharedCredentialEntry: Codable, Sendable, Equatable {
    /// The `shared::` projection id (matches `SharedOrigin.itemID`).
    var itemID: String
    var title: String
    var websiteHost: String?
    var username: String?
    var password: String?
    /// Zone address needed to reopen the grant/request machinery (mirrors `SharedOrigin`).
    var zoneName: String
    var ownerName: String
    var grantId: String
    /// The grant's `askEachTime` TOTP field id, if any -- drives the extension's
    /// "Request code" affordance. Nil when this share has no TOTP capability.
    var askEachTimeTOTPFieldId: String?

    /// Same host-matching heuristic as `VaultItem.matchesAutoFill` (subdomain/suffix
    /// tolerant), applied to the single cached host instead of a multi-host list --
    /// shared credentials only ever carry the one website the owner published.
    func matchesAutoFill(serviceIdentifiers: [String]) -> Bool {
        guard !serviceIdentifiers.isEmpty else { return true }
        guard let host = websiteHost?.lowercased(), !host.isEmpty else { return false }
        return serviceIdentifiers.contains { identifier in
            let other = identifier.lowercased()
            return host == other || host.hasSuffix(".\(other)")
                || other.hasSuffix(".\(host)") || other.contains(host)
        }
    }
}

/// Persists the recipient's shared login credentials in the App Group container so the
/// AutoFill extension can offer them even while the main app is locked/closed.
///
/// SECURITY NOTE (deliberate, needs its own review before wider rollout): unlike
/// `VaultRepository`'s in-memory cache, this blob is NOT wiped when the app locks --
/// `SharedItemsProjection.wipe()` only clears memory. AutoFill has no path to re-derive
/// these values (it never talks to CloudKit), so the cache must outlive a lock the same
/// way `VaultKeyBundle` and the vault's own `ItemRecord`s do: as ciphertext at rest,
/// readable only by whoever holds the Vault Key. It IS cleared by `AppEnvironment
/// .eraseEverything()`. Revocation lag: a revoke on the owner's side only disappears
/// from this cache the next time the app (not the extension) runs a projection refresh.
nonisolated enum SharedCredentialsCache {
    private static let version: UInt8 = 1

    /// Seal and write the full entry set (a fresh save always replaces the previous one --
    /// there is no partial update, mirroring how the projection rebuilds from scratch).
    static func save(entries: [SharedCredentialEntry], vaultKey: [UInt8]) throws {
        let plaintext = try JSONEncoder().encode(entries)
        var envelope = Data([version])
        envelope.append(try AESGCM.seal(plaintext, key: vaultKey))
        try envelope.write(to: SharedConfig.sharedCredentialsCacheURL,
                          options: [.atomic, .completeFileProtection])
    }

    /// Best-effort load -- any corruption, wrong key, or missing file yields an empty
    /// list rather than throwing (AutoFill must degrade to "no shared items", never crash).
    static func load(vaultKey: [UInt8]) -> [SharedCredentialEntry] {
        guard let envelope = try? Data(contentsOf: SharedConfig.sharedCredentialsCacheURL),
              envelope.first == version,
              let plaintext = try? AESGCM.open(envelope.dropFirst(), key: vaultKey),
              let entries = try? JSONDecoder().decode([SharedCredentialEntry].self, from: plaintext)
        else { return [] }
        return entries
    }

    /// Vault erase -- the only place this survives a lock, so it must be wiped explicitly.
    static func clear() {
        try? FileManager.default.removeItem(at: SharedConfig.sharedCredentialsCacheURL)
    }
}
