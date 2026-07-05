import CryptoKit
import XCTest
@testable import Vaultify

/// V1.1 Phase-4 invite-envelope kernel invariants: seal/sign round-trip,
/// inbox binding, tamper rejection, signature-key consistency, and the U9
/// lifetime policy — all fail-closed.
final class InviteEnvelopeTests: XCTestCase {

    // Fixed instant: 2026-07-05 13:00:00Z (ADR-7 — tests never touch Calendar).
    private let nowMs: Int64 = 1_783_256_400_000

    private func makeEnvelope(signer: DeviceSigningIdentity,
                              lifetimeMs: Int64 = 48 * 3_600_000) -> InviteEnvelope {
        InviteEnvelope(
            inviteID: "inv-0123456789abcdef",
            shareURL: "https://www.icloud.com/share/000-aaa",
            ownerParticipantID: "owner-opaque-id",
            recipientParticipantID: "recipient-opaque-id",
            senderSigningPubKey: signer.publicKeyRaw,
            createdAtUnixMs: nowMs,
            expiresAtUnixMs: nowMs + lifetimeMs)
    }

    func testSealOpenRoundTrip() throws {
        let signer = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()
        let envelope = makeEnvelope(signer: signer)

        let blob = try envelope.sealedAndSigned(
            toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
            inboxID: "inbox-a", signer: signer)
        let opened = try InviteEnvelope.open(blob, recipientPrivateKey: inboxKey,
                                             inboxID: "inbox-a", nowUnixMs: nowMs + 1000)
        XCTAssertEqual(opened, envelope)
    }

    func testWrongRecipientKeyFails() throws {
        let signer = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()
        let blob = try makeEnvelope(signer: signer).sealedAndSigned(
            toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
            inboxID: "inbox-a", signer: signer)

        XCTAssertThrowsError(try InviteEnvelope.open(
            blob, recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey(),
            inboxID: "inbox-a", nowUnixMs: nowMs)) { error in
            XCTAssertEqual(error as? InviteEnvelope.Failure, .malformed)
        }
    }

    func testWrongInboxBindingFails() throws {
        // Same private key, different inboxID — a drop copied between inboxes
        // (or replayed across an inbox rotation) must not open.
        let signer = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()
        let blob = try makeEnvelope(signer: signer).sealedAndSigned(
            toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
            inboxID: "inbox-a", signer: signer)

        XCTAssertThrowsError(try InviteEnvelope.open(
            blob, recipientPrivateKey: inboxKey, inboxID: "inbox-b", nowUnixMs: nowMs)) { error in
            XCTAssertEqual(error as? InviteEnvelope.Failure, .malformed)
        }
    }

    func testTamperedCiphertextFails() throws {
        let signer = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()
        var blob = try makeEnvelope(signer: signer).sealedAndSigned(
            toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
            inboxID: "inbox-a", signer: signer)
        blob[blob.count - 1] ^= 0xFF

        XCTAssertThrowsError(try InviteEnvelope.open(
            blob, recipientPrivateKey: inboxKey, inboxID: "inbox-a", nowUnixMs: nowMs)) { error in
            XCTAssertEqual(error as? InviteEnvelope.Failure, .malformed)
        }
    }

    func testMismatchedClaimedSignerKeyFails() throws {
        // Envelope CLAIMS one sender key but is signed by another — the
        // self-consistency check must reject it.
        let actualSigner = DeviceSigningIdentity.ephemeral()
        let claimedSigner = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()
        var envelope = makeEnvelope(signer: actualSigner)
        envelope.senderSigningPubKey = claimedSigner.publicKeyRaw

        let blob = try envelope.sealedAndSigned(
            toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
            inboxID: "inbox-a", signer: actualSigner)

        XCTAssertThrowsError(try InviteEnvelope.open(
            blob, recipientPrivateKey: inboxKey, inboxID: "inbox-a", nowUnixMs: nowMs)) { error in
            XCTAssertEqual(error as? InviteEnvelope.Failure, .badSignature)
        }
    }

    func testExpiredInviteFails() throws {
        let signer = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()
        let lifetime: Int64 = 24 * 3_600_000
        let blob = try makeEnvelope(signer: signer, lifetimeMs: lifetime).sealedAndSigned(
            toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
            inboxID: "inbox-a", signer: signer)

        XCTAssertThrowsError(try InviteEnvelope.open(
            blob, recipientPrivateKey: inboxKey, inboxID: "inbox-a",
            nowUnixMs: nowMs + lifetime)) { error in
            XCTAssertEqual(error as? InviteEnvelope.Failure, .expired)
        }
    }

    func testLifetimePolicyEnforcedAtMintAndOpen() throws {
        let signer = DeviceSigningIdentity.ephemeral()
        let inboxKey = Curve25519.KeyAgreement.PrivateKey()

        // Too short (< 24h) and too long (> 7d) both refuse to mint (U9).
        for lifetime: Int64 in [3_600_000, 8 * 24 * 3_600_000] {
            XCTAssertThrowsError(try makeEnvelope(signer: signer, lifetimeMs: lifetime)
                .sealedAndSigned(toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
                                 inboxID: "inbox-a", signer: signer)) { error in
                XCTAssertEqual(error as? InviteEnvelope.Failure, .invalidLifetime)
            }
        }
        // Boundary values mint fine.
        for lifetime in [InviteEnvelope.minLifetimeMs, InviteEnvelope.maxLifetimeMs] {
            XCTAssertNoThrow(try makeEnvelope(signer: signer, lifetimeMs: lifetime)
                .sealedAndSigned(toRecipientPubKey: inboxKey.publicKey.rawRepresentation,
                                 inboxID: "inbox-a", signer: signer))
        }
    }
}
