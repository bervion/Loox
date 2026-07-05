import CryptoKit
import Foundation

/// The encrypted, signed, expiring invite that rides the public-db rendezvous
/// (U5). The public record exposes only opaque ids, ciphertext, and coarse
/// timing; everything meaningful — the CKShare URL (an invitation capability,
/// U4), the participant bindings, the sender key — lives in here, sealed to
/// the recipient's inbox key and signed by the sender's device signing key.
///
/// Trust semantics (U10): opening an envelope is INVITE_DISCOVERED only.
/// It does not verify the sender (TOFU/activation happens in the existing
/// pairing ceremony) and it does not grant anything — the recipient still
/// walks the real CKShare accept + grant path. Replay/dedup by `inviteID`
/// is the reconciler's job (U6); expiry is enforced HERE, fail-closed.
nonisolated struct InviteEnvelope: Sendable, Equatable {
    /// Random opaque id — the reconciler's dedup/replay key (U6).
    var inviteID: String
    /// The original CKShare URL. Resolution MUST follow the CloudKit
    /// contract (U7): URL → CKFetchShareMetadataOperation → validate → accept.
    var shareURL: String
    /// Opaque CloudKit participant bindings — the acceptor cross-checks the
    /// fetched share metadata actually matches who this invite claims (U7).
    var ownerParticipantID: String
    var recipientParticipantID: String
    /// The sender's claimed P256 signing key; the signature must verify
    /// against THIS key, making the blob self-consistent. Whether the key is
    /// ultimately trusted is the pairing ceremony's decision, not ours.
    var senderSigningPubKey: Data
    var createdAtUnixMs: Int64
    var expiresAtUnixMs: Int64

    enum Failure: Error, Equatable {
        case malformed, unknownVersion, badSignature, expired, invalidLifetime
    }

    private static let version: UInt8 = 1
    /// U9: an invite is a bootstrap artifact, 24h–7d. Anything claiming a
    /// longer life is rejected outright — a forged "eternal invite" must not
    /// sit dormant in an inbox.
    static let minLifetimeMs: Int64 = 24 * 3_600_000
    static let maxLifetimeMs: Int64 = 7 * 24 * 3_600_000

    // MARK: Canonical bytes

    /// Domain-separated signing body — the exact bytes the signature covers.
    func signingBody() -> Data {
        var w = CanonicalWriter()
        w.string("Loox invite envelope v1")
        w.string(inviteID)
        w.string(shareURL)
        w.string(ownerParticipantID)
        w.string(recipientParticipantID)
        w.blob(senderSigningPubKey)
        w.i64(createdAtUnixMs)
        w.i64(expiresAtUnixMs)
        return w.data
    }

    private func encoded(signature: Data) -> Data {
        var w = CanonicalWriter()
        w.byte(Self.version)
        w.string(inviteID)
        w.string(shareURL)
        w.string(ownerParticipantID)
        w.string(recipientParticipantID)
        w.blob(senderSigningPubKey)
        w.i64(createdAtUnixMs)
        w.i64(expiresAtUnixMs)
        w.blob(signature)
        return w.data
    }

    private static func decode(_ data: Data) throws -> (envelope: InviteEnvelope, signature: Data) {
        var r = CanonicalReader(data)
        do {
            guard try r.byte() == version else { throw Failure.unknownVersion }
            let envelope = InviteEnvelope(
                inviteID: try r.string(),
                shareURL: try r.string(),
                ownerParticipantID: try r.string(),
                recipientParticipantID: try r.string(),
                senderSigningPubKey: try r.blob(),
                createdAtUnixMs: try r.i64(),
                expiresAtUnixMs: try r.i64())
            let signature = try r.blob()
            // No trailing bytes: the encoding is exact, like every other
            // wire blob in the kernel.
            guard r.isAtEnd else { throw Failure.malformed }
            return (envelope, signature)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.malformed
        }
    }

    // MARK: Seal / open

    /// Sign with the sender identity, then seal to the recipient's inbox key
    /// bound to the inboxID. The lifetime range is enforced at mint too, so
    /// a coding bug can't ship out-of-policy invites.
    func sealedAndSigned(toRecipientPubKey key: Data, inboxID: String,
                         signer: DeviceSigningIdentity) throws -> Data {
        guard Self.lifetimeValid(createdAtUnixMs: createdAtUnixMs,
                                 expiresAtUnixMs: expiresAtUnixMs) else {
            throw Failure.invalidLifetime
        }
        let signature = try signer.signature(for: signingBody())
        return try ApprovalSeal.sealInviteEnvelope(encoded(signature: signature),
                                                   toRecipientPubKey: key, inboxID: inboxID)
    }

    /// Decrypt, then verify shape → lifetime policy → signature → expiry.
    /// Every failure is terminal (fail-closed) — a bad envelope is dropped,
    /// never partially trusted.
    static func open(_ blob: Data,
                     recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey,
                     inboxID: String, nowUnixMs: Int64) throws -> InviteEnvelope {
        let plaintext: Data
        do {
            plaintext = try ApprovalSeal.openInviteEnvelope(
                blob, recipientPrivateKey: recipientPrivateKey, inboxID: inboxID)
        } catch {
            throw Failure.malformed
        }
        let (envelope, signature) = try decode(plaintext)
        guard lifetimeValid(createdAtUnixMs: envelope.createdAtUnixMs,
                            expiresAtUnixMs: envelope.expiresAtUnixMs) else {
            throw Failure.invalidLifetime
        }
        guard DeviceSigningIdentity.verify(envelope.signingBody(), signature: signature,
                                           publicKeyRaw: envelope.senderSigningPubKey) else {
            throw Failure.badSignature
        }
        guard nowUnixMs < envelope.expiresAtUnixMs else { throw Failure.expired }
        return envelope
    }

    private static func lifetimeValid(createdAtUnixMs: Int64, expiresAtUnixMs: Int64) -> Bool {
        let lifetime = expiresAtUnixMs - createdAtUnixMs
        return lifetime >= minLifetimeMs && lifetime <= maxLifetimeMs
    }
}
