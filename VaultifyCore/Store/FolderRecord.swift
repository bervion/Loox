import Foundation
import SwiftData

/// Persistent record for one folder ("Space"). The name lives only inside
/// `sealed` (AES-256-GCM under the Vault Key); the icon, color, sort order, and
/// sync metadata are plaintext so the store can sort and sync can reconcile
/// without unsealing. Mirrors `ItemRecord`'s sync columns for CloudKit parity.
@Model
final class FolderRecord {
    @Attribute(.unique) var id: String
    /// AES-256-GCM sealed `FolderSecret` (nonce ‖ ciphertext ‖ tag).
    var sealed: Data
    /// Polaris icon name — reveals nothing about the folder's contents.
    var iconAsset: String
    /// `FolderColor.rawValue` — non-secret presentation metadata.
    var colorRaw: String
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?

    // Sync metadata (CloudKit) — mirrors ItemRecord.
    var dirty: Bool
    var ckRecordName: String?
    var ckChangeTag: String?

    init(id: String,
         sealed: Data,
         iconAsset: String,
         colorRaw: String,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.sealed = sealed
        self.iconAsset = iconAsset
        self.colorRaw = colorRaw
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = nil
        self.dirty = true
    }
}
