import Foundation
import SwiftData

/// Where an artifact's ciphertext is allowed to travel.
nonisolated enum ArtifactSyncPolicy: String, Sendable {
    /// Ciphertext stays in this device's App Group container only.
    case localOnly
    /// Ciphertext may ride the (flag-gated) CloudKit artifact plane as a CKAsset.
    case synced
}

/// Persistent record for one owned encrypted artifact (attachment binary).
///
/// The secret content lives in two sealed pieces: the ciphertext FILE at
/// `relativePath` inside the App Group `Artifacts-v2/` directory (sealed under
/// the artifact's own DEK), and `sealedManifest` (filename, UTI, plaintext
/// size + hash — also sealed under the DEK). The DEK itself is stored only
/// wrapped by the Vault Key, AAD-bound to `(id, ownerItemId)`, so neither the
/// key nor the bytes can be re-parented to another artifact or item.
///
/// A missing file with a live record is a legal, HONEST state ("bytes not on
/// this device") — the record must never be silently dropped for it.
@Model
final class ArtifactRecord {
    @Attribute(.unique) var id: String
    /// The vault item this artifact belongs to (single owner, never shared).
    var ownerItemId: String
    /// Artifact DEK wrapped by the Vault Key (AAD-bound to id + owner).
    var wrappedDEK: Data
    /// `ArtifactManifest` sealed under the DEK (AAD-bound to id + owner).
    var sealedManifest: Data
    /// Ciphertext file location relative to the artifacts root — `<id>.enc`,
    /// so the file name leaks nothing (the id is a random UUID).
    var relativePath: String
    /// Byte count of the ciphertext envelope file (plaintext size lives sealed
    /// inside the manifest). Lets integrity checks run without opening anything.
    var byteCount: Int
    /// SHA-256 of the ciphertext envelope — proves the file on disk (or a
    /// synced asset) is the exact bytes this record describes.
    var ciphertextHash: Data
    /// Soft-delete tombstone retained for sync reconciliation.
    var deletedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata (CloudKit artifact plane, flag-gated).
    var dirty: Bool
    /// Raw `ArtifactSyncPolicy` — a string column so the schema never fights
    /// the enum over migrations.
    var syncPolicy: String

    init(id: String,
         ownerItemId: String,
         wrappedDEK: Data,
         sealedManifest: Data,
         relativePath: String,
         byteCount: Int,
         ciphertextHash: Data,
         syncPolicy: ArtifactSyncPolicy = .localOnly,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.ownerItemId = ownerItemId
        self.wrappedDEK = wrappedDEK
        self.sealedManifest = sealedManifest
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.ciphertextHash = ciphertextHash
        self.deletedAt = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dirty = true
        self.syncPolicy = syncPolicy.rawValue
    }
}
