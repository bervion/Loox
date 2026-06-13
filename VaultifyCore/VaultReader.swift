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
            .filter { $0.trashedAt == nil && $0.deletedAt == nil }
            .compactMap { decrypt($0, key: vaultKey) }
            .filter { $0.passwordField != nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private nonisolated static func decrypt(_ record: ItemRecord, key: [UInt8]) -> VaultItem? {
        guard let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(ItemSecret.self, from: plaintext)
        else { return nil }
        return VaultItem(id: record.id, category: secret.category, title: secret.title,
                         folderId: secret.folderId, fields: secret.fields,
                         favorite: record.favorite, createdAt: record.createdAt,
                         updatedAt: record.updatedAt, trashedAt: record.trashedAt)
    }
}

extension VaultItem {
    /// Best host string for matching against an AutoFill service identifier.
    var autofillHost: String? {
        guard let raw = urlField?.value, !raw.isEmpty else { return nil }
        let withScheme = raw.contains("://") ? raw : "https://\(raw)"
        return URL(string: withScheme)?.host?.lowercased()
    }

    /// Whether this item is relevant to any of the requested service domains.
    func matchesAutoFill(serviceIdentifiers: [String]) -> Bool {
        guard !serviceIdentifiers.isEmpty else { return true }
        guard let host = autofillHost else { return false }
        return serviceIdentifiers.contains { id in
            let other = id.lowercased()
            return host == other || host.hasSuffix(".\(other)") || other.hasSuffix(".\(host)") || other.contains(host)
        }
    }
}
