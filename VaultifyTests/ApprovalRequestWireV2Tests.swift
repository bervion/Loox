import XCTest
@testable import Vaultify

/// Approval request wire v2 (passkey askEachTime): the clientDataHash binding
/// forces version byte 2; TOTP requests stay bit-identical to v1. Mirrors the
/// grant-v2 strictness: version/feature agreement both ways, exact 32-byte
/// binding, trailing bytes rejected.
final class ApprovalRequestWireV2Tests: XCTestCase {

    private func makeRequest(binding: Data?) -> ApprovalRequest {
        ApprovalRequest(requestId: "req-1", grantId: "g-1",
                        requesterDeviceId: "dev-1", itemId: "item-1",
                        fieldId: binding == nil ? "field-1" : "passkey::aa",
                        nonce: Data(repeating: 5, count: 16),
                        ephemeralPubKey: Data(repeating: 6, count: 32),
                        createdAtUnixMs: 1_000, expiresAtUnixMs: 61_000,
                        requesterSigningPubKey: Data(repeating: 7, count: 65),
                        requesterSignature: Data([9, 9]),
                        payloadBinding: binding)
    }

    func testTOTPRequestStaysOnWireV1() throws {
        let request = makeRequest(binding: nil)
        XCTAssertEqual(request.signingBody().first, ApprovalWire.version)
        XCTAssertEqual(try ApprovalRequest.decode(request.encoded()), request)
    }

    func testPasskeyRequestRoundTripsOnWireV2() throws {
        let request = makeRequest(binding: Data(repeating: 3, count: 32))
        XCTAssertEqual(request.signingBody().first, ApprovalWire.versionV2)
        XCTAssertEqual(try ApprovalRequest.decode(request.encoded()), request)
    }

    func testBindingMustBeExactly32Bytes() {
        let short = makeRequest(binding: Data(repeating: 3, count: 31))
        XCTAssertThrowsError(try ApprovalRequest.decode(short.encoded()))
    }

    func testVersionByteFlipRejectedOrChangesSignedBytes() {
        // Relabelling a v2 request as v1 shifts the layout — decode must not
        // silently produce a different (unsigned-over) request.
        let v2 = makeRequest(binding: Data(repeating: 3, count: 32))
        var relabelled = v2.encoded()
        relabelled[relabelled.startIndex] = ApprovalWire.version
        if let decoded = try? ApprovalRequest.decode(relabelled) {
            // If it happens to parse, the signed bytes can never match the
            // original signature domain (version byte differs).
            XCTAssertNotEqual(decoded.signingBody(), v2.signingBody())
        }
    }

    func testTrailingBytesRejected() {
        let request = makeRequest(binding: Data(repeating: 3, count: 32))
        XCTAssertThrowsError(try ApprovalRequest.decode(request.encoded() + Data([0])))
    }

    func testVerifierRequiresBindingAgreementWithCapability() async {
        // Passkey capability + missing binding → malformed; TOTP capability +
        // unexpected binding → malformed (INV-09 agreement check, step 8).
        let owner = DeviceSigningIdentity.ephemeral()
        let requester = DeviceSigningIdentity.ephemeral()
        let slot = "passkey::aa"
        var grant = AccessGrant(id: "g-1", itemId: "item-1", recipientId: "r",
                                participantPubKey: Data(repeating: 1, count: 32),
                                pinnedDeviceSigningKeys: [requester.publicKeyRaw],
                                capabilities: [slot: .passkey(.askEachTime)],
                                epoch: 1, createdAtUnixMs: 0, expiresAtUnixMs: nil,
                                ownerSigningPubKey: owner.publicKeyRaw,
                                ownerSignature: Data())
        grant.ownerSignature = try! owner.signature(for: grant.signingBody())

        var request = ApprovalRequest(
            requestId: "req-1", grantId: "g-1", requesterDeviceId: "dev",
            itemId: "item-1", fieldId: slot,
            nonce: Data(repeating: 5, count: 16),
            ephemeralPubKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
            createdAtUnixMs: 1_000, expiresAtUnixMs: 61_000,
            requesterSigningPubKey: requester.publicKeyRaw,
            requesterSignature: Data(), payloadBinding: nil) // MISSING binding
        request.requesterSignature = try! requester.signature(for: request.signingBody())

        let failure = await ApprovalVerifier.verifyRequest(
            request, grant: grant, trustedOwnerSigningKeys: [owner.publicKeyRaw],
            currentEpoch: 1, nowUnixMs: 2_000, nonceStore: PreviewNonceStore())
        XCTAssertEqual(failure, .malformedRequest)
    }
}

import CryptoKit
