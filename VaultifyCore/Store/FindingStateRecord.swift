import Foundation
import SwiftData

/// User-set state for one audit finding, keyed by the finding's stable
/// fingerprint (natural key → merges are idempotent across devices). Only
/// USER decisions are stored — ignored, accepted risk, snooze; `resolved` and
/// `noLongerMonitored` are derived by comparing audit runs, never persisted.
/// The reason/rule metadata live inside `sealed` (`FindingStatePayload`);
/// the bare status enum raw value is a plaintext column for cheap filtering
/// (it reveals THAT something was dismissed, never what it was).
@Model
final class FindingStateRecord {
    /// = `AuditFinding.fingerprint` (SHA-256 hex, no plaintext inside).
    @Attribute(.unique) var id: String
    var personaID: String?
    /// AES-256-GCM sealed `FindingStatePayload`.
    var sealed: Data
    /// `FindingStatus.rawValue` — plaintext enum label only.
    var status: String
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?

    // Sync metadata (CloudKit) — mirrors FolderRecord.
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String,
         personaID: String?,
         sealed: Data,
         status: String,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.personaID = personaID
        self.sealed = sealed
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
        self.dirty = true
    }
}
