import CloudKit
import Foundation

/// B's participant identity lifecycle (ADR-2, Validation §3). The private key
/// exists ONLY sealed under B's Vault Key: in a singleton record in B's
/// private database (so B's other devices recover it) and in a local
/// Keychain fast-path cache of the same sealed envelope.
///
/// Creation is TRANSACTIONAL: generate → seal → publish to CloudKit → cache.
/// If the publish fails the identity is discarded (never "create then wait
/// to escrow" — a crash there would strand an unescrowed key).
///
/// Two devices racing the first creation: the record is saved
/// create-if-not-exists, so the second device's save collides and adopts the
/// first device's identity. First-writer-wins deliberately (vs last-writer):
/// the key the owner may already have pinned can never be silently replaced.
@MainActor final class ParticipantEscrowService {
    enum Failure: Error {
        case notConfigured
        case vaultLocked
        case escrowUnavailable
    }

    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var database: CKDatabase { container.privateCloudDatabase }
    /// Same private zone the vault-key escrow uses.
    private let zone = CKRecordZone(zoneName: "Vault")

    private static let cacheAccount = "approval_participant_escrow_cache_v1"

    /// Return the existing identity (cloud or cache) or transactionally
    /// create one. `vaultKey` proves the vault is unlocked.
    func ensureIdentity(vaultKey: [UInt8]) async throws -> ParticipantIdentity {
        guard CloudSyncService.isConfigured else {
            ShareDiagnostics.log("ESCROW", "FAIL notConfigured (CloudSyncService.isConfigured=false)")
            throw Failure.notConfigured
        }
        guard !vaultKey.isEmpty else {
            ShareDiagnostics.log("ESCROW", "FAIL vaultLocked (empty key)")
            throw Failure.vaultLocked
        }

        // Fast path: locally cached sealed envelope.
        if let cached = try? KeychainStore.get(account: Self.cacheAccount),
           let identity = try? ParticipantIdentity.fromEscrow(cached, vaultKey: vaultKey) {
            ShareDiagnostics.log("ESCROW", "identity from local cache")
            return identity
        }
        // Cloud copy (another device already created it).
        if let envelope = try await fetchEscrowEnvelope() {
            let identity = try ParticipantIdentity.fromEscrow(envelope, vaultKey: vaultKey)
            try? KeychainStore.set(envelope, account: Self.cacheAccount)
            ShareDiagnostics.log("ESCROW", "identity from cloud copy")
            return identity
        }
        ShareDiagnostics.log("ESCROW", "creating new identity (transactional)")
        // Transactional create: publish MUST succeed before the key is used.
        // The zone is created here, NOT assumed: with vault sync OFF (the
        // ADR-2 scenario) `CloudSyncService` never made it, and this save
        // would die with `zoneNotFound`.
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        let identity = ParticipantIdentity.generate()
        let envelope = try identity.escrowSealed(vaultKey: vaultKey)
        let record = CKRecord(recordType: ApprovalConfig.participantEscrowRecordType,
                              recordID: escrowRecordID())
        record[ApprovalRecordMapping.Field.sealed] = envelope as CKRecordValue
        do {
            let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                         savePolicy: .ifServerRecordUnchanged)
            for (_, result) in saved.saveResults {
                if case .failure(let error) = result, Self.isExistingRecordCollision(error) {
                    return try await adoptExisting(vaultKey: vaultKey)
                }
                _ = try result.get()
            }
            try? KeychainStore.set(envelope, account: Self.cacheAccount)
            return identity
        } catch let error where Self.isExistingRecordCollision(error) {
            // Collision: another device won the race — adopt ITS identity
            // (first-writer-wins keeps any owner-side pin stable).
            return try await adoptExisting(vaultKey: vaultKey)
        }
    }

    /// `serverRecordChanged` may surface directly, per-record, or wrapped in
    /// a `partialFailure` — treat all shapes as "record already exists".
    private static func isExistingRecordCollision(_ error: any Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .serverRecordChanged { return true }
        if ckError.code == .partialFailure,
           let partials = ckError.partialErrorsByItemID?.values {
            return partials.contains { ($0 as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }

    private func adoptExisting(vaultKey: [UInt8]) async throws -> ParticipantIdentity {
        guard let existing = try await fetchEscrowEnvelope() else { throw Failure.escrowUnavailable }
        let adopted = try ParticipantIdentity.fromEscrow(existing, vaultKey: vaultKey)
        try? KeychainStore.set(existing, account: Self.cacheAccount)
        return adopted
    }

    private func escrowRecordID() -> CKRecord.ID {
        CKRecord.ID(recordName: ApprovalConfig.participantEscrowRecordName, zoneID: zone.zoneID)
    }

    private func fetchEscrowEnvelope() async throws -> Data? {
        guard let record = try? await database.record(for: escrowRecordID()) else { return nil }
        return record[ApprovalRecordMapping.Field.sealed] as? Data
    }

    /// Vault erase / approval teardown.
    static func clearLocalCache() {
        KeychainStore.delete(account: cacheAccount)
    }
}
