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
        case notConfigured, noEnvelope, noRecoveryKit, timedOut, cloudUnavailable

        var errorDescription: String? {
            switch self {
            case .notConfigured: return appString("iCloud sync isn’t enabled in this build.")
            case .noEnvelope:
                return appString("No synced vault found for this iCloud account. Create the Emergency Kit on your other device with iCloud Sync on, then try again.")
            case .noRecoveryKit:
                return appString("This device has no Emergency Kit to upload yet.")
            case .timedOut: return appString("No response from your other device. Generate a fresh QR code and try again.")
            case .cloudUnavailable:
                return appString("iCloud can't be reached right now. Check your connection and iCloud sign-in, then try again.")
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
        guard CloudSyncService.isConfigured, !CloudSyncService.isHostingUnitTests,
              let payload = Self.localEnvelope() else { return }
        guard UserDefaults.standard.string(forKey: Self.pushedFingerprintKey) != payload.fingerprint else { return }
        // Best-effort: retried on the next sync while the fingerprint mismatches.
        try? await upload(payload)
    }

    /// Upload the recovery envelope and REPORT the outcome.
    ///
    /// `pushRecoveryEnvelopeIfNeeded()` is deliberately silent because it trails every
    /// sync. The consent step cannot be: it tells the user their kit now restores on a
    /// new device, and that sentence is only true once this write lands. The fingerprint
    /// short-circuit is skipped here on purpose — "uploaded" has to mean a round-trip
    /// completed on this run, not that some earlier run left a matching marker.
    func pushRecoveryEnvelope() async throws {
        // `CKContainer.init` traps without the iCloud entitlement, and the test host
        // builds unsigned — never touch CloudKit from a test process.
        guard CloudSyncService.isConfigured, !CloudSyncService.isHostingUnitTests else {
            throw Failure.notConfigured
        }
        guard let payload = Self.localEnvelope() else { throw Failure.noRecoveryKit }
        try await upload(payload)
    }

    /// The local recovery blob plus its fingerprint, or nil when this device has no kit.
    private static func localEnvelope() -> (wrapped: Data, salt: Data, kdf: Data, fingerprint: String)? {
        guard let bundle = VaultKeyBundle.load(),
              let wrapped = bundle.wrappedByRecovery,
              let salt = bundle.recoverySalt,
              // The envelope must travel with the params it was WRAPPED with —
              // `recoveryKdf` when recorded; `kdf` only for pre-field bundles,
              // where the two paths always shared a profile. Pushing the current
              // password-path `kdf` after it diverges would make the Emergency
              // Kit fail to open the synced envelope on a new device.
              let kdfData = try? JSONEncoder().encode(bundle.recoveryKdf ?? bundle.kdf) else { return nil }
        return (wrapped, salt, kdfData, Data(SHA256.hash(data: wrapped)).base64EncodedString())
    }

    private func upload(_ payload: (wrapped: Data, salt: Data, kdf: Data, fingerprint: String)) async throws {
        let id = CKRecord.ID(recordName: Self.envelopeRecordName, zoneID: zone.zoneID)
        let record = CKRecord(recordType: Self.envelopeRecordType, recordID: id)
        record["wrappedByRecovery"] = payload.wrapped as CKRecordValue
        record["recoverySalt"] = payload.salt as CKRecordValue
        record["kdf"] = payload.kdf as CKRecordValue
        record["updatedAt"] = Date.now as CKRecordValue
        do {
            // Ensure the zone itself: the envelope must upload even when no
            // item sync ever succeeded (fresh install, kit just generated) —
            // saving an existing zone is a cheap server-side no-op.
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        } catch {
            throw Failure.cloudUnavailable
        }
        UserDefaults.standard.set(payload.fingerprint, forKey: Self.pushedFingerprintKey)
    }

    /// Fetch the synced recovery envelope (new-device join by Emergency Kit).
    /// Only an authoritative server "this record/zone doesn't exist" reads as
    /// `.noEnvelope` — network, auth, or throttle failures propagate as
    /// `.cloudUnavailable` instead. Collapsing every error into "no synced
    /// vault" sent users doubting a perfectly good recovery key while the
    /// device was merely offline.
    func fetchRecoveryEnvelope() async throws -> (wrapped: Data, salt: Data, kdf: KdfParams) {
        guard CloudSyncService.isConfigured else { throw Failure.notConfigured }
        let id = CKRecord.ID(recordName: Self.envelopeRecordName, zoneID: zone.zoneID)
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError
            where error.code == .unknownItem || error.code == .zoneNotFound
                || error.code == .userDeletedZone {
            throw Failure.noEnvelope
        } catch {
            throw Failure.cloudUnavailable
        }
        guard let wrapped = record["wrappedByRecovery"] as? Data,
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
