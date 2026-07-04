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
        // `cloudKitDatabase: .none` is REQUIRED, not cosmetic: the default `.automatic`
        // detects the app's iCloud entitlement and silently enables SwiftData↔CloudKit
        // mirroring, whose schema rules (all attributes optional-or-default, no unique
        // constraints) our records don't meet → the container fails to load and the app
        // crashes at launch. Sync is done manually by `CloudSyncService` instead.
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            : ModelConfiguration(url: SharedConfig.storeURL, cloudKitDatabase: .none)
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
    ///
    /// Two independent LWW gates: **content** (sealed blob + columns written together with
    /// it) merges by `updatedAt`; **meta** (`pinned`/`archived` — column-only toggles that
    /// deliberately don't bump `updatedAt`) merges by `metaUpdatedAt`. `useCount` is
    /// device-local by design and is never overwritten from remote.
    ///
    /// Timestamps are device wall clocks, so a skewed clock can still prefer the "wrong"
    /// writer between two *different* revisions; the change-tag short-circuit at least makes
    /// re-processing the *same* server revision a guaranteed no-op regardless of clocks.
    @MainActor
    func upsertFromRemote(id: String, sealed: Data, favorite: Bool, trashedAt: Date?,
                          deletedAt: Date?, createdAt: Date, updatedAt: Date,
                          pinned: Bool, archived: Bool, metaUpdatedAt: Date,
                          isDefaultIdentity: Bool, avatarSealed: Data?,
                          changeTag: String?) {
        if let existing = record(id: id) {
            // Already merged this exact server revision — skip (clock-skew-proof no-op).
            if let changeTag, changeTag == existing.ckChangeTag { return }
            let applyContent = updatedAt > existing.updatedAt
            let applyMeta = metaUpdatedAt > existing.metaUpdatedAt
            // The server holds a DIFFERENT revision (tag mismatch) that is strictly
            // OLDER on a gate → an out-of-order push overwrote the server with stale
            // state (push runs blind, `.changedKeys`, no server tag carried). Re-mark
            // dirty so the local winner re-pushes — self-healing regardless of which
            // device pushed first. Strict `>` only: dirtying on equal timestamps with
            // differing tags would ping-pong between devices forever.
            let localContentWins = existing.updatedAt > updatedAt
            let localMetaWins = existing.metaUpdatedAt > metaUpdatedAt
            guard applyContent || applyMeta else {
                if localContentWins || localMetaWins {
                    existing.dirty = true
                    try? context.save()
                }
                return
            }
            if applyContent {
                existing.sealed = sealed
                existing.favorite = favorite
                existing.trashedAt = trashedAt
                existing.deletedAt = deletedAt
                existing.updatedAt = updatedAt
                existing.isDefaultIdentity = isDefaultIdentity
                existing.avatarSealed = avatarSealed
            }
            if applyMeta {
                existing.pinned = pinned
                existing.archived = archived
                existing.metaUpdatedAt = metaUpdatedAt
            }
            existing.ckChangeTag = changeTag
            // Only a full remote win supersedes pending local changes. A one-sided apply
            // means the local side still holds the newer half — force it dirty so it
            // re-pushes even when a completed earlier push had cleared the flag.
            if applyContent && applyMeta {
                existing.dirty = false
            } else if localContentWins || localMetaWins {
                existing.dirty = true
            }
        } else {
            let record = ItemRecord(id: id, sealed: sealed, favorite: favorite,
                                    createdAt: createdAt, updatedAt: updatedAt, trashedAt: trashedAt)
            record.deletedAt = deletedAt
            record.pinned = pinned
            record.archived = archived
            record.metaUpdatedAt = metaUpdatedAt
            record.isDefaultIdentity = isDefaultIdentity
            record.avatarSealed = avatarSealed
            record.ckChangeTag = changeTag
            record.dirty = false
            context.insert(record)
        }
        try? context.save()
    }

    /// Clear `dirty` after a successful push — but only if the record hasn't been edited
    /// again since the push snapshot was taken. `modifyRecords` is a suspension point; an
    /// edit made during the await must stay dirty or it would silently never push.
    @MainActor
    func markSynced(_ record: ItemRecord, changeTag: String?,
                    snapshotUpdatedAt: Date, snapshotMetaUpdatedAt: Date) {
        record.ckChangeTag = changeTag
        if record.updatedAt == snapshotUpdatedAt && record.metaUpdatedAt == snapshotMetaUpdatedAt {
            record.dirty = false
        }
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
    /// Every folder mutation bumps `updatedAt` (single content gate suffices — folders
    /// have no column-only toggles). Icon/color/sortIndex are plaintext presentation
    /// metadata by design; the sync guarantee is "secrets sealed", not "zero cleartext".
    @MainActor
    func upsertFolderFromRemote(id: String, sealed: Data, iconAsset: String, colorRaw: String,
                                sortIndex: Int, deletedAt: Date?, createdAt: Date, updatedAt: Date,
                                changeTag: String?) {
        if let existing = folderRecord(id: id) {
            // Same server revision already merged — skip regardless of clocks.
            if let changeTag, changeTag == existing.ckChangeTag { return }
            guard updatedAt > existing.updatedAt else {
                // Server holds a different, strictly-older revision → an out-of-order
                // push overwrote it; re-push the local winner (see item analogue above).
                if existing.updatedAt > updatedAt {
                    existing.dirty = true
                    try? context.save()
                }
                return
            }
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

    /// Folder analogue of `markSynced` — clear `dirty` only if unchanged since the
    /// push snapshot (an edit during the in-flight push must stay dirty).
    @MainActor
    func markFolderSynced(_ record: FolderRecord, changeTag: String?, snapshotUpdatedAt: Date) {
        record.ckChangeTag = changeTag
        if record.updatedAt == snapshotUpdatedAt {
            record.dirty = false
        }
        try? context.save()
    }
}
