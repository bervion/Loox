import Foundation
import SwiftData

/// Read-only vault access for the AutoFill extension: unlock with the master
/// password (Argon2id → unwrap the Vault Key from the shared key bundle) and
/// decrypt login items from the shared store. No `VaultSession` / app runtime.
enum VaultReader {
    enum Failure: Error { case noVault, wrongPassword }

    /// Whether a vault has been provisioned (key bundle present in App Group).
    nonisolated static var hasVault: Bool { VaultKeyBundle.exists }

    /// Derive the Vault Key from the master password. Heavy (Argon2id) — call
    /// off the main actor. Throws `wrongPassword` if the password doesn't unwrap.
    nonisolated static func deriveVaultKey(masterPassword: String) throws -> [UInt8] {
        guard let bundle = VaultKeyBundle.load() else { throw Failure.noVault }
        do {
            return try KeyHierarchy.unwrap(wrapped: bundle.wrappedByPassword,
                                           passphrase: masterPassword,
                                           salt: [UInt8](bundle.kdfSalt),
                                           params: bundle.kdf)
        } catch {
            throw Failure.wrongPassword
        }
    }

    /// All non-trashed login items (those exposing a password), decrypted.
    @MainActor static func logins(vaultKey: [UInt8]) -> [VaultItem] {
        let store = VaultStore()
        return store.allRecords()
            .filter { $0.trashedAt == nil && $0.deletedAt == nil && $0.archived == false }
            .compactMap { decrypt($0, key: vaultKey) }
            .filter { $0.passwordField != nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Best username/email to prefill a new login from the user's default identity.
    /// Identities have no password, so they never appear in `logins`; this reads them directly,
    /// filtering on the plaintext `ItemRecord.isDefaultIdentity` column (the sealed payload doesn't
    /// carry that flag). Returns the identity's email, else its name; nil if there's no default.
    @MainActor static func defaultIdentityUsername(vaultKey: [UInt8]) -> String? {
        let store = VaultStore()
        guard let record = store.allRecords().first(where: {
            $0.trashedAt == nil && $0.deletedAt == nil && $0.isDefaultIdentity
        }), let item = decrypt(record, key: vaultKey) else { return nil }
        if let email = item.fields.first(where: { $0.kind == .email })?.value, !email.isEmpty {
            return email
        }
        let name = item.fields.first(where: { $0.kind == .text })?.value
        return (name?.isEmpty == false) ? name : nil
    }

    /// Non-trashed items that carry a TOTP secret, for 2FA / one-time-code AutoFill.
    @MainActor static func totpItems(vaultKey: [UInt8]) -> [VaultItem] {
        let store = VaultStore()
        return store.allRecords()
            .filter { $0.trashedAt == nil && $0.deletedAt == nil && $0.archived == false }
            .compactMap { decrypt($0, key: vaultKey) }
            .filter { $0.totpField != nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private nonisolated static func decrypt(_ record: ItemRecord, key: [UInt8]) -> VaultItem? {
        guard let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(ItemSecret.self, from: plaintext)
        else { return nil }
        return VaultItem(id: record.id, category: secret.category, title: secret.title,
                         folderId: secret.folderId, fields: secret.fields,
                         favorite: record.favorite, tags: secret.tags,
                         iconAsset: secret.iconAsset,
                         lastUsedAt: record.lastUsedAt,
                         pinned: record.pinned, archived: record.archived, useCount: record.useCount,
                         createdAt: record.createdAt,
                         updatedAt: record.updatedAt, trashedAt: record.trashedAt)
    }
}

extension VaultItem {
    /// Every non-empty website field value. An item may carry several websites so a
    /// single login autofills across all of a service's domains.
    var urlValues: [String] {
        fields.filter { $0.kind == .url && !$0.isEmpty }.map(\.value)
    }

    /// All matchable hosts derived from every website field (deduped, lowercased),
    /// preserving field order. Drives multi-site AutoFill + passkey attachment.
    var autofillHosts: [String] {
        var seen = Set<String>()
        var hosts: [String] = []
        for raw in urlValues {
            let withScheme = raw.contains("://") ? raw : "https://\(raw)"
            guard let host = URL(string: withScheme)?.host?.lowercased() else { continue }
            if seen.insert(host).inserted { hosts.append(host) }
        }
        return hosts
    }

    /// Best single host (first website). Kept for callers that need one host.
    var autofillHost: String? { autofillHosts.first }

    /// Whether this item is relevant to any of the requested service domains —
    /// true if ANY of the item's websites matches.
    func matchesAutoFill(serviceIdentifiers: [String]) -> Bool {
        guard !serviceIdentifiers.isEmpty else { return true }
        let hosts = autofillHosts
        guard !hosts.isEmpty else { return false }
        return serviceIdentifiers.contains { id in
            let other = id.lowercased()
            return hosts.contains { host in
                host == other || host.hasSuffix(".\(other)") || other.hasSuffix(".\(host)") || other.contains(host)
            }
        }
    }

    /// Whether ANY of this login's hosts belongs to a WebAuthn relying-party id.
    /// Unlike the looser password AutoFill matcher above, passkey attachment is
    /// display-only and conservative: exact host or true subdomain only.
    func matchesRelyingParty(_ relyingParty: String) -> Bool {
        let rp = relyingParty.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rp.isEmpty else { return false }
        return autofillHosts.contains { host in host == rp || host.hasSuffix(".\(rp)") }
    }
}
