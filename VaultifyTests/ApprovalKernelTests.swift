import CryptoKit
import XCTest
@testable import Vaultify

/// Phase-2 control-plane kernel invariants: canonical round-trip, pinned-key
/// verification, fail-closed capability lookup, replay, the ADR-3 two-recipient
/// seal contract, and the ADR-7 timezone-free window math.
final class ApprovalKernelTests: XCTestCase {

    // Fixed instant: 2026-07-05 13:00:00Z (same instant in VN/US — ADR-7).
    private let nowMs: Int64 = 1_783_256_400_000

    // MARK: Helpers

    private final class MemoryNonceStore: ApprovalNonceStore, @unchecked Sendable {
        private var consumed: Set<Data> = []
        var failNext = false
        struct Unavailable: Error {}
        func consume(nonce: Data, expiresAtUnixMs: Int64) async throws -> Bool {
            if failNext { throw Unavailable() }
            return consumed.insert(nonce).inserted
        }
    }

    private func makeGrant(owner: DeviceSigningIdentity,
                           requesterKey: Data,
                           participant: ParticipantIdentity,
                           capabilities: [String: FieldCapability] = ["totp-1": .totp(.askEachTime)],
                           epoch: UInt32 = 1,
                           expiresAtUnixMs: Int64? = nil) throws -> AccessGrant {
        var grant = AccessGrant(
            id: "grant-1", itemId: "item-1", recipientId: "rcpt-opaque",
            participantPubKey: participant.publicKeyRaw,
            pinnedDeviceSigningKeys: [requesterKey],
            capabilities: capabilities, epoch: epoch,
            createdAtUnixMs: nowMs, expiresAtUnixMs: expiresAtUnixMs,
            ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        grant.ownerSignature = try owner.signature(for: grant.signingBody())
        return grant
    }

    private func makeRequest(requester: DeviceSigningIdentity,
                             ephemeral: Curve25519.KeyAgreement.PrivateKey,
                             fieldId: String = "totp-1",
                             nonce: Data = Data((0..<16).map { _ in UInt8.random(in: 0...255) })) throws -> ApprovalRequest {
        var request = ApprovalRequest(
            requestId: "req-1", grantId: "grant-1", requesterDeviceId: "dev-b1",
            itemId: "item-1", fieldId: fieldId, nonce: nonce,
            ephemeralPubKey: ephemeral.publicKey.rawRepresentation,
            createdAtUnixMs: nowMs, expiresAtUnixMs: nowMs + 120_000,
            requesterSigningPubKey: requester.publicKeyRaw, requesterSignature: Data())
        request.requesterSignature = try requester.signature(for: request.signingBody())
        return request
    }

    // MARK: Canonical round-trip

    func testCanonicalRoundTripPreservesSignatures() throws {
        let owner = DeviceSigningIdentity.ephemeral()
        let requester = DeviceSigningIdentity.ephemeral()
        let participant = ParticipantIdentity.generate()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        let grant = try makeGrant(owner: owner, requesterKey: requester.publicKeyRaw,
                                  participant: participant, expiresAtUnixMs: nowMs + 86_400_000)
        let decodedGrant = try AccessGrant.decode(grant.encoded())
        XCTAssertEqual(decodedGrant, grant)
        XCTAssertTrue(DeviceSigningIdentity.verify(decodedGrant.signingBody(),
                                                   signature: decodedGrant.ownerSignature,
                                                   publicKeyRaw: owner.publicKeyRaw))

        let request = try makeRequest(requester: requester, ephemeral: ephemeral)
        XCTAssertEqual(try ApprovalRequest.decode(request.encoded()), request)

        var response = ApprovalResponse(requestId: "req-1", decision: .approved,
                                        sealedPayload: Data([9, 9, 9]), respondedAtUnixMs: nowMs,
                                        ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        response.ownerSignature = try owner.signature(for: response.signingBody())
        XCTAssertEqual(try ApprovalResponse.decode(response.encoded()), response)
    }

    func testDecodeRejectsWrongTypeAndVersion() throws {
        let owner = DeviceSigningIdentity.ephemeral()
        let grant = try makeGrant(owner: owner, requesterKey: Data([1]),
                                  participant: .generate())
        XCTAssertThrowsError(try ApprovalRequest.decode(grant.encoded()))
        var corrupted = grant.encoded()
        corrupted[corrupted.startIndex] = 99 // unknown version byte
        XCTAssertThrowsError(try AccessGrant.decode(corrupted))
    }

    // MARK: Verifier

    func testVerifyRequestHappyPathThenReplayRejected() async throws {
        let owner = DeviceSigningIdentity.ephemeral()
        let requester = DeviceSigningIdentity.ephemeral()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let grant = try makeGrant(owner: owner, requesterKey: requester.publicKeyRaw,
                                  participant: .generate())
        let request = try makeRequest(requester: requester, ephemeral: ephemeral)
        let store = MemoryNonceStore()

        let first = await ApprovalVerifier.verifyRequest(request, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                         nowUnixMs: nowMs, nonceStore: store)
        XCTAssertNil(first)
        let replay = await ApprovalVerifier.verifyRequest(request, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                          nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(replay, .replayedNonce)
    }

    func testVerifyRejectsUnpinnedKeyTamperEpochExpiryAndUnknownField() async throws {
        let owner = DeviceSigningIdentity.ephemeral()
        let requester = DeviceSigningIdentity.ephemeral()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let grant = try makeGrant(owner: owner, requesterKey: requester.publicKeyRaw,
                                  participant: .generate())
        let store = MemoryNonceStore()

        // Unpinned requester key.
        let intruder = DeviceSigningIdentity.ephemeral()
        let forged = try makeRequest(requester: intruder, ephemeral: ephemeral)
        var failure = await ApprovalVerifier.verifyRequest(forged, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                           nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .requesterKeyUnpinned)

        // Tamper after signing → bad signature.
        var tampered = try makeRequest(requester: requester, ephemeral: ephemeral)
        tampered.expiresAtUnixMs += 1
        failure = await ApprovalVerifier.verifyRequest(tampered, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .badRequestSignature)

        // Stale epoch (revoked).
        let request = try makeRequest(requester: requester, ephemeral: ephemeral)
        failure = await ApprovalVerifier.verifyRequest(request, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 2,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .staleEpoch)

        // Expired request.
        failure = await ApprovalVerifier.verifyRequest(request, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                       nowUnixMs: nowMs + 121_000, nonceStore: store)
        XCTAssertEqual(failure, .requestExpired)

        // Unknown fieldId fails closed.
        let unknownField = try makeRequest(requester: requester, ephemeral: ephemeral,
                                           fieldId: "field-not-in-grant")
        failure = await ApprovalVerifier.verifyRequest(unknownField, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .unknownField)

        // Shared-value field cannot answer an askEachTime request.
        let sharedOnly = try makeGrant(owner: owner, requesterKey: requester.publicKeyRaw,
                                       participant: .generate(),
                                       capabilities: ["totp-1": .value(.shared)])
        failure = await ApprovalVerifier.verifyRequest(request, grant: sharedOnly,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .capabilityNotGranted)

        // Neither can a code-only TOTP field: the recipient makes its own codes.
        let codeOnly = try makeGrant(owner: owner, requesterKey: requester.publicKeyRaw,
                                     participant: .generate(),
                                     capabilities: ["totp-1": .totp(.alwaysShowCode)])
        failure = await ApprovalVerifier.verifyRequest(request, grant: codeOnly,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .capabilityNotGranted)

        // Nonce authority unreachable → fail closed, not approve.
        store.failNext = true
        failure = await ApprovalVerifier.verifyRequest(request, grant: grant,
                                                         trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                         currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .nonceAuthorityUnavailable)
    }

    func testVerifyGrantRejectsChangedOwnerKeyAfterPin() throws {
        let owner = DeviceSigningIdentity.ephemeral()
        let otherOwner = DeviceSigningIdentity.ephemeral()
        let grant = try makeGrant(owner: owner, requesterKey: Data([1]), participant: .generate())
        XCTAssertNil(ApprovalVerifier.verifyGrant(grant, pinnedOwnerSigningKey: owner.publicKeyRaw,
                                                  nowUnixMs: nowMs))
        XCTAssertEqual(ApprovalVerifier.verifyGrant(grant,
                                                    pinnedOwnerSigningKey: otherOwner.publicKeyRaw,
                                                    nowUnixMs: nowMs),
                       .ownerKeyUnpinned)
    }

    func testVerifyRejectsUntrustedGrantSignerAndLifetimeAndMalformedShape() async throws {
        let owner = DeviceSigningIdentity.ephemeral()
        let requester = DeviceSigningIdentity.ephemeral()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let grant = try makeGrant(owner: owner, requesterKey: requester.publicKeyRaw,
                                  participant: .generate())
        let store = MemoryNonceStore()

        // Grant signed by a key NOT in the owner's trust root → rejected even
        // though internally consistent (no storage-ACL trust).
        let request = try makeRequest(requester: requester, ephemeral: ephemeral)
        let rogue = DeviceSigningIdentity.ephemeral()
        var failure = await ApprovalVerifier.verifyRequest(request, grant: grant,
                                                           trustedOwnerSigningKeys: [rogue.publicKeyRaw],
                                                           currentEpoch: 1,
                                                           nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .ownerKeyUnpinned)

        // B-signed lifetime beyond the kernel clamp.
        var longLived = try makeRequest(requester: requester, ephemeral: ephemeral)
        longLived.expiresAtUnixMs = nowMs + 86_400_000 // 1 day
        longLived.requesterSignature = Data() // re-sign the mutated body
        var resigned = longLived
        resigned.requesterSignature = try requester.signature(for: longLived.signingBody())
        failure = await ApprovalVerifier.verifyRequest(resigned, grant: grant,
                                                       trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                       currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .requestLifetimeTooLong)

        // Short nonce → malformed BEFORE the ceremony.
        let shortNonce = try makeRequest(requester: requester, ephemeral: ephemeral,
                                         nonce: Data([1, 2, 3]))
        failure = await ApprovalVerifier.verifyRequest(shortNonce, grant: grant,
                                                       trustedOwnerSigningKeys: [owner.publicKeyRaw],
                                                       currentEpoch: 1,
                                                       nowUnixMs: nowMs, nonceStore: store)
        XCTAssertEqual(failure, .malformedRequest)
    }

    func testMultiKeyGrantRoundTripEqualityRegardlessOfInputOrder() throws {
        let owner = DeviceSigningIdentity.ephemeral()
        // Deliberately unsorted pinned-key input.
        let keyA = Data([0xFF, 0x01]); let keyB = Data([0x00, 0x02]); let keyC = Data([0x7F])
        var grant = AccessGrant(
            id: "grant-2", itemId: "item-1", recipientId: "rcpt",
            participantPubKey: Data([1]), pinnedDeviceSigningKeys: [keyA, keyB, keyC],
            capabilities: ["totp-1": .totp(.askEachTime)], epoch: 1,
            createdAtUnixMs: nowMs, expiresAtUnixMs: nil,
            ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        grant.ownerSignature = try owner.signature(for: grant.signingBody())
        let decoded = try AccessGrant.decode(grant.encoded())
        XCTAssertEqual(decoded, grant) // normalized order == wire order
        XCTAssertTrue(DeviceSigningIdentity.verify(decoded.signingBody(),
                                                   signature: decoded.ownerSignature,
                                                   publicKeyRaw: owner.publicKeyRaw))
    }

    func testVerifyResponseBindingPinAndPayloadConsistency() throws {
        let owner = DeviceSigningIdentity.ephemeral()
        var approved = ApprovalResponse(requestId: "req-1", decision: .approved,
                                        sealedPayload: Data([1]), respondedAtUnixMs: nowMs,
                                        ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        approved.ownerSignature = try owner.signature(for: approved.signingBody())
        XCTAssertNil(ApprovalVerifier.verifyResponse(approved, expectedRequestId: "req-1",
                                                     pinnedOwnerSigningKey: owner.publicKeyRaw))
        // Wrong request binding.
        XCTAssertEqual(ApprovalVerifier.verifyResponse(approved, expectedRequestId: "req-9",
                                                       pinnedOwnerSigningKey: owner.publicKeyRaw),
                       .responseMismatch)
        // Unpinned owner key.
        let other = DeviceSigningIdentity.ephemeral()
        XCTAssertEqual(ApprovalVerifier.verifyResponse(approved, expectedRequestId: "req-1",
                                                       pinnedOwnerSigningKey: other.publicKeyRaw),
                       .ownerKeyUnpinned)
        // Approved without payload is malformed.
        var empty = ApprovalResponse(requestId: "req-1", decision: .approved,
                                     sealedPayload: nil, respondedAtUnixMs: nowMs,
                                     ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        empty.ownerSignature = try owner.signature(for: empty.signingBody())
        XCTAssertEqual(ApprovalVerifier.verifyResponse(empty, expectedRequestId: "req-1",
                                                       pinnedOwnerSigningKey: owner.publicKeyRaw),
                       .malformedResponse)
        // Reject carrying a payload is malformed.
        var rejectWithPayload = ApprovalResponse(requestId: "req-1", decision: .rejected,
                                                 sealedPayload: Data([2]), respondedAtUnixMs: nowMs,
                                                 ownerSigningPubKey: owner.publicKeyRaw,
                                                 ownerSignature: Data())
        rejectWithPayload.ownerSignature = try owner.signature(for: rejectWithPayload.signingBody())
        XCTAssertEqual(ApprovalVerifier.verifyResponse(rejectWithPayload, expectedRequestId: "req-1",
                                                       pinnedOwnerSigningKey: owner.publicKeyRaw),
                       .malformedResponse)
        // Tampered signature.
        var tampered = approved
        tampered.respondedAtUnixMs += 1
        XCTAssertEqual(ApprovalVerifier.verifyResponse(tampered, expectedRequestId: "req-1",
                                                       pinnedOwnerSigningKey: owner.publicKeyRaw),
                       .badResponseSignature)
    }

    func testTOTPWindowFailsClosedOnZeroPeriod() {
        XCTAssertEqual(TOTPWindow.counter(atUnixMs: nowMs, period: 0), 0)
        XCTAssertEqual(TOTPWindow.remainingMs(atUnixMs: nowMs, period: 0), 0)
        XCTAssertFalse(TOTPIssuancePolicy.v1.canIssueNow(atUnixMs: nowMs, period: 0))
    }

    // MARK: ADR-3 seal contract

    func testResponseSealsToEphemeralAndCrossOpenFails() throws {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let participant = ParticipantIdentity.generate()
        let nonce = Data([1, 2, 3, 4])
        let payload = Data("code:483921".utf8)

        let envelope = try ApprovalSeal.sealResponsePayload(
            payload, toEphemeralPubKey: ephemeral.publicKey.rawRepresentation,
            requestId: "req-1", nonce: nonce)
        XCTAssertEqual(try ApprovalSeal.openResponsePayload(envelope, ephemeralPrivateKey: ephemeral,
                                                            requestId: "req-1", nonce: nonce), payload)
        // Wrong private key (participant ≠ ephemeral) → fails (ADR-3 enforced).
        XCTAssertThrowsError(try ApprovalSeal.openResponsePayload(
            envelope, ephemeralPrivateKey: participant.privateKey, requestId: "req-1", nonce: nonce))
        // Wrong info binding (different request) → fails.
        XCTAssertThrowsError(try ApprovalSeal.openResponsePayload(
            envelope, ephemeralPrivateKey: ephemeral, requestId: "req-2", nonce: nonce))
    }

    func testSharedFieldSealsToParticipantKey() throws {
        let participant = ParticipantIdentity.generate()
        let other = ParticipantIdentity.generate()
        let value = Data("hunter2".utf8)
        let blob = try ApprovalSeal.sealSharedField(value, toParticipantPubKey: participant.publicKeyRaw,
                                                    grantId: "grant-1", fieldId: "pw-1")
        XCTAssertEqual(try ApprovalSeal.openSharedField(blob, participantPrivateKey: participant.privateKey,
                                                        grantId: "grant-1", fieldId: "pw-1"), value)
        XCTAssertThrowsError(try ApprovalSeal.openSharedField(
            blob, participantPrivateKey: other.privateKey, grantId: "grant-1", fieldId: "pw-1"))
        XCTAssertThrowsError(try ApprovalSeal.openSharedField(
            blob, participantPrivateKey: participant.privateKey, grantId: "grant-1", fieldId: "pw-2"))
    }

    // MARK: Fingerprint

    func testTrustFingerprintDeterministicAndKeySensitive() {
        let owner = DeviceSigningIdentity.ephemeral()
        let participant = ParticipantIdentity.generate()
        let a = TrustFingerprint.code(ownerSigningPubKey: owner.publicKeyRaw,
                                      participantPubKey: participant.publicKeyRaw)
        let b = TrustFingerprint.code(ownerSigningPubKey: owner.publicKeyRaw,
                                      participantPubKey: participant.publicKeyRaw)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.range(of: #"^\d{5}-\d{5}-\d{5}$"#, options: .regularExpression) != nil)
        let other = DeviceSigningIdentity.ephemeral()
        XCTAssertNotEqual(a, TrustFingerprint.code(ownerSigningPubKey: other.publicKeyRaw,
                                                   participantPubKey: participant.publicKeyRaw))
    }

    // MARK: ADR-7 window math (timezone-free by construction)

    func testTOTPWindowMathUsesAbsoluteUnixTimeOnly() {
        // 1_783_256_400s = 13:00:00Z = 20:00 VN = 09:00 New York — same counter.
        XCTAssertEqual(TOTPWindow.counter(atUnixMs: nowMs, period: 30), 59_441_880)
        XCTAssertEqual(TOTPWindow.remainingMs(atUnixMs: nowMs, period: 30), 30_000)
        XCTAssertEqual(TOTPWindow.remainingMs(atUnixMs: nowMs + 27_500, period: 30), 2_500)
        XCTAssertEqual(TOTPWindow.periodEndUnixMs(atUnixMs: nowMs + 29_999, period: 30),
                       nowMs + 30_000)

        let policy = TOTPIssuancePolicy.v1
        XCTAssertTrue(policy.canIssueNow(atUnixMs: nowMs, period: 30))           // 30s left
        XCTAssertTrue(policy.canIssueNow(atUnixMs: nowMs + 12_000, period: 30))  // 18s left (boundary)
        XCTAssertFalse(policy.canIssueNow(atUnixMs: nowMs + 12_001, period: 30)) // 17.999s left
        XCTAssertFalse(policy.canIssueNow(atUnixMs: nowMs + 28_000, period: 30)) // 2s left → wait
    }

    // MARK: Participant escrow

    func testParticipantEscrowRoundTripAndWrongKeyFails() throws {
        let identity = ParticipantIdentity.generate()
        let vaultKey = [UInt8](repeating: 0x11, count: 32)
        let sealed = try identity.escrowSealed(vaultKey: vaultKey)
        let restored = try ParticipantIdentity.fromEscrow(sealed, vaultKey: vaultKey)
        XCTAssertEqual(restored.publicKeyRaw, identity.publicKeyRaw)
        XCTAssertThrowsError(try ParticipantIdentity.fromEscrow(
            sealed, vaultKey: [UInt8](repeating: 0x22, count: 32)))
    }
}
