import Foundation
import SwiftData

/// Decrypts vault records into an in-memory cache on unlock and performs CRUD,
/// re-sealing payloads under the Vault Key. The cache is cleared on lock.
@MainActor @Observable final class VaultRepository {
    // Internal (not private) so the `+Folders` extension in a sibling file can
    // reach the store/session; the item seal/decrypt helpers stay private.
    let store: VaultStore
    let session: VaultSession

    private(set) var items: [VaultItem] = []
    private(set) var trashed: [VaultItem] = []
    private(set) var folders: [Folder] = []

    init(store: VaultStore, session: VaultSession) {
        self.store = store
        self.session = session
    }

    var isEmpty: Bool { items.isEmpty && trashed.isEmpty }

    func clear() {
        items = []
        trashed = []
        folders = []
        CredentialIdentityService.clear()
    }

    /// Load and decrypt all live records into the in-memory caches.
    func reload() {
        guard let key = session.vaultKey else { clear(); return }
        let descriptor = FetchDescriptor<ItemRecord>(
            predicate: #Predicate { $0.deletedAt == nil })
        guard let records = try? store.context.fetch(descriptor) else { return }
        var active: [VaultItem] = []
        var trash: [VaultItem] = []
        for record in records {
            guard let item = try? decrypt(record, key: key) else { continue }
            if item.isTrashed { trash.append(item) } else { active.append(item) }
        }
        items = active.sorted { $0.updatedAt > $1.updatedAt }
        trashed = trash.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
        folders = loadFolders(key: key)
        CredentialIdentityService.refresh(items: items)
    }

    // MARK: CRUD

    func add(_ item: VaultItem) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let record = ItemRecord(id: item.id,
                                sealed: try seal(item, key: key),
                                favorite: item.favorite,
                                createdAt: item.createdAt,
                                updatedAt: item.updatedAt,
                                trashedAt: item.trashedAt)
        store.context.insert(record)
        try store.context.save()
        reload()
    }

    func update(_ item: VaultItem) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = try record(id: item.id) else { return try add(item) }
        var updated = item
        updated.updatedAt = .now
        record.sealed = try seal(updated, key: key)
        record.favorite = updated.favorite
        record.trashedAt = updated.trashedAt
        record.updatedAt = updated.updatedAt
        record.dirty = true
        try store.context.save()
        reload()
    }

    func toggleFavorite(_ item: VaultItem) throws {
        var updated = item
        updated.favorite.toggle()
        try update(updated)
    }

    /// Record an in-app use (copy/reveal) for Recents. Writes only the plaintext
    /// `lastUsedAt` column — no re-seal, no `dirty`, no `reload()` — and patches
    /// the in-memory cache in place so Home updates without re-decrypting.
    func markUsed(_ item: VaultItem) {
        guard let record = store.record(id: item.id) else { return }
        record.lastUsedAt = .now
        try? store.context.save()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].lastUsedAt = record.lastUsedAt
        }
    }

    func moveToTrash(_ item: VaultItem) throws {
        var updated = item
        updated.trashedAt = .now
        try update(updated)
    }

    func restore(_ item: VaultItem) throws {
        var updated = item
        updated.trashedAt = nil
        try update(updated)
    }

    /// Soft-delete (tombstone) so sync can propagate the deletion.
    func delete(_ item: VaultItem) throws {
        guard let record = try record(id: item.id) else { return }
        record.deletedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
    }

    func emptyTrash() throws {
        for item in trashed { try delete(item) }
    }

    // MARK: Sealing

    private func seal(_ item: VaultItem, key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(item.secret), key: key)
    }

    private func decrypt(_ record: ItemRecord, key: SecureBytes) throws -> VaultItem {
        let plaintext = try AESGCM.open(record.sealed, key: key)
        let secret = try JSONDecoder().decode(ItemSecret.self, from: plaintext)
        return VaultItem(id: record.id,
                         category: secret.category,
                         title: secret.title,
                         folderId: secret.folderId,
                         fields: secret.fields,
                         favorite: record.favorite,
                         tags: secret.tags,
                         lastUsedAt: record.lastUsedAt,
                         createdAt: record.createdAt,
                         updatedAt: record.updatedAt,
                         trashedAt: record.trashedAt)
    }

    private func record(id: String) throws -> ItemRecord? {
        var descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try store.context.fetch(descriptor).first
    }
}
