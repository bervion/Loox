import Foundation
import SwiftData

/// Owns the SwiftData `ModelContainer` for the encrypted vault.
final class VaultStore {
    let container: ModelContainer

    @MainActor
    var context: ModelContext { container.mainContext }

    @MainActor
    init(inMemory: Bool = false) {
        do { container = try Self.makeContainer(inMemory: inMemory) }
        catch { fatalError("Failed to initialise vault store: \(error)") }
    }

    /// Throwing initialiser for callers that must recover from a container failure instead of
    /// crashing — the AutoFill extension write path, where a `fatalError` would kill the
    /// credential UI mid-registration. The label distinguishes it from the app's `init`.
    @MainActor
    init(recoverable inMemory: Bool) throws {
        container = try Self.makeContainer(inMemory: inMemory)
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: SharedConfig.storeURL)
        return try ModelContainer(for: ItemRecord.self, PasskeyRecord.self, FolderRecord.self,
                                  configurations: configuration)
    }

    /// Permanently delete every record (used by "Erase Vault").
    @MainActor
    func eraseAll() throws {
        try context.delete(model: ItemRecord.self)
        try context.delete(model: FolderRecord.self)
        try context.delete(model: PasskeyRecord.self)
        try context.save()
    }

    // MARK: Sync access (operates on opaque ciphertext — no Vault Key needed)

    /// All records including soft-deleted tombstones (for sync reconciliation).
    @MainActor
    func allRecords() -> [ItemRecord] {
        (try? context.fetch(FetchDescriptor<ItemRecord>())) ?? []
    }

    @MainActor
    func record(id: String) -> ItemRecord? {
        var descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Last-writer-wins upsert of a remote record (ciphertext + metadata).
    @MainActor
    func upsertFromRemote(id: String, sealed: Data, favorite: Bool, trashedAt: Date?,
                          deletedAt: Date?, createdAt: Date, updatedAt: Date,
                          pinned: Bool, archived: Bool, useCount: Int,
                          isDefaultIdentity: Bool, avatarSealed: Data?,
                          changeTag: String?) {
        if let existing = record(id: id) {
            guard updatedAt > existing.updatedAt else { return }
            existing.sealed = sealed
            existing.favorite = favorite
            existing.trashedAt = trashedAt
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
            existing.pinned = pinned
            existing.archived = archived
            existing.useCount = useCount
            existing.isDefaultIdentity = isDefaultIdentity
            existing.avatarSealed = avatarSealed
            existing.ckChangeTag = changeTag
            existing.dirty = false
        } else {
            let record = ItemRecord(id: id, sealed: sealed, favorite: favorite,
                                    createdAt: createdAt, updatedAt: updatedAt, trashedAt: trashedAt)
            record.deletedAt = deletedAt
            record.pinned = pinned
            record.archived = archived
            record.useCount = useCount
            record.isDefaultIdentity = isDefaultIdentity
            record.avatarSealed = avatarSealed
            record.ckChangeTag = changeTag
            record.dirty = false
            context.insert(record)
        }
        try? context.save()
    }

    @MainActor
    func markSynced(_ record: ItemRecord, changeTag: String?) {
        record.dirty = false
        record.ckChangeTag = changeTag
        try? context.save()
    }

    // MARK: Folder sync access (sealed name + non-secret presentation metadata)

    @MainActor
    func allFolderRecords() -> [FolderRecord] {
        (try? context.fetch(FetchDescriptor<FolderRecord>())) ?? []
    }

    @MainActor
    func folderRecord(id: String) -> FolderRecord? {
        var descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Last-writer-wins upsert of a remote folder record (sealed + metadata).
    @MainActor
    func upsertFolderFromRemote(id: String, sealed: Data, iconAsset: String, colorRaw: String,
                                sortIndex: Int, deletedAt: Date?, createdAt: Date, updatedAt: Date,
                                changeTag: String?) {
        if let existing = folderRecord(id: id) {
            guard updatedAt > existing.updatedAt else { return }
            existing.sealed = sealed
            existing.iconAsset = iconAsset
            existing.colorRaw = colorRaw
            existing.sortIndex = sortIndex
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
            existing.ckChangeTag = changeTag
            existing.dirty = false
        } else {
            let record = FolderRecord(id: id, sealed: sealed, iconAsset: iconAsset, colorRaw: colorRaw,
                                      sortIndex: sortIndex, createdAt: createdAt, updatedAt: updatedAt)
            record.deletedAt = deletedAt
            record.ckChangeTag = changeTag
            record.dirty = false
            context.insert(record)
        }
        try? context.save()
    }

    @MainActor
    func markFolderSynced(_ record: FolderRecord, changeTag: String?) {
        record.dirty = false
        record.ckChangeTag = changeTag
        try? context.save()
    }
}
