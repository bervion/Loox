import CloudKit
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Recipient-side (B) transport: publish the participant profile into the
/// accepted shared zone, read the owner's grant (TOFU-pinning the owner key
/// after the fingerprint ceremony), send signed requests, and fetch verified
/// responses. Ephemeral request keys live ONLY in the caller's memory —
/// this service never persists them.
@MainActor final class ApprovalRecipientService {
    enum Failure: Error, LocalizedError {
        case noAcceptedZone
        case grantMissing
        case verifyFailed(ApprovalVerifyFailure)
        case malformedPayload
        /// v2 single-device grant that does not include THIS device (or the
        /// binding hash doesn't match our key) — Tier-0 projection, not an
        /// error toast (INV-04/10).
        case deviceNotAuthorized

        var errorDescription: String? {
            switch self {
            case .noAcceptedZone:
                return appString("Nothing has been shared with this account yet.")
            case .grantMissing:
                // Normal state while the owner hasn't confirmed the
                // fingerprint yet — the grant only exists after that.
                return appString("The owner hasn't finished setting up this share yet. Ask them to open the item and confirm the code with you.")
            case .verifyFailed(let reason):
                // The specific failed check is appended verbatim — it names a
                // kernel invariant (e.g. badGrantSignature, ownerKeyUnpinned),
                // which is exactly what a bug report needs.
                return appString("This share couldn't be verified.") + " (\(reason))"
            case .malformedPayload:
                return appString("The response couldn't be read.")
            case .deviceNotAuthorized:
                return appString("The owner limited this item to a different device.")
            }
        }
    }

    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

    // MARK: Zones

    /// Approval zones this account has accepted (shared DB, `apz-` prefix).
    func acceptedApprovalZones() async throws -> [CKRecordZone.ID] {
        try await container.sharedCloudDatabase.allRecordZones()
            .map(\.zoneID)
            .filter { $0.zoneName.hasPrefix(ApprovalConfig.zonePrefix) }
    }

    // MARK: Profile

    /// Publish B's identity material for the owner to pin (ADR-4). Called
    /// after `ParticipantEscrowService.ensureIdentity` succeeded (Validation
    /// §3 ordering: escrowed BEFORE published).
    ///
    /// MERGE-aware (P03a): the profile is a singleton per zone, but each of
    /// B's devices must appear in it — signing keys are unioned and the
    /// per-device HPKE directory is upserted onto the FETCHED record, so a
    /// republish from device 2 no longer erases device 1.
    func publishProfile(identity: ParticipantIdentity, zoneID: CKRecordZone.ID,
                        nowUnixMs: Int64) async throws {
        let signingIdentity = try DeviceSigningIdentity.loadOrCreate()
        let hpkeIdentity = try DeviceHPKEIdentity.loadOrCreate()
        let ownEntry = DeviceHPKEDirectoryEntry(
            deviceKeyID: hpkeIdentity.deviceKeyID,
            hpkePublicKey: hpkeIdentity.publicKeyRaw,
            label: Self.deviceLabel(),
            addedAtUnixMs: nowUnixMs)

        let recordID = CKRecord.ID(recordName: ApprovalConfig.participantProfileRecordName,
                                   zoneID: zoneID)
        let record: CKRecord
        var signingKeys = [signingIdentity.publicKeyRaw]
        var directory = [ownEntry]
        if let existing = try? await sharedDatabase.record(for: recordID),
           let profile = ApprovalRecordMapping.participantProfile(from: existing) {
            signingKeys = ParticipantProfileMerge.signingKeys(
                existing: profile.deviceSigningKeys, adding: signingIdentity.publicKeyRaw)
            directory = ParticipantProfileMerge.directory(
                existing: profile.deviceHPKEDirectory, upserting: ownEntry)
            record = existing
        } else {
            record = CKRecord(recordType: ApprovalConfig.participantProfileRecordType,
                              recordID: recordID)
        }
        // Rendezvous pointers ride along (repeat auto-invites, U5): the inbox
        // id B listens on, and B's OWN opaque userRecordID — the owner can't
        // learn either from an email lookup, but B can always say its own.
        ApprovalRecordMapping.applyParticipantProfile(
            to: record,
            participantPubKey: identity.publicKeyRaw,
            deviceSigningKeys: signingKeys,
            deviceHPKEDirectory: directory,
            createdAtUnixMs: nowUnixMs,
            inviteInboxID: InviteInboxService.storedOrNewInboxID(),
            inviteRecipientID: (try? await container.userRecordID())?.recordName)
        let saved = try await sharedDatabase.modifyRecords(saving: [record], deleting: [],
                                                           savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
    }

    /// Display label for the device directory (owner-facing in the P03b
    /// "new device asks for access" banner). Non-sensitive.
    private static func deviceLabel() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    /// Idempotent acceptance completion (Validation §3 ordering): identity is
    /// already escrowed by the caller; publish the profile into EVERY accepted
    /// zone (singleton record — re-publish is a harmless overwrite). Callable
    /// after accept, after crash, after onboarding — same result.
    ///
    /// Returns the number of zones a profile was published into. **Zero is not
    /// success** — it means the accepted CKShare zone has not propagated into
    /// the shared DB yet (accept just happened) and the caller MUST retry; a
    /// caller that clears its resume breadcrumb on a zero-zone return would
    /// permanently strand the owner on "accepted, waiting for their device".
    @discardableResult
    func completeAcceptance(identity: ParticipantIdentity, nowUnixMs: Int64) async throws -> Int {
        let zones = try await acceptedApprovalZones()
        for zoneID in zones {
            try await publishProfile(identity: identity, zoneID: zoneID, nowUnixMs: nowUnixMs)
        }
        return zones.count
    }

    // MARK: Owner-key pin (TOFU after the one-time fingerprint compare)

    /// Pin key includes the zone OWNER name — two different owners could
    /// otherwise collide on an (opaque but attacker-visible) zone name.
    private static func pinAccount(zoneID: CKRecordZone.ID) -> String {
        "approval_pinned_owner_key_\(zoneID.ownerName)_\(zoneID.zoneName)"
    }

    static func pinnedOwnerKey(zoneID: CKRecordZone.ID) -> Data? {
        try? KeychainStore.get(account: pinAccount(zoneID: zoneID))
    }

    /// Called by the Phase-6 fingerprint-confirm step. Pin once; a later
    /// grant with a different owner key is rejected, not re-pinned.
    static func pinOwnerKey(_ key: Data, zoneID: CKRecordZone.ID) throws {
        try KeychainStore.set(key, account: pinAccount(zoneID: zoneID))
    }

    static func clearPin(zoneID: CKRecordZone.ID) {
        KeychainStore.delete(account: pinAccount(zoneID: zoneID))
    }

    /// Leave a received share: deleting the zone from the SHARED database
    /// removes this participant's access server-side (the owner's copy is
    /// untouched); the TOFU pin is dropped with it.
    func leave(zoneID: CKRecordZone.ID) async throws {
        _ = try await sharedDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
        Self.clearPin(zoneID: zoneID)
    }

    // MARK: Grant + shared fields

    /// Fetch and verify the grant. Before the pin exists (pre-fingerprint)
    /// the grant is returned for DISPLAY/ceremony purposes only — callers
    /// must not decrypt or request against an unpinned grant.
    func fetchGrant(zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> AccessGrant {
        let id = CKRecord.ID(recordName: ApprovalConfig.grantRecordName, zoneID: zoneID)
        guard let record = try? await sharedDatabase.record(for: id),
              let grant = ApprovalRecordMapping.grant(from: record) else {
            throw Failure.grantMissing
        }
        if let failure = ApprovalVerifier.verifyGrant(
            grant, pinnedOwnerSigningKey: Self.pinnedOwnerKey(zoneID: zoneID),
            nowUnixMs: nowUnixMs) {
            throw Failure.verifyFailed(failure)
        }
        return grant
    }

    /// Decrypt all `shared` field blobs for the grant (participant key,
    /// ADR-3). Unknown/mismatched blobs are skipped, never guessed at.
    func fetchSharedFieldValues(grant: AccessGrant, identity: ParticipantIdentity,
                                zoneID: CKRecordZone.ID) async throws -> [String: Data] {
        // Decryption requires the completed fingerprint ceremony (TOFU pin) —
        // the "display only" pre-pin grant must not unlock values.
        guard Self.pinnedOwnerKey(zoneID: zoneID) == grant.ownerSigningPubKey else {
            throw Failure.verifyFailed(.ownerKeyUnpinned)
        }
        // Grant v2 with device bindings: this device must appear in the
        // signed bindings AND its live public key must match the bound hash
        // (a swapped key under the same id is rejected — INV-12 test).
        // The legacy synced participant key is NEVER consulted here (INV-04).
        var deviceIdentity: DeviceHPKEIdentity?
        if !grant.allowedDeviceKeyBindings.isEmpty {
            guard let device = try? DeviceHPKEIdentity.loadOrCreate(),
                  let binding = grant.allowedDeviceKeyBindings
                      .first(where: { $0.deviceKeyID == device.deviceKeyID }),
                  binding.hpkePublicKeyHash == device.publicKeyHash else {
                throw Failure.deviceNotAuthorized
            }
            deviceIdentity = device
        }
        var values: [String: Data] = [:]
        // Stateless: current state of the shared blobs, every call.
        try await ZoneDeltaFetch.pull(database: sharedDatabase, zoneID: zoneID, cursor: nil) { record in
            guard let field = ApprovalRecordMapping.sharedField(from: record),
                  field.grantId == grant.id,
                  grant.capabilities[field.fieldId]?.isSharedValue == true else { return }
            if let device = deviceIdentity {
                if let blob = try? PerDeviceSealedBlob.decode(field.blob),
                   let envelope = blob.envelope(forDeviceKeyID: device.deviceKeyID),
                   let plaintext = try? ApprovalSeal.openSharedFieldForDevice(
                       envelope, deviceIdentity: device,
                       grantId: grant.id, fieldId: field.fieldId) {
                    values[field.fieldId] = plaintext
                }
            } else if let plaintext = try? ApprovalSeal.openSharedField(
                field.blob, participantPrivateKey: identity.privateKey,
                grantId: grant.id, fieldId: field.fieldId) {
                values[field.fieldId] = plaintext
            }
        }
        return values
    }

    /// Decrypt the presentation metadata (title/host). nil when the owner
    /// hasn't published one (older shares) — callers show a neutral fallback.
    func fetchDisplayEnvelope(grant: AccessGrant, identity: ParticipantIdentity,
                              zoneID: CKRecordZone.ID) async -> SharedDisplayEnvelope? {
        guard Self.pinnedOwnerKey(zoneID: zoneID) == grant.ownerSigningPubKey else { return nil }
        let id = CKRecord.ID(recordName: ApprovalConfig.displayEnvelopeRecordName, zoneID: zoneID)
        guard let record = try? await sharedDatabase.record(for: id),
              let payload = ApprovalRecordMapping.displayEnvelope(from: record),
              payload.grantId == grant.id else { return nil }
        if !grant.allowedDeviceKeyBindings.isEmpty {
            // v2: Tier-1 metadata is per-device too — an unbound device gets
            // nil (generic Tier-0 title), not the real title (INV-10).
            guard let device = try? DeviceHPKEIdentity.loadOrCreate(),
                  grant.allowedDeviceKeyBindings.contains(where: {
                      $0.deviceKeyID == device.deviceKeyID
                          && $0.hpkePublicKeyHash == device.publicKeyHash
                  }),
                  let blob = try? PerDeviceSealedBlob.decode(payload.blob),
                  let envelope = blob.envelope(forDeviceKeyID: device.deviceKeyID) else {
                return nil
            }
            return try? SharedDisplayEnvelope.openForDevice(envelope, deviceIdentity: device,
                                                            grantId: grant.id)
        }
        return try? SharedDisplayEnvelope.open(payload.blob, participantIdentity: identity,
                                               grantId: grant.id)
    }

    // MARK: Request / response

    struct PendingRequest {
        let request: ApprovalRequest
        /// In-memory ONLY — dropping this key makes the response permanently
        /// unopenable (forward secrecy, ADR-3).
        let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey
    }

    /// Build, sign, and save an `askEachTime` request.
    func sendRequest(grant: AccessGrant, fieldId: String, deviceId: String,
                     zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> PendingRequest {
        // Requests are only sent against a fingerprint-confirmed owner.
        guard Self.pinnedOwnerKey(zoneID: zoneID) == grant.ownerSigningPubKey else {
            throw Failure.verifyFailed(.ownerKeyUnpinned)
        }
        let signingIdentity = try DeviceSigningIdentity.loadOrCreate()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        var request = ApprovalRequest(
            requestId: ApprovalConfig.opaqueName(), grantId: grant.id,
            requesterDeviceId: deviceId, itemId: grant.itemId, fieldId: fieldId,
            nonce: CryptoRandom.data(16),
            ephemeralPubKey: ephemeral.publicKey.rawRepresentation,
            createdAtUnixMs: nowUnixMs,
            expiresAtUnixMs: nowUnixMs + ApprovalConfig.requestTTLMs,
            requesterSigningPubKey: signingIdentity.publicKeyRaw,
            requesterSignature: Data())
        request.requesterSignature = try signingIdentity.signature(for: request.signingBody())
        let record = ApprovalRecordMapping.requestRecord(request, zoneID: zoneID)
        let saved = try await sharedDatabase.modifyRecords(saving: [record], deleting: [])
        for (_, result) in saved.saveResults { _ = try result.get() }
        return PendingRequest(request: request, ephemeralPrivateKey: ephemeral)
    }

    /// Look for the owner's answer to `requestId`; verify it (kernel-owned,
    /// pinned owner key) before returning. nil = not answered yet.
    /// Direct record lookup — the response name is deterministic
    /// ("rsp-" + requestId), so no zone scan is needed per poll tick.
    func fetchResponse(requestId: String, zoneID: CKRecordZone.ID) async throws -> ApprovalResponse? {
        guard let pinnedKey = Self.pinnedOwnerKey(zoneID: zoneID) else {
            throw Failure.verifyFailed(.ownerKeyUnpinned)
        }
        let recordID = ApprovalRecordMapping.responseRecordID(requestId: requestId, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await sharedDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil // not answered yet
        }
        guard let response = ApprovalRecordMapping.response(from: record) else { return nil }
        if let failure = ApprovalVerifier.verifyResponse(response, expectedRequestId: requestId,
                                                         pinnedOwnerSigningKey: pinnedKey) {
            throw Failure.verifyFailed(failure)
        }
        return response
    }

    /// Open an approved response's sealed payload with the request's
    /// ephemeral private key and sanity-check the window context (ADR-7:
    /// malformed payloads fail closed — they must never render as fresh).
    nonisolated static func openApprovedPayload(_ response: ApprovalResponse,
                                                pending: PendingRequest) throws -> TOTPApprovalPayload {
        guard let sealed = response.sealedPayload else { throw Failure.malformedPayload }
        let plaintext = try ApprovalSeal.openResponsePayload(
            sealed, ephemeralPrivateKey: pending.ephemeralPrivateKey,
            requestId: pending.request.requestId, nonce: pending.request.nonce)
        let payload = try JSONDecoder().decode(TOTPApprovalPayload.self, from: plaintext)
        guard payload.requestNonce == pending.request.nonce,
              payload.period > 0, !payload.code.isEmpty,
              payload.periodEndUnixMs > payload.periodStartUnixMs else {
            throw Failure.malformedPayload
        }
        return payload
    }
}
