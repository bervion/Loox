import Foundation
import SwiftData

/// Owns the SwiftData `ModelContainer` for the encrypted vault.
@MainActor
final class VaultStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: SharedConfig.storeURL)
        do {
            container = try ModelContainer(for: ItemRecord.self, PasskeyRecord.self, configurations: configuration)
        } catch {
            fatalError("Failed to initialise vault store: \(error)")
        }
    }

    /// Permanently delete every record (used by "Erase Vault").
    func eraseAll() throws {
        try context.delete(model: ItemRecord.self)
        try context.save()
    }

    // MARK: Sync access (operates on opaque ciphertext — no Vault Key needed)

    /// All records including soft-deleted tombstones (for sync reconciliation).
    func allRecords() -> [ItemRecord] {
        (try? context.fetch(FetchDescriptor<ItemRecord>())) ?? []
    }

    func record(id: String) -> ItemRecord? {
        var descriptor = FetchDescriptor<ItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Last-writer-wins upsert of a remote record (ciphertext + metadata).
    func upsertFromRemote(id: String, sealed: Data, favorite: Bool, trashedAt: Date?,
                          deletedAt: Date?, createdAt: Date, updatedAt: Date,
                          changeTag: String?) {
        if let existing = record(id: id) {
            guard updatedAt > existing.updatedAt else { return }
            existing.sealed = sealed
            existing.favorite = favorite
            existing.trashedAt = trashedAt
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
            existing.ckChangeTag = changeTag
            existing.dirty = false
        } else {
            let record = ItemRecord(id: id, sealed: sealed, favorite: favorite,
                                    createdAt: createdAt, updatedAt: updatedAt, trashedAt: trashedAt)
            record.deletedAt = deletedAt
            record.ckChangeTag = changeTag
            record.dirty = false
            context.insert(record)
        }
        try? context.save()
    }

    func markSynced(_ record: ItemRecord, changeTag: String?) {
        record.dirty = false
        record.ckChangeTag = changeTag
        try? context.save()
    }
}
