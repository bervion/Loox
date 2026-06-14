import Foundation
import SwiftData

/// Persistent record for one vault item. The content (title, category, fields)
/// lives only inside `sealed` (AES-256-GCM under the Vault Key) — never in
/// plaintext columns. Low-sensitivity metadata is kept as columns so the store
/// can filter/sort and so sync can reconcile without unsealing.
@Model
final class ItemRecord {
    @Attribute(.unique) var id: String
    /// AES-256-GCM sealed `ItemSecret` (nonce ‖ ciphertext ‖ tag).
    var sealed: Data
    var favorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var trashedAt: Date?
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?
    /// Last in-app copy/reveal time (powers Recents). Plaintext (timing only,
    /// not content), device-local — intentionally NOT synced.
    var lastUsedAt: Date?

    // Sync metadata (CloudKit).
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String,
         sealed: Data,
         favorite: Bool = false,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         trashedAt: Date? = nil) {
        self.id = id
        self.sealed = sealed
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trashedAt = trashedAt
        self.deletedAt = nil
        self.lastUsedAt = nil
        self.dirty = true
    }
}
