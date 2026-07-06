import Foundation
import SwiftData

/// Persistent record for one forwarding inbox. The email/label/default flag
/// live only inside `sealed` (AES-256-GCM under the Vault Key); sort order and
/// sync metadata are plaintext so the store can sort and sync can reconcile
/// without unsealing. Mirrors `EmailAliasRecord` exactly (whole-record LWW by
/// `updatedAt`, soft-delete tombstone).
@Model
final class ForwardingInboxRecord {
    @Attribute(.unique) var id: String
    var sealed: Data
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?

    // Sync metadata (CloudKit) — mirrors EmailAliasRecord.
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
