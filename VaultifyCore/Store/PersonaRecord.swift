import Foundation
import SwiftData

/// Persistent record for one persona ("identity"). Identity-bearing fields
/// (name, kind, isolation policy, profile/space links) live only inside `sealed`
/// (AES-256-GCM under the Vault Key). The default flag, sort order, and sync
/// metadata are plaintext so the store can sort and sync can converge the single
/// default without unsealing — mirrors `FolderRecord`, with `isDefault` playing
/// the role `isDefaultIdentity` plays on `ItemRecord`.
@Model
final class PersonaRecord {
    @Attribute(.unique) var id: String
    /// AES-256-GCM sealed `PersonaSecret` (nonce ‖ ciphertext ‖ tag).
    var sealed: Data
    /// Exactly one persona is the default. Carried in the CONTENT gate (bumped
    /// with `updatedAt`), never a column-only toggle, so a change can't be
    /// silently dropped on pull.
    var isDefault: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?

    // Sync metadata (CloudKit) — mirrors FolderRecord.
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String,
         sealed: Data,
         isDefault: Bool = false,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.sealed = sealed
        self.isDefault = isDefault
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
        self.dirty = true
    }
}
