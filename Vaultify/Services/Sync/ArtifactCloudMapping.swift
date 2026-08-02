import CloudKit
import Foundation

/// Wire mapping for the (flag-gated, not yet live) CloudKit artifact plane.
///
/// Record type `ArtifactV2`. Everything secret rides sealed: `wrappedDEK`
/// (Vault-Key-wrapped artifact key), `sealedManifest` (DEK-sealed metadata),
/// and the ciphertext file itself as a `CKAsset`. Plaintext columns are the
/// same organizational shape the item plane exposes: an opaque owner id,
/// byte count + ciphertext hash for integrity, and timestamps.
///
/// This file is mapping + merge policy ONLY. It is deliberately NOT wired
/// into `CloudSyncService`'s push/pull: convergence of the artifact plane
/// (asset upload retries, partial-download honesty, two-phase delete) gates
/// behind `SettingsStore.artifactSyncEnabled`, which ships default-off until
/// that behavior is proven.
enum ArtifactCloudMapping {
    static let recordType = "ArtifactV2"

    /// Per-plane delta-pull cursor key (each plane owns its own token so an
    /// artifact backfill can never stall the item planes' cursor).
    static let cursorKey = "cloudkit_artifact_zone_change_token"

    /// Two-phase delete: phase one pushes the record as a tombstone
    /// (`deletedAtMs > 0`, sealed fields emptied, no asset) so every device
    /// learns of the deletion; phase two hard-deletes the CKRecord only after
    /// the tombstone has been server-visible this long, so a device that was
    /// offline through phase one still converges instead of resurrecting.
    static let tombstoneRetentionSeconds: TimeInterval = 30 * 24 * 60 * 60

    /// A pulled remote artifact, decoded field-for-field. `assetFileURL` is
    /// CloudKit's local download cache for the ciphertext; nil on tombstones
    /// and when the server had no asset (the record then imports as the
    /// honest missing-bytes state).
    struct RemoteArtifact: Equatable {
        var id: String
        var ownerItemId: String
        var wrappedDEK: Data
        var sealedManifest: Data
        var byteCount: Int
        var ciphertextHash: Data
        var deletedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var assetFileURL: URL?
    }

    enum MergeDecision: Equatable {
        case applyRemote
        case keepLocal
    }

    /// Build the CKRecord this device would push for a local artifact record.
    /// Every non-asset field is ALWAYS assigned — `.changedKeys` transmits only
    /// keys present on a fresh CKRecord, so absence must ride in-band (empty
    /// Data / 0 ms) or the server copy could never be cleared. The asset is the
    /// one field with no in-band empty form: it is attached only when a live
    /// ciphertext file exists, and tombstone convergence relies on
    /// `deletedAtMs` (readers ignore the asset on tombstones) plus the
    /// two-phase hard delete — never on clearing the asset field itself.
    static func ckRecord(from record: ArtifactRecord, zoneID: CKRecordZone.ID,
                         assetFileURL: URL?) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zoneID)
        let ck = CKRecord(recordType: recordType, recordID: id)
        let tombstoned = record.deletedAt != nil
        ck["ownerItemId"] = record.ownerItemId as CKRecordValue
        ck["wrappedDEK"] = (tombstoned ? Data() : record.wrappedDEK) as CKRecordValue
        ck["sealedManifest"] = (tombstoned ? Data() : record.sealedManifest) as CKRecordValue
        ck["byteCount"] = Int64(tombstoned ? 0 : record.byteCount) as CKRecordValue
        ck["ciphertextHash"] = (tombstoned ? Data() : record.ciphertextHash) as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        let deletedAtMs = record.deletedAt.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        ck["deletedAtMs"] = deletedAtMs as CKRecordValue
        if !tombstoned, let assetFileURL {
            ck["asset"] = CKAsset(fileURL: assetFileURL)
        }
        return ck
    }

    /// Decode a pulled CKRecord. Returns nil when any required field is
    /// missing (schema drift must not land as a half-written artifact).
    static func parse(_ record: CKRecord) -> RemoteArtifact? {
        guard let ownerItemId = record["ownerItemId"] as? String,
              let wrappedDEK = record["wrappedDEK"] as? Data,
              let sealedManifest = record["sealedManifest"] as? Data,
              let byteCount = record["byteCount"] as? Int64,
              let ciphertextHash = record["ciphertextHash"] as? Data,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date,
              let deletedAtMs = record["deletedAtMs"] as? Int64 else { return nil }
        let deletedAt = deletedAtMs > 0
            ? Date(timeIntervalSince1970: TimeInterval(deletedAtMs) / 1000) : nil
        // A tombstone's asset (if a stale one survived) is dead weight, never data.
        let assetURL = deletedAt == nil ? (record["asset"] as? CKAsset)?.fileURL : nil
        return RemoteArtifact(id: record.recordID.recordName,
                              ownerItemId: ownerItemId,
                              wrappedDEK: wrappedDEK,
                              sealedManifest: sealedManifest,
                              byteCount: Int(byteCount),
                              ciphertextHash: ciphertextHash,
                              deletedAt: deletedAt,
                              createdAt: createdAt,
                              updatedAt: updatedAt,
                              assetFileURL: assetURL)
    }

    /// Merge policy: artifacts are single-owner and immutable after commit, so
    /// content merges last-writer-wins by `updatedAt` — except a tombstone,
    /// which wins over live content in BOTH directions regardless of clocks
    /// (a deletion must never be resurrected by a skewed wall clock).
    static func merge(localUpdatedAt: Date, localDeletedAt: Date?,
                      remoteUpdatedAt: Date, remoteDeletedAt: Date?) -> MergeDecision {
        switch (localDeletedAt != nil, remoteDeletedAt != nil) {
        case (false, true): return .applyRemote
        case (true, false): return .keepLocal
        default: return remoteUpdatedAt > localUpdatedAt ? .applyRemote : .keepLocal
        }
    }
}
