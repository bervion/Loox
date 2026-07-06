import CloudKit
import Foundation

/// The Relay Principal's lifecycle (D3). The private key exists ONLY sealed under
/// the Vault Key: in a singleton record in the private database (so other devices
/// recover it) and in a local Keychain fast-path cache of the same envelope.
/// Structurally identical to `ParticipantEscrowService` — genesis is transactional
/// first-writer-wins (a pinned principalID is never silently replaced); rotation
/// is a deliberate last-writer-wins overwrite.
///
/// Gated on `CloudSyncService.isConfigured` (VAULTIFY_ICLOUD); no user path calls
/// it yet (`RelayFeature.activeAliasesEnabled` is false), so a non-iCloud build
/// simply throws `.notConfigured`.
@MainActor final class RelayPrincipalEscrowService {
    enum Failure: Error { case notConfigured, vaultLocked, escrowUnavailable }

    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var database: CKDatabase { container.privateCloudDatabase }
    /// Same private zone the vault-key + participant escrow use — so `eraseRemote`
    /// dropping this zone also destroys the principal (D4).
    private let zone = CKRecordZone(zoneName: "Vault")

    private static let cacheAccount = RelayConfig.escrowKeychainAccount

    /// Return the existing principal (cache or cloud) or transactionally create one.
    func ensurePrincipal(vaultKey: [UInt8]) async throws -> RelayPrincipalIdentity {
        guard CloudSyncService.isConfigured else { throw Failure.notConfigured }
        guard !vaultKey.isEmpty else { throw Failure.vaultLocked }

        if let cached = try? KeychainStore.get(account: Self.cacheAccount),
           let identity = try? RelayPrincipalIdentity.fromEscrow(cached, vaultKey: vaultKey) {
            return identity
        }
        if let envelope = try await fetchEscrowEnvelope() {
            let identity = try RelayPrincipalIdentity.fromEscrow(envelope, vaultKey: vaultKey)
            try? KeychainStore.set(envelope, account: Self.cacheAccount)
            return identity
        }
        // Transactional create — self-create the zone (vault sync may be OFF).
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        let identity = RelayPrincipalIdentity.generate()
        let envelope = try identity.escrowSealed(vaultKey: vaultKey)
        let record = CKRecord(recordType: RelayConfig.escrowRecordType, recordID: escrowRecordID())
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
            return try await adoptExisting(vaultKey: vaultKey)
        }
    }

    /// Rotate the principal to the next epoch: mint a new key (same principalID),
    /// sign the rotate command with the CURRENT key (proving epoch N authorized
    /// N+1, D5), and OVERWRITE the escrow (last-writer-wins, not the create path).
    /// The signature is returned for the future backend CAS (P4B) — nothing is
    /// sent to a relay here.
    func rotate(vaultKey: [UInt8]) async throws -> (identity: RelayPrincipalIdentity, rotateSignature: Data) {
        guard CloudSyncService.isConfigured else { throw Failure.notConfigured }
        let current = try await ensurePrincipal(vaultKey: vaultKey)
        let next = current.rotated()
        let command = RelayCommand(principalID: current.principalID, epoch: current.epoch,
                                   nonce: Data(CryptoRandom.bytes(16)),
                                   issuedAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000),
                                   kind: .rotatePrincipal, newPublicKey: next.signingPublicKey)
        let signature = try RelayCommandCanonical.sign(command, using: current).signature

        guard let record = try? await database.record(for: escrowRecordID()) else {
            throw Failure.escrowUnavailable
        }
        let envelope = try next.escrowSealed(vaultKey: vaultKey)
        record[ApprovalRecordMapping.Field.sealed] = envelope as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
        try? KeychainStore.set(envelope, account: Self.cacheAccount)
        return (next, signature)
    }

    private static func isExistingRecordCollision(_ error: any Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .serverRecordChanged { return true }
        if ckError.code == .partialFailure, let partials = ckError.partialErrorsByItemID?.values {
            return partials.contains { ($0 as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }

    private func adoptExisting(vaultKey: [UInt8]) async throws -> RelayPrincipalIdentity {
        guard let existing = try await fetchEscrowEnvelope() else { throw Failure.escrowUnavailable }
        let adopted = try RelayPrincipalIdentity.fromEscrow(existing, vaultKey: vaultKey)
        try? KeychainStore.set(existing, account: Self.cacheAccount)
        return adopted
    }

    private func escrowRecordID() -> CKRecord.ID {
        CKRecord.ID(recordName: RelayConfig.escrowRecordName, zoneID: zone.zoneID)
    }

    private func fetchEscrowEnvelope() async throws -> Data? {
        guard let record = try? await database.record(for: escrowRecordID()) else { return nil }
        return record[ApprovalRecordMapping.Field.sealed] as? Data
    }

    /// Vault erase teardown. The REMOTE escrow record dies with the `"Vault"` zone
    /// that `CloudSyncService.eraseRemote()` deletes — no extra remote call here.
    static func clearLocalCache() {
        KeychainStore.delete(account: cacheAccount)
    }
}
