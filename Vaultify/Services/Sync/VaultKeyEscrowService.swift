import CloudKit
import CryptoKit
import Foundation

/// CloudKit transport for the two key-provisioning paths — everything it stores
/// is ciphertext or public parameters; the Vault Key itself never appears:
///
/// - **Recovery envelope** (`VaultKeyEnvelope`, singleton record): the
///   recovery-KEK-wrapped Vault Key + its salt + Argon2 params, mirrored from the
///   local `VaultKeyBundle`. Lets a NEW device join with just the Emergency Kit
///   recovery key (no trusted device needed). Useless without that key.
/// - **Pairing hand-off** (`VaultKeyPairing` records): the HPKE-sealed Vault Key a
///   trusted device publishes for one QR-pairing session; the new device polls for
///   it, consumes it (delete-on-read), and only its in-memory ephemeral private key
///   can open it. Stale hand-offs (crashed ceremonies) expire via a TTL check.
///
/// Both live in the user's private database — access already requires their
/// signed-in iCloud account; the QR scan is what proves physical presence.
@MainActor final class VaultKeyEscrowService {
    enum Failure: Error, LocalizedError {
        case notConfigured, noEnvelope, timedOut

        var errorDescription: String? {
            switch self {
            case .notConfigured: return appString("iCloud sync isn’t enabled in this build.")
            case .noEnvelope:
                return appString("No synced vault found for this iCloud account. Create the Emergency Kit on your other device with iCloud Sync on, then try again.")
            case .timedOut: return appString("No response from your other device. Generate a fresh QR code and try again.")
            }
        }
    }

    private lazy var container = CKContainer(identifier: "iCloud.com.bervion.vaultify")
    private let zone = CKRecordZone(zoneName: "Vault")
    private var database: CKDatabase { container.privateCloudDatabase }

    private static let envelopeRecordType = "VaultKeyEnvelope"
    private static let envelopeRecordName = "vault-key-envelope"
    private static let pairingRecordType = "VaultKeyPairingHandoff"
    /// Fingerprint of the last recovery blob this device pushed (avoids a network
    /// round-trip on every sync when nothing changed).
    private static let pushedFingerprintKey = "recovery_envelope_pushed_fingerprint"
    /// Hand-offs older than this are ignored (leftovers of an abandoned ceremony).
    private static let handoffTTL: TimeInterval = 10 * 60

    /// Forget which recovery blob was pushed (vault erase) so a future vault's
    /// envelope is pushed fresh instead of being fingerprint-skipped.
    static func clearPushedFingerprint() {
        UserDefaults.standard.removeObject(forKey: pushedFingerprintKey)
    }

    // MARK: Recovery envelope (Emergency-Kit join path)

    /// Mirror the local recovery-wrapped Vault Key to CloudKit when it changed.
    /// Called after each successful sync; cheap no-op while the fingerprint matches.
    ///
    /// The envelope is a last-writer singleton: regenerating the Emergency Kit on ANY
    /// synced device makes THAT kit the one new devices join with (older printed kits
    /// still unlock their own device locally, but no longer join new ones) — matching
    /// the single-device "regenerate invalidates the old kit" semantics.
    func pushRecoveryEnvelopeIfNeeded() async {
        guard CloudSyncService.isConfigured else { return }
        guard let bundle = VaultKeyBundle.load(),
              let wrapped = bundle.wrappedByRecovery,
              let salt = bundle.recoverySalt,
              // The envelope must travel with the params it was WRAPPED with —
              // `recoveryKdf` when recorded; `kdf` only for pre-field bundles,
              // where the two paths always shared a profile. Pushing the current
              // password-path `kdf` after it diverges would make the Emergency
              // Kit fail to open the synced envelope on a new device.
              let kdfData = try? JSONEncoder().encode(bundle.recoveryKdf ?? bundle.kdf) else { return }
        let fingerprint = Data(SHA256.hash(data: wrapped)).base64EncodedString()
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.pushedFingerprintKey) != fingerprint else { return }

        let id = CKRecord.ID(recordName: Self.envelopeRecordName, zoneID: zone.zoneID)
        let record = CKRecord(recordType: Self.envelopeRecordType, recordID: id)
        record["wrappedByRecovery"] = wrapped as CKRecordValue
        record["recoverySalt"] = salt as CKRecordValue
        record["kdf"] = kdfData as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            defaults.set(fingerprint, forKey: Self.pushedFingerprintKey)
        } catch {
            // Best-effort: retried on the next sync while the fingerprint mismatches.
        }
    }

    /// Fetch the synced recovery envelope (new-device join by Emergency Kit).
    func fetchRecoveryEnvelope() async throws -> (wrapped: Data, salt: Data, kdf: KdfParams) {
        guard CloudSyncService.isConfigured else { throw Failure.notConfigured }
        let id = CKRecord.ID(recordName: Self.envelopeRecordName, zoneID: zone.zoneID)
        guard let record = try? await database.record(for: id),
              let wrapped = record["wrappedByRecovery"] as? Data,
              let salt = record["recoverySalt"] as? Data,
              let kdfData = record["kdf"] as? Data,
              let kdf = try? JSONDecoder().decode(KdfParams.self, from: kdfData)
        else { throw Failure.noEnvelope }
        return (wrapped, salt, kdf)
    }

    // MARK: Pairing hand-off (QR join path)

    private static func handoffRecordID(pairingId: String, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "pairing-\(pairingId)", zoneID: zoneID)
    }

    /// Trusted device: publish the HPKE-sealed Vault Key for one pairing session.
    func publishPairingHandoff(pairingId: String, sealedVaultKey: Data) async throws {
        guard CloudSyncService.isConfigured else { throw Failure.notConfigured }
        let record = CKRecord(recordType: Self.pairingRecordType,
                              recordID: Self.handoffRecordID(pairingId: pairingId, zoneID: zone.zoneID))
        record["sealed"] = sealedVaultKey as CKRecordValue
        record["createdAt"] = Date.now as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    /// New device: poll for the hand-off, consume it (delete-on-read), return the
    /// sealed envelope. Throws `.timedOut` when the trusted device never responds.
    func waitForPairingHandoff(pairingId: String,
                               timeout: TimeInterval = 180,
                               pollInterval: TimeInterval = 2.5) async throws -> Data {
        guard CloudSyncService.isConfigured else { throw Failure.notConfigured }
        let recordID = Self.handoffRecordID(pairingId: pairingId, zoneID: zone.zoneID)
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            try Task.checkCancellation()
            if let record = try? await database.record(for: recordID),
               let sealed = record["sealed"] as? Data,
               let createdAt = record["createdAt"] as? Date,
               Date.now.timeIntervalSince(createdAt) < Self.handoffTTL {
                // Consume: a hand-off is single-use; remove it as soon as it's read.
                _ = try? await database.modifyRecords(saving: [], deleting: [recordID])
                return sealed
            }
            try await Task.sleep(for: .seconds(pollInterval))
        }
        throw Failure.timedOut
    }
}
