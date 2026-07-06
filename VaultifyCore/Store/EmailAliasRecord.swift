import Foundation
import SwiftData

/// Persistent record for one email alias. Identity-bearing content (owner,
/// local-part, bindings, status, forwarding target) lives only inside `sealed`
/// (AES-256-GCM under the Vault Key); the sort order and sync metadata are
/// plaintext so the store can sort and sync can reconcile without unsealing.
/// Mirrors `PersonaRecord` minus the default flag (aliases have no singleton
/// invariant). `status`/`tier` stay sealed — no plaintext status signal in
/// CloudKit; they ride the `updatedAt` content gate.
@Model
final class EmailAliasRecord {
    @Attribute(.unique) var id: String
    var sealed: Data
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?

    // Sync metadata (CloudKit) — mirrors PersonaRecord.
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String,
         sealed: Data,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.sealed = sealed
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
        self.dirty = true
    }
}
