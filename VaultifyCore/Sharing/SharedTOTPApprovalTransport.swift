import CloudKit
import CryptoKit
import Foundation

/// Extension-side transport for the askEachTime **TOTP** ceremony: build and
/// sign the approval request, save it into the owner's shared zone, and poll
/// for the sealed code. The AutoFill extension carries the same iCloud
/// container as the app, so the ceremony runs where the fill session lives —
/// handing the user off to the app would destroy that session.
///
/// Deliberately parallel to `PasskeyApprovalTransport` rather than shared with
/// it: the two differ in the capability they demand, in the payload binding
/// the verifier requires (exactly one clientDataHash for a passkey slot, none
/// for TOTP), and in the payload they open. Folding them together would put
/// those three kind-specific rules behind a generic parameter, which is where
/// a fail-closed check gets weakened by accident.
///
/// Owner-key trust differs from the app path on purpose: the app pins the
/// owner's signing key in its own Keychain group after the safety-code
/// decision, which the extension cannot read. Here the response is verified
/// against the signing key carried by the grant fetched in `submitRequest` —
/// so an answer signed by anyone else is rejected, but the first-use decision
/// itself stays an app-side act.
nonisolated enum SharedTOTPApprovalTransport {
    /// Mirrors `ApprovalRecordMapping.Field.blob` (app target).
    private static let blobField = "blob"

    enum Failure: Error {
        case notConfigured
        case grantUnavailable
        case capabilityNotGranted
        case rejected
        case interrupted
        case timedOut
        case invalidResponse
    }

    struct Ticket: Sendable {
        let request: ApprovalRequest
        let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey
        let ownerSigningPubKey: Data
        let zoneID: CKRecordZone.ID
    }

    /// Fetch the live grant, check the field capability, then sign and save
    /// the request. The grant fetch doubles as the authoritative online gate
    /// (INV-11) — no grant, no request.
    static func submitRequest(zoneName: String, ownerName: String,
                              expectedGrantId: String, fieldId: String) async throws -> Ticket {
        #if !VAULTIFY_ICLOUD
        throw Failure.notConfigured
        #else
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        let database = CKContainer(identifier: ApprovalConfig.containerID).sharedCloudDatabase
        guard let grant = try? await Self.fetchGrant(database: database, zoneID: zoneID,
                                                     grantId: expectedGrantId),
              grant.id == expectedGrantId else {
            throw Failure.grantUnavailable
        }
        guard case .totp(.askEachTime)? = grant.capabilities[fieldId] else {
            throw Failure.capabilityNotGranted
        }

        let signingIdentity = try DeviceSigningIdentity.loadOrCreate()
        let deviceID = (try? DeviceHPKEIdentity.loadOrCreate().deviceKeyID.hexString.prefix(16))
            .map(String.init) ?? "extension"
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // No `payloadBinding`: the owner's verifier rejects a TOTP request that
        // carries one (the binding is passkey-only, INV-09).
        var request = ApprovalRequest(
            requestId: ApprovalConfig.opaqueName(), grantId: grant.id,
            requesterDeviceId: deviceID, itemId: grant.itemId, fieldId: fieldId,
            nonce: CryptoRandom.data(16),
            ephemeralPubKey: ephemeral.publicKey.rawRepresentation,
            createdAtUnixMs: nowMs,
            expiresAtUnixMs: nowMs + ApprovalConfig.requestTTLMs,
            requesterSigningPubKey: signingIdentity.publicKeyRaw,
            requesterSignature: Data())
        request.requesterSignature = try signingIdentity.signature(for: request.signingBody())

        let record = CKRecord(recordType: ApprovalConfig.requestRecordType,
                              recordID: CKRecord.ID(recordName: request.requestId, zoneID: zoneID))
        record[blobField] = request.encoded() as CKRecordValue
        let saved = try await database.modifyRecords(saving: [record], deleting: [])
        for (_, result) in saved.saveResults { _ = try result.get() }
        return Ticket(request: request, ephemeralPrivateKey: ephemeral,
                      ownerSigningPubKey: grant.ownerSigningPubKey, zoneID: zoneID)
        #endif
    }

    #if VAULTIFY_ICLOUD
    /// Fetch one grant by id: probes the deterministic per-grant record AND
    /// the legacy zone-wide singleton CONCURRENTLY (this gate sits on the
    /// user-visible ceremony latency budget) and prefers the per-grant result
    /// when both resolve. The caller compares the returned grant's own `id`
    /// against `expectedGrantId` — never inferred from which name it was
    /// found under (INV-FAM-01).
    private static func fetchGrant(database: CKDatabase, zoneID: CKRecordZone.ID,
                                   grantId: String) async throws -> AccessGrant {
        let perGrantID = CKRecord.ID(recordName: ApprovalConfig.grantRecordName(grantId: grantId),
                                     zoneID: zoneID)
        let legacyID = CKRecord.ID(recordName: ApprovalConfig.legacyGrantRecordName, zoneID: zoneID)
        async let perGrantRecord = Self.fetchRecordOrNil(perGrantID, database: database)
        async let legacyRecord = Self.fetchRecordOrNil(legacyID, database: database)
        let (perGrant, legacy) = await (perGrantRecord, legacyRecord)
        if let record = perGrant,
           let blob = record[blobField] as? Data,
           let grant = try? AccessGrant.decode(blob) {
            return grant
        }
        guard let record = legacy,
              let blob = record[blobField] as? Data,
              let grant = try? AccessGrant.decode(blob) else {
            throw Failure.grantUnavailable
        }
        return grant
    }

    private static func fetchRecordOrNil(_ recordID: CKRecord.ID, database: CKDatabase) async -> CKRecord? {
        try? await database.record(for: recordID)
    }
    #endif

    /// Poll for the owner's answer within the extension's budget. The opened
    /// payload is validated against the ticket and its own window before it is
    /// handed back — a malformed or already-dead code must never render as
    /// usable (ADR-7 fail-closed).
    static func awaitApproval(_ ticket: Ticket,
                              policy: SharedAccessTimingPolicy = .standard) async throws
        -> TOTPApprovalPayload {
        #if !VAULTIFY_ICLOUD
        throw Failure.notConfigured
        #else
        let database = CKContainer(identifier: ApprovalConfig.containerID).sharedCloudDatabase
        let responseID = CKRecord.ID(recordName: "rsp-" + ticket.request.requestId,
                                     zoneID: ticket.zoneID)
        let deadline = ContinuousClock.now + policy.extensionPollingBudget
        var backoff = policy.pollingBackoff.makeIterator()
        var interval = backoff.next() ?? .seconds(2)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let record = try? await database.record(for: responseID),
               let blob = record[blobField] as? Data,
               let response = try? ApprovalResponse.decode(blob) {
                guard ApprovalVerifier.verifyResponse(
                    response, expectedRequestId: ticket.request.requestId,
                    pinnedOwnerSigningKey: ticket.ownerSigningPubKey) == nil else {
                    throw Failure.invalidResponse
                }
                switch response.decision {
                case .rejected: throw Failure.rejected
                case .interrupted: throw Failure.interrupted
                case .approved: break
                }
                guard let sealed = response.sealedPayload,
                      let plaintext = try? ApprovalSeal.openResponsePayload(
                          sealed, ephemeralPrivateKey: ticket.ephemeralPrivateKey,
                          requestId: ticket.request.requestId, nonce: ticket.request.nonce),
                      let payload = try? JSONDecoder().decode(TOTPApprovalPayload.self,
                                                              from: plaintext),
                      payload.requestNonce == ticket.request.nonce,
                      payload.period > 0, !payload.code.isEmpty,
                      payload.periodEndUnixMs > payload.periodStartUnixMs,
                      payload.periodEndUnixMs > Int64(Date().timeIntervalSince1970 * 1000) else {
                    throw Failure.invalidResponse
                }
                return payload
            }
            try await Task.sleep(for: interval)
            interval = backoff.next() ?? interval
        }
        throw Failure.timedOut
        #endif
    }
}
