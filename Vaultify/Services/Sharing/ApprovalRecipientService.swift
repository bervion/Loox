import CloudKit
import CryptoKit
import Foundation

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
    func publishProfile(identity: ParticipantIdentity, zoneID: CKRecordZone.ID,
                        nowUnixMs: Int64) async throws {
        let signingIdentity = try DeviceSigningIdentity.loadOrCreate()
        let record = ApprovalRecordMapping.participantProfileRecord(
            participantPubKey: identity.publicKeyRaw,
            deviceSigningKeys: [signingIdentity.publicKeyRaw],
            createdAtUnixMs: nowUnixMs, zoneID: zoneID)
        let saved = try await sharedDatabase.modifyRecords(saving: [record], deleting: [],
                                                           savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
    }

    /// Idempotent acceptance completion (Validation §3 ordering): identity is
    /// already escrowed by the caller; publish the profile into EVERY accepted
    /// zone (singleton record — re-publish is a harmless overwrite). Callable
    /// after accept, after crash, after onboarding — same result.
    func completeAcceptance(identity: ParticipantIdentity, nowUnixMs: Int64) async throws {
        for zoneID in try await acceptedApprovalZones() {
            try await publishProfile(identity: identity, zoneID: zoneID, nowUnixMs: nowUnixMs)
        }
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
        var values: [String: Data] = [:]
        // Stateless: current state of the shared blobs, every call.
        try await ZoneDeltaFetch.pull(database: sharedDatabase, zoneID: zoneID, cursor: nil) { record in
            guard let field = ApprovalRecordMapping.sharedField(from: record),
                  field.grantId == grant.id,
                  grant.capabilities[field.fieldId]?.isSharedValue == true else { return }
            if let plaintext = try? ApprovalSeal.openSharedField(
                field.blob, participantPrivateKey: identity.privateKey,
                grantId: grant.id, fieldId: field.fieldId) {
                values[field.fieldId] = plaintext
            }
        }
        return values
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
    func fetchResponse(requestId: String, zoneID: CKRecordZone.ID) async throws -> ApprovalResponse? {
        guard let pinnedKey = Self.pinnedOwnerKey(zoneID: zoneID) else {
            throw Failure.verifyFailed(.ownerKeyUnpinned)
        }
        var found: ApprovalResponse?
        // Stateless: a cursor here would let a poll for one request silently
        // consume (and lose) another request's response record.
        try await ZoneDeltaFetch.pull(database: sharedDatabase, zoneID: zoneID, cursor: nil) { record in
            guard record.recordType == ApprovalConfig.responseRecordType,
                  (record[ApprovalRecordMapping.Field.requestName] as? String) == requestId,
                  let response = ApprovalRecordMapping.response(from: record) else { return }
            found = response
        }
        guard let response = found else { return nil }
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
