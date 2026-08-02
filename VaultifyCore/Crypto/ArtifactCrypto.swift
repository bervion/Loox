import CryptoKit
import Foundation

/// Sealed metadata that travels WITH an artifact (inside `ArtifactRecord.sealedManifest`,
/// encrypted under the artifact's own DEK). Everything here is secret at rest;
/// the plaintext hash lets a restore prove the recovered bytes are the original ones.
nonisolated struct ArtifactManifest: Codable, Equatable, Sendable {
    var filename: String
    var utiType: String
    var plaintextByteCount: Int
    var plaintextSHA256: Data
}

/// Per-artifact encryption for owned binary attachments.
///
/// Key hierarchy: each artifact gets its own random 256-bit DEK. The DEK — not
/// the Vault Key — seals the ciphertext file and the manifest, so re-keying the
/// vault only ever re-wraps 32 bytes per artifact, and a backup can hand a single
/// artifact's key to a different wrapping key without touching the blob.
///
/// Every seal is AAD-bound to the artifact id, the owning item id, and (for
/// blobs) a purpose string. A ciphertext copied between artifact slots, re-parented
/// to another item, or replayed in a different role fails authentication instead
/// of decrypting.
///
/// Envelope layout: `version(1) || nonce(12) || ciphertext || tag(16)`.
nonisolated enum ArtifactCrypto {
    enum Failure: Error, Equatable {
        /// The byte count exceeds the hard ceiling. Raised from the count alone,
        /// before any output buffer is allocated.
        case oversize(byteCount: Int)
        case malformedEnvelope
        case unsupportedVersion(UInt8)
    }

    static let envelopeVersion: UInt8 = 1

    /// Hard ceiling on artifact plaintext. One-shot AEAD keeps the whole buffer
    /// in memory, so the bound is what keeps a hostile or accidental huge file
    /// from ballooning the process.
    static let maxPlaintextBytes = 20 * 1024 * 1024

    /// Version prefix + GCM nonce + GCM tag.
    static let envelopeOverheadBytes = 1 + 12 + 16

    /// Largest envelope a valid plaintext can produce — the pre-allocation
    /// bound for the open path (and for file sizes read from disk).
    static let maxEnvelopeBytes = maxPlaintextBytes + envelopeOverheadBytes

    /// Purpose tag for the on-disk ciphertext file.
    static let purposeFile = "file"
    /// Purpose tag for a blob travelling inside an encrypted backup.
    static let purposeBackup = "backup"
    /// Owner placeholder for a staged (not yet committed) blob. Real owner ids
    /// are UUIDs, so this can never collide with one.
    static let stagingOwnerID = "vaultify.staging"

    static func newDEK() -> [UInt8] { CryptoRandom.bytes(32) }

    // MARK: AAD domains

    static func dekAAD(artifactID: String, ownerItemID: String) -> Data {
        Data("vaultify.artifact.dek.v1|\(artifactID)|\(ownerItemID)".utf8)
    }

    static func blobAAD(artifactID: String, ownerItemID: String, purpose: String) -> Data {
        Data("vaultify.artifact.blob.v1|\(artifactID)|\(ownerItemID)|\(purpose)".utf8)
    }

    static func manifestAAD(artifactID: String, ownerItemID: String) -> Data {
        Data("vaultify.artifact.manifest.v1|\(artifactID)|\(ownerItemID)".utf8)
    }

    // MARK: DEK wrap

    static func wrapDEK(_ dek: [UInt8], under vaultKey: SecureBytes,
                        artifactID: String, ownerItemID: String) throws -> Data {
        try AESGCM.seal(Data(dek), key: vaultKey,
                        aad: dekAAD(artifactID: artifactID, ownerItemID: ownerItemID))
    }

    static func unwrapDEK(_ wrapped: Data, under vaultKey: SecureBytes,
                          artifactID: String, ownerItemID: String) throws -> [UInt8] {
        Array(try AESGCM.open(wrapped, key: vaultKey,
                              aad: dekAAD(artifactID: artifactID, ownerItemID: ownerItemID)))
    }

    // MARK: Blob seal/open

    static func sealArtifact(plaintext: Data, dek: [UInt8],
                             artifactID: String, ownerItemID: String,
                             purpose: String) throws -> Data {
        guard plaintext.count <= maxPlaintextBytes else {
            throw Failure.oversize(byteCount: plaintext.count)
        }
        var envelope = Data([envelopeVersion])
        envelope.append(try AESGCM.seal(
            plaintext, key: dek,
            aad: blobAAD(artifactID: artifactID, ownerItemID: ownerItemID, purpose: purpose)))
        return envelope
    }

    static func openArtifact(envelope: Data, dek: [UInt8],
                             artifactID: String, ownerItemID: String,
                             purpose: String) throws -> Data {
        // The size gate runs on the count alone so an oversized envelope is
        // refused before any plaintext buffer exists.
        guard envelope.count <= maxEnvelopeBytes else {
            throw Failure.oversize(byteCount: envelope.count)
        }
        // `>=`: an EMPTY plaintext is legitimate (its envelope is exactly the
        // overhead — version + nonce + tag over zero ciphertext bytes).
        guard envelope.count >= envelopeOverheadBytes, let version = envelope.first else {
            throw Failure.malformedEnvelope
        }
        guard version == envelopeVersion else { throw Failure.unsupportedVersion(version) }
        return try AESGCM.open(
            Data(envelope.dropFirst()), key: dek,
            aad: blobAAD(artifactID: artifactID, ownerItemID: ownerItemID, purpose: purpose))
    }

    // MARK: Manifest seal/open

    static func sealManifest(_ manifest: ArtifactManifest, dek: [UInt8],
                             artifactID: String, ownerItemID: String) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(manifest), key: dek,
                        aad: manifestAAD(artifactID: artifactID, ownerItemID: ownerItemID))
    }

    static func openManifest(_ sealed: Data, dek: [UInt8],
                             artifactID: String, ownerItemID: String) throws -> ArtifactManifest {
        let json = try AESGCM.open(sealed, key: dek,
                                   aad: manifestAAD(artifactID: artifactID, ownerItemID: ownerItemID))
        return try JSONDecoder().decode(ArtifactManifest.self, from: json)
    }

    // MARK: Hashing

    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}
