import Foundation

/// Presentation metadata for a share — DELIBERATELY separate from the signed
/// `AccessGrant` (different lifecycle: renaming an item is not a capability
/// mutation and must never require re-signing or a wire bump). Sealed to the
/// recipient's participant key and bound to the grant id via the HPKE info,
/// so the public record shows only ciphertext (no plaintext titles in
/// CloudKit — metadata hygiene).
nonisolated struct SharedDisplayEnvelope: Codable, Sendable, Equatable {
    /// Presentation metadata for ONE shared field: the recipient renders a
    /// username as a username and a password as a password (labels, masking,
    /// AutoFill kinds) instead of a generic "shared value". Sealed with the
    /// rest of the envelope — never plaintext in CloudKit.
    struct FieldMeta: Codable, Sendable, Equatable {
        var label: String
        /// `FieldKind` rawValue; unknown values fall back to a secret kind.
        var kind: String
    }

    var title: String
    var websiteHost: String?
    var updatedAtUnixMs: Int64
    /// Monotonic per-grant revision — recipients ignore an older revision
    /// arriving after a newer one (out-of-order CloudKit delivery).
    var revision: UInt32
    /// Per-fieldId metadata (optional — pre-V1.2 envelopes decode fine).
    var fields: [String: FieldMeta]? = nil

    func sealed(toParticipantPubKey key: Data, grantId: String) throws -> Data {
        try ApprovalSeal.sealDisplayEnvelope(JSONEncoder().encode(self),
                                             toParticipantPubKey: key, grantId: grantId)
    }

    /// Per-device variants (grant v2): Tier-1 metadata is sealed to each
    /// APPROVED device only — an unapproved device stays at Tier 0 (INV-10).
    func sealedForDevice(toDevicePubKey key: Data, deviceKeyID: Data,
                         grantId: String) throws -> Data {
        try ApprovalSeal.sealDisplayEnvelopeForDevice(JSONEncoder().encode(self),
                                                      toDevicePubKey: key,
                                                      deviceKeyID: deviceKeyID,
                                                      grantId: grantId)
    }

    static func openForDevice(_ blob: Data, deviceIdentity: DeviceHPKEIdentity,
                              grantId: String) throws -> SharedDisplayEnvelope {
        let plaintext = try ApprovalSeal.openDisplayEnvelopeForDevice(
            blob, deviceIdentity: deviceIdentity, grantId: grantId)
        return try JSONDecoder().decode(SharedDisplayEnvelope.self, from: plaintext)
    }

    static func open(_ blob: Data, participantIdentity: ParticipantIdentity,
                     grantId: String) throws -> SharedDisplayEnvelope {
        let plaintext = try ApprovalSeal.openDisplayEnvelope(
            blob, participantPrivateKey: participantIdentity.privateKey, grantId: grantId)
        return try JSONDecoder().decode(SharedDisplayEnvelope.self, from: plaintext)
    }
}
