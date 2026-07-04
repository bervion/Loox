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
    /// Pinned to the top of Home — a separate concept from `favorite`.
    var pinned: Bool = false
    /// Archived: kept out of normal lists but not deleted (no auto-purge).
    var archived: Bool = false
    /// In-app use tally powering "Frequently Used". Plaintext, device-local.
    var useCount: Int = 0
    /// Rotation reminder cadence in days: 0 = off, 15 / 30 / 90 = enabled.
    /// Plaintext — reveals timing preference only, not secret content. Currently
    /// device-local (not in the CloudKit mapping); add to `CloudSyncService` if
    /// per-item cadence should sync once iCloud is enabled.
    var rotateDays: Int = 0
    /// When the password was last changed. Nil means use `createdAt` as the
    /// baseline. Updated only when the decrypted password value actually changes.
    /// Device-local for now (see `rotateDays` note re: CloudKit).
    var passwordChangedAt: Date?
    /// Marks this item as the user's default identity (only meaningful for the
    /// `.identity` category). Synced; the app enforces a single active default.
    /// Changing it bumps `updatedAt` so the whole-record LWW sync propagates it.
    var isDefaultIdentity: Bool = false
    /// LWW timestamp for the column-only metadata (`pinned`/`archived`). Those toggles
    /// deliberately do NOT bump `updatedAt` (so they never pollute "Recently Modified"),
    /// which would make the content-LWW gate drop them on pull — so they carry their own
    /// timestamp and sync merges content and meta independently. `.distantPast` default
    /// keeps pre-existing rows migration-safe (any real change wins).
    var metaUpdatedAt: Date = Date.distantPast
    /// AES-256-GCM-sealed (Vault Key) downscaled avatar JPEG for an identity.
    /// Synced as a CKRecord Data field — zero-knowledge (iCloud sees ciphertext).
    /// Nil → the UI shows the letter-avatar fallback.
    var avatarSealed: Data?

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
