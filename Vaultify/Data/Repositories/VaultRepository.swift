import Foundation
import SwiftData
import UserNotifications

/// Decrypts vault records into an in-memory cache on unlock and performs CRUD,
/// re-sealing payloads under the Vault Key. The cache is cleared on lock.
@MainActor @Observable final class VaultRepository {
    // Internal (not private) so the `+Folders` extension in a sibling file can
    // reach the store/session; the item seal/decrypt helpers stay private.
    let store: VaultStore
    let session: VaultSession

    private(set) var items: [VaultItem] = []
    private(set) var trashed: [VaultItem] = []
    private(set) var archived: [VaultItem] = []
    private(set) var folders: [Folder] = []

    init(store: VaultStore, session: VaultSession) {
        self.store = store
        self.session = session
    }

    var isEmpty: Bool { items.isEmpty && trashed.isEmpty && archived.isEmpty }

    func clear() {
        items = []
        trashed = []
        archived = []
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
        var arch: [VaultItem] = []
        for record in records {
            guard let item = try? decrypt(record, key: key) else { continue }
            // Trash wins over archive when an item is both; archived items stay out
            // of every normal surface but remain reachable in the Archive screen.
            if item.isTrashed { trash.append(item) }
            else if item.archived { arch.append(item) }
            else { active.append(item) }
        }
        items = active.sorted { $0.updatedAt > $1.updatedAt }
        trashed = trash.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
        archived = arch.sorted { $0.updatedAt > $1.updatedAt }
        folders = loadFolders(key: key)
        CredentialIdentityService.refresh(items: items)
        normalizeDefaultIdentity()
    }

    // MARK: Default identity (single-active invariant)

    /// Ensure exactly one ACTIVE identity carries the default marker. Converges sync
    /// conflicts (two devices each picked a default → a transient double-default) and
    /// promotes a replacement when the old default leaves the active set. Runs at the
    /// tail of `reload()`; writes only when the active identities are inconsistent and
    /// **never calls `reload()`** (it patches the freshly-built `items` in place).
    private func normalizeDefaultIdentity() {
        let identities = items.filter { $0.category == .identity }
        guard !identities.isEmpty else { return }
        guard identities.filter(\.isDefaultIdentity).count != 1 else { return }
        // Winner = most recently touched (`updatedAt`), `createdAt` as the final tiebreak.
        guard let winner = identities.max(by: {
            ($0.updatedAt, $0.createdAt) < ($1.updatedAt, $1.createdAt)
        }) else { return }
        let now = Date()
        var didWrite = false
        for identity in identities {
            let shouldBeDefault = identity.id == winner.id
            guard identity.isDefaultIdentity != shouldBeDefault else { continue }
            writeIdentityDefault(id: identity.id, isDefault: shouldBeDefault, now: now)
            if let idx = items.firstIndex(where: { $0.id == identity.id }) {
                items[idx].isDefaultIdentity = shouldBeDefault
                items[idx].updatedAt = now
            }
            didWrite = true
        }
        if didWrite { try? store.context.save() }
    }

    /// Set the default-identity marker on a record and bump `updatedAt` so the change
    /// propagates through the whole-record LWW CloudKit sync (a column-only write is
    /// dropped on pull). Marks the record dirty. Caller is responsible for save + reload.
    /// Internal so the `+Identity` extension can drive `setDefaultIdentity`.
    func writeIdentityDefault(id: String, isDefault: Bool, now: Date) {
        guard let record = store.record(id: id) else { return }
        record.isDefaultIdentity = isDefault
        record.updatedAt = now
        record.dirty = true
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
        record.pinned = item.pinned
        record.archived = item.archived
        record.useCount = item.useCount
        record.isDefaultIdentity = item.isDefaultIdentity
        record.rotateDays = item.rotateDays
        // New items: baseline is createdAt (caller provides it).
        record.passwordChangedAt = item.createdAt
        store.context.insert(record)
        try store.context.save()
        reload()
        RotationNotificationService.shared.schedule(item: item, passwordChangedAt: record.passwordChangedAt)
    }

    func update(_ item: VaultItem) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = try record(id: item.id) else { return try add(item) }
        var updated = item
        updated.updatedAt = .now

        // Detect a real password change by comparing decrypted old password to new.
        // We re-seal regardless; the comparison is purely for the timestamp.
        let oldPassword = passwordValue(for: record, key: key)
        let newPassword = item.passwordField?.value

        record.sealed = try seal(updated, key: key)
        record.favorite = updated.favorite
        record.trashedAt = updated.trashedAt
        record.updatedAt = updated.updatedAt
        record.rotateDays = updated.rotateDays
        record.dirty = true

        if oldPassword != newPassword {
            // Password value changed — reset the baseline so rotation tracking is accurate.
            record.passwordChangedAt = .now
        }

        try store.context.save()
        reload()
        RotationNotificationService.shared.schedule(
            item: updated, passwordChangedAt: record.passwordChangedAt)
    }

    func toggleFavorite(_ item: VaultItem) throws {
        var updated = item
        updated.favorite.toggle()
        try update(updated)
    }

    /// Pin/unpin (Home "Pinned"). Column-only — no re-seal, no `updatedAt` bump,
    /// so it never pollutes "Recently Modified".
    func togglePin(_ item: VaultItem) { setColumn(item.id) { $0.pinned.toggle() } }

    /// Archive / unarchive — keeps the item out of normal lists without deleting
    /// it. Same column-only contract as pin.
    func archive(_ item: VaultItem) { setColumn(item.id) { $0.archived = true } }
    func unarchive(_ item: VaultItem) { setColumn(item.id) { $0.archived = false } }

    /// Mutate a plaintext metadata column, mark dirty for sync, and reload —
    /// without re-sealing or bumping `updatedAt`.
    private func setColumn(_ id: String, _ mutate: (ItemRecord) -> Void) {
        guard let record = store.record(id: id) else { return }
        mutate(record)
        record.dirty = true
        try? store.context.save()
        reload()
    }

    /// Record an in-app use (copy/reveal) for Recents + Frequently Used. Writes
    /// only the plaintext `lastUsedAt`/`useCount` columns — no re-seal, no
    /// `dirty`, no `reload()` — and patches the in-memory cache in place.
    func markUsed(_ item: VaultItem) {
        guard let record = store.record(id: item.id) else { return }
        record.lastUsedAt = .now
        record.useCount += 1
        try? store.context.save()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].lastUsedAt = record.lastUsedAt
            items[idx].useCount = record.useCount
        }
    }

    func moveToTrash(_ item: VaultItem) throws {
        var updated = item
        updated.trashedAt = .now
        try update(updated)
        RotationNotificationService.shared.cancel(itemID: item.id)
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
        RotationNotificationService.shared.cancel(itemID: item.id)
    }

    // MARK: Attention list

    /// Items that need user attention: overdue rotation, then weak passwords,
    /// then soon-due rotation, then stale (no cadence, 180+ days). Excludes
    /// trashed/archived items.
    func itemsNeedingAttention(limit: Int = 50) -> [VaultItem] {
        typealias Ranked = (item: VaultItem, order: Int)
        var ranked: [Ranked] = []
        for item in items {
            let status = RotationStatus.evaluate(
                rotateDays: item.rotateDays,
                passwordChangedAt: item.passwordChangedAt,
                createdAt: item.createdAt)
            let isWeak = (item.passwordField.map { PasswordStrength.evaluate($0.value) } ?? .strong) == .weak
            let reason = RotationStatus.attentionReason(status: status, isWeak: isWeak)
            switch reason {
            case .overdue:  ranked.append((item, 0))
            case .weak:     ranked.append((item, 1))
            case .soon:     ranked.append((item, 2))
            case .stale:    ranked.append((item, 3))
            case .none:     break
            }
        }
        return ranked
            .sorted { $0.order < $1.order }
            .prefix(limit)
            .map(\.item)
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
                         pinned: record.pinned,
                         archived: record.archived,
                         useCount: record.useCount,
                         isDefaultIdentity: record.isDefaultIdentity,
                         rotateDays: record.rotateDays,
                         passwordChangedAt: record.passwordChangedAt,
                         createdAt: record.createdAt,
                         updatedAt: record.updatedAt,
                         trashedAt: record.trashedAt)
    }

    /// Unseal the record and return just the password field value. Returns nil
    /// on any error (key mismatch, missing field). Used only to detect actual
    /// password changes without a separate decrypt path.
    private func passwordValue(for record: ItemRecord, key: SecureBytes) -> String? {
        guard let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(ItemSecret.self, from: plaintext)
        else { return nil }
        return secret.fields.first { $0.kind == .password }?.value
    }

    private func record(id: String) throws -> ItemRecord? {
        var descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try store.context.fetch(descriptor).first
    }
}
