import Foundation
import SwiftData

/// Persistent record for one COMPLETED audit run. Append-only by design (a
/// report is never edited after it is written), pruned to a per-persona cap.
/// The report content — score, pillars, finding digests — lives only inside
/// `sealed` (AES-256-GCM under the Vault Key, `AuditReportPayload`). Plaintext
/// columns carry just what listing and sync need: never a password, hash,
/// HIBP suffix, or finding content.
@Model
final class AuditReportRecord {
    @Attribute(.unique) var id: String
    /// Persona partition (persona IDs are plaintext record names everywhere).
    var personaID: String?
    /// AES-256-GCM sealed `AuditReportPayload` (nonce ‖ ciphertext ‖ tag).
    var sealed: Data
    /// Plaintext so history can sort without unsealing (timing only).
    var completedAt: Date
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete tombstone retained for sync reconciliation (prune).
    var deletedAt: Date?

    // Sync metadata (CloudKit) — mirrors FolderRecord.
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String = UUID().uuidString,
         personaID: String?,
         sealed: Data,
         completedAt: Date,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.personaID = personaID
        self.sealed = sealed
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
        self.dirty = true
    }
}
