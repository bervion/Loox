import CryptoKit
import Foundation

/// Crypto primitives for the Approval Mode control plane: the persistent
/// device signing identity, HPKE sealing (two-recipient contract, ADR-3),
/// and the human-comparable trust fingerprint (ADR-4).
///
/// NET-NEW code — `VaultKeyPairing`/`PasskeyEnvelope` are pattern references
/// only (their `info` strings and payload lengths are hard-coded elsewhere).

// MARK: - Device signing identity (P256, Keychain-persisted)

/// This device's long-lived control-plane signing key. Created once, kept in
/// the Keychain (`WhenUnlockedThisDeviceOnly`, never synced) — losing it just
/// means re-enrolling the device into grants.
nonisolated struct DeviceSigningIdentity: Sendable {
    private let privateKey: P256.Signing.PrivateKey

    static let keychainAccount = "approval_device_signing_key_v1"

    enum Failure: Error { case corruptKeyMaterial }

    var publicKeyRaw: Data { privateKey.publicKey.rawRepresentation }

    /// Loads the existing identity or creates one on FIRST use. Undecodable
    /// keychain material THROWS instead of silently regenerating — a new key
    /// would break every pin that references this device with nothing but an
    /// unexplained `requesterKeyUnpinned` on the far side; surfacing the
    /// corruption lets the UI drive an explicit re-enrollment.
    static func loadOrCreate() throws -> DeviceSigningIdentity {
        if let raw = try KeychainStore.get(account: keychainAccount) {
            guard let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) else {
                throw Failure.corruptKeyMaterial
            }
            return DeviceSigningIdentity(privateKey: key)
        }
        let key = P256.Signing.PrivateKey()
        try KeychainStore.set(key.rawRepresentation, account: keychainAccount)
        return DeviceSigningIdentity(privateKey: key)
    }

    /// In-memory identity for tests / ephemeral flows (never persisted).
    static func ephemeral() -> DeviceSigningIdentity {
        DeviceSigningIdentity(privateKey: P256.Signing.PrivateKey())
    }

    private init(privateKey: P256.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    /// ECDSA-P256/SHA-256, 64-byte raw signature.
    func signature(for data: Data) throws -> Data {
        try privateKey.signature(for: data).rawRepresentation
    }

    static func verify(_ data: Data, signature: Data, publicKeyRaw: Data) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(rawRepresentation: publicKeyRaw),
              let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            return false
        }
        return publicKey.isValidSignature(ecdsa, for: data)
    }
}

// MARK: - HPKE seals (ADR-3: two recipients, two purposes — never cross)

/// `askEachTime` responses seal to the request's EPHEMERAL key with
/// `info = requestId + nonce` (forward secrecy, replay-bound). Static
/// `shared` field blobs seal to B's PERSISTENT participant key with
/// `info = grantId + fieldId`. Distinct keys AND distinct info strings —
/// opening with the wrong pair fails.
nonisolated enum ApprovalSeal {
    enum Failure: Error, Equatable { case invalidEnvelope, unknownVersion, invalidRecipientKey }

    private static let version: UInt8 = 1
    private static let encapsulatedKeyLength = 32
    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    // Info strings are built with the canonical writer (length-prefixed
    // components) — plain "a|b" concatenation is not injective when ids can
    // contain the separator, and fieldIds are arbitrary mutable strings.

    private static func responseInfo(requestId: String, nonce: Data) -> Data {
        var w = CanonicalWriter()
        w.string("Loox approval response v1")
        w.string(requestId)
        w.blob(nonce)
        return w.data
    }

    private static func sharedFieldInfo(grantId: String, fieldId: String) -> Data {
        var w = CanonicalWriter()
        w.string("Loox shared field v1")
        w.string(grantId)
        w.string(fieldId)
        return w.data
    }

    private static func displayEnvelopeInfo(grantId: String) -> Data {
        var w = CanonicalWriter()
        w.string("Loox display envelope v1")
        w.string(grantId)
        return w.data
    }

    /// Per-device variants (grant v2): the deviceKeyID rides in the HPKE
    /// info, so an envelope sealed for device A can never be opened by (or
    /// swapped onto) device B even if both keys leaked — the AEAD binding
    /// fails first.
    private static func sharedFieldInfoV2(grantId: String, fieldId: String,
                                          deviceKeyID: Data) -> Data {
        var w = CanonicalWriter()
        w.string("Loox shared field v2")
        w.string(grantId)
        w.string(fieldId)
        w.blob(deviceKeyID)
        return w.data
    }

    private static func displayEnvelopeInfoV2(grantId: String, deviceKeyID: Data) -> Data {
        var w = CanonicalWriter()
        w.string("Loox display envelope v2")
        w.string(grantId)
        w.blob(deviceKeyID)
        return w.data
    }

    private static func inviteEnvelopeInfo(inboxID: String) -> Data {
        var w = CanonicalWriter()
        w.string("Loox invite envelope v1")
        w.string(inboxID)
        return w.data
    }

    // Envelope layout mirrors the pairing envelope: version || encap(32) || ct.

    private static func seal(_ plaintext: Data, recipientKeyRaw: Data, info: Data) throws -> Data {
        guard let recipientKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientKeyRaw) else {
            throw Failure.invalidRecipientKey
        }
        var sender = try HPKE.Sender(recipientKey: recipientKey, ciphersuite: ciphersuite, info: info)
        let ciphertext = try sender.seal(plaintext)
        var envelope = Data([version])
        envelope.append(sender.encapsulatedKey)
        envelope.append(ciphertext)
        return envelope
    }

    private static func open(_ envelope: Data,
                             privateKey: Curve25519.KeyAgreement.PrivateKey,
                             info: Data) throws -> Data {
        guard envelope.count > 1 + encapsulatedKeyLength else { throw Failure.invalidEnvelope }
        guard envelope.first == version else { throw Failure.unknownVersion }
        let encapsulatedKey = envelope.dropFirst().prefix(encapsulatedKeyLength)
        let ciphertext = envelope.dropFirst(1 + encapsulatedKeyLength)
        var recipient = try HPKE.Recipient(privateKey: privateKey, ciphersuite: ciphersuite,
                                           info: info, encapsulatedKey: Data(encapsulatedKey))
        return try recipient.open(Data(ciphertext))
    }

    // MARK: askEachTime response ↔ per-request ephemeral key

    static func sealResponsePayload(_ plaintext: Data, toEphemeralPubKey key: Data,
                                    requestId: String, nonce: Data) throws -> Data {
        try seal(plaintext, recipientKeyRaw: key, info: responseInfo(requestId: requestId, nonce: nonce))
    }

    static func openResponsePayload(_ envelope: Data,
                                    ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey,
                                    requestId: String, nonce: Data) throws -> Data {
        try open(envelope, privateKey: ephemeralPrivateKey,
                 info: responseInfo(requestId: requestId, nonce: nonce))
    }

    // MARK: display envelope ↔ persistent participant key

    static func sealDisplayEnvelope(_ plaintext: Data, toParticipantPubKey key: Data,
                                    grantId: String) throws -> Data {
        try seal(plaintext, recipientKeyRaw: key, info: displayEnvelopeInfo(grantId: grantId))
    }

    static func openDisplayEnvelope(_ envelope: Data,
                                    participantPrivateKey: Curve25519.KeyAgreement.PrivateKey,
                                    grantId: String) throws -> Data {
        try open(envelope, privateKey: participantPrivateKey,
                 info: displayEnvelopeInfo(grantId: grantId))
    }

    // MARK: invite envelope ↔ recipient inbox key (U5 public rendezvous)

    /// Sealing binds the ciphertext to the TARGET inboxID via the HPKE info —
    /// a drop copied into another inbox (or replayed after an inbox rotation)
    /// fails to open even with the right private key.
    static func sealInviteEnvelope(_ plaintext: Data, toRecipientPubKey key: Data,
                                   inboxID: String) throws -> Data {
        try seal(plaintext, recipientKeyRaw: key, info: inviteEnvelopeInfo(inboxID: inboxID))
    }

    static func openInviteEnvelope(_ envelope: Data,
                                   recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey,
                                   inboxID: String) throws -> Data {
        try open(envelope, privateKey: recipientPrivateKey,
                 info: inviteEnvelopeInfo(inboxID: inboxID))
    }

    // MARK: shared field blob ↔ persistent participant key

    static func sealSharedField(_ plaintext: Data, toParticipantPubKey key: Data,
                                grantId: String, fieldId: String) throws -> Data {
        try seal(plaintext, recipientKeyRaw: key, info: sharedFieldInfo(grantId: grantId, fieldId: fieldId))
    }

    static func openSharedField(_ envelope: Data,
                                participantPrivateKey: Curve25519.KeyAgreement.PrivateKey,
                                grantId: String, fieldId: String) throws -> Data {
        try open(envelope, privateKey: participantPrivateKey,
                 info: sharedFieldInfo(grantId: grantId, fieldId: fieldId))
    }

    // MARK: per-device seal (grant v2 — INV-04: never a legacy synced key)

    static func sealSharedFieldForDevice(_ plaintext: Data, toDevicePubKey key: Data,
                                         deviceKeyID: Data,
                                         grantId: String, fieldId: String) throws -> Data {
        try seal(plaintext, recipientKeyRaw: key,
                 info: sharedFieldInfoV2(grantId: grantId, fieldId: fieldId,
                                         deviceKeyID: deviceKeyID))
    }

    static func openSharedFieldForDevice(_ envelope: Data,
                                         deviceIdentity: DeviceHPKEIdentity,
                                         grantId: String, fieldId: String) throws -> Data {
        try open(envelope, privateKey: deviceIdentity.agreementPrivateKey,
                 info: sharedFieldInfoV2(grantId: grantId, fieldId: fieldId,
                                         deviceKeyID: deviceIdentity.deviceKeyID))
    }

    static func sealDisplayEnvelopeForDevice(_ plaintext: Data, toDevicePubKey key: Data,
                                             deviceKeyID: Data, grantId: String) throws -> Data {
        try seal(plaintext, recipientKeyRaw: key,
                 info: displayEnvelopeInfoV2(grantId: grantId, deviceKeyID: deviceKeyID))
    }

    static func openDisplayEnvelopeForDevice(_ envelope: Data,
                                             deviceIdentity: DeviceHPKEIdentity,
                                             grantId: String) throws -> Data {
        try open(envelope, privateKey: deviceIdentity.agreementPrivateKey,
                 info: displayEnvelopeInfoV2(grantId: grantId,
                                             deviceKeyID: deviceIdentity.deviceKeyID))
    }
}

// MARK: - Per-device sealed blob container (grant v2)

/// One CloudKit blob carrying an envelope per allowed device — same record
/// count/linkage as v1 (metadata hygiene), recipients pick their own entry
/// by deviceKeyID. Readers choose the format by the GRANT's wire version,
/// never by sniffing bytes; the marker byte is a sanity check only.
nonisolated struct PerDeviceSealedBlob: Sendable {
    static let marker: UInt8 = 0xD2

    /// deviceKeyID (hex) → HPKE envelope sealed for that device.
    var envelopes: [String: Data]

    enum CodecFailure: Error { case malformed }

    func encoded() throws -> Data {
        var data = Data([Self.marker])
        data.append(try JSONEncoder().encode(envelopes))
        return data
    }

    static func decode(_ data: Data) throws -> PerDeviceSealedBlob {
        guard data.first == marker,
              let envelopes = try? JSONDecoder().decode([String: Data].self,
                                                        from: data.dropFirst()) else {
            throw CodecFailure.malformed
        }
        return PerDeviceSealedBlob(envelopes: envelopes)
    }

    func envelope(forDeviceKeyID id: Data) -> Data? { envelopes[id.hexString] }
}

// MARK: - Trust fingerprint (ADR-4 one-time out-of-band compare)

/// Short human-comparable code over both parties' long-lived public keys.
/// A and B read it to each other ONCE (call/in person); after confirmation
/// the owner key is TOFU-pinned and any change is rejected.
nonisolated enum TrustFingerprint {
    /// Short per-request match code shown on BOTH sides during an approval
    /// ceremony (owner sheet + requester waiting screen) so A can eyeball
    /// that the request on screen is the one B actually sent.
    static func requestCode(requestId: String, nonce: Data) -> String {
        var w = CanonicalWriter()
        w.string("Loox request code v1")
        w.string(requestId)
        w.blob(nonce)
        let digest = Data(SHA256.hash(data: w.data))
        let value = digest.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        return String(format: "%05d", value % 100_000)
    }

    /// "12345-67890-24680" — three 5-digit groups from a domain-separated
    /// SHA-256 over both keys (length-prefixed; order fixed owner-first).
    static func code(ownerSigningPubKey: Data, participantPubKey: Data) -> String {
        var w = CanonicalWriter()
        w.string("Loox trust fingerprint v1")
        w.blob(ownerSigningPubKey)
        w.blob(participantPubKey)
        let digest = Data(SHA256.hash(data: w.data))
        let groups = (0..<3).map { i -> String in
            let chunk = digest.subdata(in: (i * 4)..<(i * 4 + 4))
            let value = chunk.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            return String(format: "%05d", value % 100_000)
        }
        return groups.joined(separator: "-")
    }
}
