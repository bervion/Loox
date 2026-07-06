import CloudKit
import CryptoKit
import Foundation

/// Extension-side transport for the passkey askEachTime ceremony: build and
/// sign the wire-v2 approval request (clientDataHash binding, INV-09), save
/// it into the owner's shared zone, and poll for the sealed response.
///
/// Lives in VaultifyCore (the extension links only the core). Record shapes
/// mirror `ApprovalRecordMapping` (app target) — field names kept in sync.
nonisolated enum PasskeyApprovalTransport {
    /// Mirrors `ApprovalRecordMapping.Field.blob` / `.requestName`.
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

    /// Fetch the live grant, check the slot capability, then sign and save
    /// the request. The grant fetch doubles as the online-gate authoritative
    /// check (INV-11) — no grant, no request.
    static func submitRequest(zoneName: String, ownerName: String,
                              expectedGrantId: String, slotId: String,
                              clientDataHash: Data,
                              policy: SharedAccessTimingPolicy = .standard) async throws -> Ticket {
        #if !VAULTIFY_ICLOUD
        throw Failure.notConfigured
        #else
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        let database = CKContainer(identifier: ApprovalConfig.containerID).sharedCloudDatabase
        let grantRecordID = CKRecord.ID(recordName: ApprovalConfig.grantRecordName, zoneID: zoneID)
        guard let grantRecord = try? await database.record(for: grantRecordID),
              let blob = grantRecord[blobField] as? Data,
              let grant = try? AccessGrant.decode(blob),
              grant.id == expectedGrantId else {
            throw Failure.grantUnavailable
        }
        guard case .passkey(.askEachTime)? = grant.capabilities[slotId] else {
            throw Failure.capabilityNotGranted
        }

        let signingIdentity = try DeviceSigningIdentity.loadOrCreate()
        let deviceID = (try? DeviceHPKEIdentity.loadOrCreate().deviceKeyID.hexString.prefix(16))
            .map(String.init) ?? "extension"
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var request = ApprovalRequest(
            requestId: ApprovalConfig.opaqueName(), grantId: grant.id,
            requesterDeviceId: deviceID, itemId: grant.itemId, fieldId: slotId,
            nonce: CryptoRandom.data(16),
            ephemeralPubKey: ephemeral.publicKey.rawRepresentation,
            createdAtUnixMs: nowMs,
            expiresAtUnixMs: nowMs + ApprovalConfig.requestTTLMs,
            requesterSigningPubKey: signingIdentity.publicKeyRaw,
            requesterSignature: Data(),
            payloadBinding: clientDataHash)
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

    /// Poll for the owner's answer within the extension's budget. Every echo
    /// in the opened payload is validated against the ticket before the
    /// assertion is accepted (INV-09).
    static func awaitApproval(_ ticket: Ticket,
                              policy: SharedAccessTimingPolicy = .standard) async throws
        -> PasskeyApprovalPayload {
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
                      let payload = try? JSONDecoder().decode(PasskeyApprovalPayload.self,
                                                              from: plaintext),
                      payload.clientDataHash == ticket.request.payloadBinding,
                      payload.requestNonce == ticket.request.nonce else {
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
