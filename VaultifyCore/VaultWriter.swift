import Foundation
import SwiftData

/// Minimal write path for the AutoFill extension: seal a brand-new login and insert it into the
/// shared SwiftData store. Symmetric to `VaultReader`. Recoverable (throws, never `fatalError`s) so
/// a store failure aborts the save gracefully instead of crashing the credential UI mid-registration.
///
/// Independent of the app's `VaultRepository` (which is app-target only and pulls in
/// `VaultSession` / notifications / the credential-identity index). The extension stays lean:
/// no favicon fetch, no rotation scheduling — the app enriches the item on its next open.
@MainActor
enum VaultWriter {
    enum Failure: Error { case emptyPassword }

    /// Create + persist a new login. Returns the new item id.
    /// `updatedAt = now` and `dirty = true` (the `ItemRecord` default) so the app pushes it to
    /// CloudKit on its next sync. Fields use the correct `FieldKind`s so the item survives the
    /// reader's `passwordField != nil` filter and resolves via `usernameField`/`urlField`.
    @discardableResult
    static func createLogin(site: String, username: String, password: String,
                            vaultKey: [UInt8]) throws -> String {
        guard !password.isEmpty else { throw Failure.emptyPassword }
        let now = Date()
        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)

        var fields: [DynamicField] = [
            DynamicField(label: "Username", kind: .username, value: trimmedUser),
            DynamicField(label: "Password", kind: .password, value: password, protected: true),
        ]
        if !trimmedSite.isEmpty {
            fields.append(DynamicField(label: "Website", kind: .url, value: trimmedSite))
        }

        let id = UUID().uuidString
        let title = trimmedSite.isEmpty ? (trimmedUser.isEmpty ? "Login" : trimmedUser) : trimmedSite
        let secret = ItemSecret(title: title, category: .login, fields: fields)
        let sealed = try AESGCM.seal(JSONEncoder().encode(secret), key: vaultKey)

        let store = try VaultStore(recoverable: false)
        let record = ItemRecord(id: id, sealed: sealed, createdAt: now, updatedAt: now)
        record.passwordChangedAt = now   // rotation baseline (matches VaultRepository.add)
        store.context.insert(record)
        try store.context.save()
        return id
    }
}
