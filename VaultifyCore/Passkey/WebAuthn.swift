import Foundation
import CryptoKit

/// Minimal WebAuthn / CTAP authenticator primitives for a passkey provider:
/// authenticator data, a "none"-attestation object, the COSE EC2 public key,
/// and ES256 assertion signing. Includes just enough CBOR to encode the COSE
/// key and the attestation map (RFC 8949 definite-length items).
///
/// Sign counter is kept at 0 (the spec permits a constant zero counter for
/// authenticators that don't implement one), so assertions never need a write.
nonisolated enum WebAuthn {
    /// Vaultify authenticator AAGUID. Frozen after first passkey release.
    static let aaguid = Data([
        0x90, 0x78, 0x98, 0x4A, 0xB6, 0xCA, 0x4D, 0xA9,
        0xAA, 0x36, 0x9B, 0xB2, 0xA3, 0xB2, 0x3F, 0x02,
    ])

    static let flagUserPresent: UInt8 = 0x01
    static let flagUserVerified: UInt8 = 0x04
    static let flagBackupEligible: UInt8 = 0x08
    static let flagBackupState: UInt8 = 0x10
    static let flagAttestedData: UInt8 = 0x40
    static let legacyAssertionFlags = flagUserPresent | flagUserVerified
    static let newCredentialFlags = flagUserPresent | flagUserVerified | flagBackupEligible | flagBackupState
    /// Flags for a credential created by a conditional (automatic) registration:
    /// no user-verification ceremony ran, so the authenticator must not claim
    /// UP/UV. The credential is still backup-eligible and backed up (envelope
    /// sync), so BE/BS stay set.
    static let conditionalCredentialFlags = flagBackupEligible | flagBackupState

    /// Flags for an assertion produced by this provider. Every assertion route
    /// runs behind the interactive unlock gate (Face ID or master password), so
    /// UP and UV are genuinely true per ceremony — even for a credential whose
    /// registration recorded UP=0/UV=0 (conditional creation). BE/BS carry over
    /// from the stored registration flags: they describe the credential's backup
    /// state, not the ceremony.
    static func assertionFlags(stored: UInt8?) -> UInt8 {
        flagUserPresent | flagUserVerified | ((stored ?? 0) & (flagBackupEligible | flagBackupState))
    }

    struct Registration {
        let credentialID: Data
        let attestationObject: Data
        let privateKeyRaw: Data
        let flags: UInt8
    }

    /// Create a new passkey: P-256 key pair + credential id + attestation object.
    /// `flags` defaults to an interactive ceremony (UP|UV|BE|BS); conditional
    /// creations pass `conditionalCredentialFlags` because no user was present
    /// or verified when the credential was minted.
    static func register(relyingParty: String, flags: UInt8 = newCredentialFlags) -> Registration {
        let privateKey = P256.Signing.PrivateKey()
        let credentialID = Data(CryptoRandom.bytes(16))
        let attested = attestedCredentialData(credentialID: credentialID, publicKey: privateKey.publicKey)
        let authData = authenticatorData(relyingParty: relyingParty,
                                         flags: flags | flagAttestedData,
                                         attestedCredentialData: attested)
        return Registration(credentialID: credentialID,
                            attestationObject: attestationObject(authData: authData),
                            privateKeyRaw: privateKey.rawRepresentation,
                            flags: flags)
    }

    /// Produce an assertion (authenticatorData + DER ECDSA signature) for a login.
    static func assertion(relyingParty: String, clientDataHash: Data, privateKeyRaw: Data, flags: UInt8) throws
        -> (authenticatorData: Data, signature: Data) {
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
        let authData = authenticatorData(relyingParty: relyingParty,
                                         flags: flags)
        let signature = try privateKey.signature(for: authData + clientDataHash)
        return (authData, signature.derRepresentation)
    }

    // MARK: Authenticator data

    static func authenticatorData(relyingParty: String, flags: UInt8,
                                  signCount: UInt32 = 0, attestedCredentialData: Data? = nil) -> Data {
        var data = Data(SHA256.hash(data: Data(relyingParty.utf8)))
        data.append(flags)
        data.append(contentsOf: signCount.bigEndian4)
        if let attestedCredentialData { data.append(attestedCredentialData) }
        return data
    }

    /// AAGUID ‖ credentialIdLength(2 BE) ‖ credentialId ‖ COSE public key.
    static func attestedCredentialData(credentialID: Data, publicKey: P256.Signing.PublicKey) -> Data {
        var data = aaguid
        let length = UInt16(credentialID.count)
        data.append(UInt8(length >> 8)); data.append(UInt8(length & 0xff))
        data.append(credentialID)
        data.append(coseKey(publicKey))
        return data
    }

    /// COSE_Key (CBOR map) for an EC2 / P-256 / ES256 public key.
    static func coseKey(_ publicKey: P256.Signing.PublicKey) -> Data {
        let raw = publicKey.rawRepresentation            // 64 bytes: X(32) ‖ Y(32)
        var cbor = Data([0xA5])                          // map of 5 pairs
        cbor += cborInt(1)  + cborInt(2)                 // kty: EC2
        cbor += cborInt(3)  + cborInt(-7)                // alg: ES256
        cbor += cborInt(-1) + cborInt(1)                 // crv: P-256
        cbor += cborInt(-2) + cborBytes(raw.prefix(32))  // x
        cbor += cborInt(-3) + cborBytes(raw.suffix(32))  // y
        return cbor
    }

    /// attestationObject = CBOR { fmt: "none", attStmt: {}, authData: <bytes> }.
    static func attestationObject(authData: Data) -> Data {
        var cbor = Data([0xA3])                          // map of 3 pairs
        cbor += cborText("fmt")     + cborText("none")
        cbor += cborText("attStmt") + Data([0xA0])       // empty map
        cbor += cborText("authData") + cborBytes(authData)
        return cbor
    }

    // MARK: Minimal CBOR encoder

    static func cborInt(_ value: Int) -> Data {
        value >= 0 ? cborHead(major: 0, value: UInt64(value))
                   : cborHead(major: 1, value: UInt64(-1 - value))
    }
    static func cborBytes<D: DataProtocol>(_ bytes: D) -> Data {
        cborHead(major: 2, value: UInt64(bytes.count)) + Data(bytes)
    }
    static func cborText(_ string: String) -> Data {
        let utf8 = Data(string.utf8)
        return cborHead(major: 3, value: UInt64(utf8.count)) + utf8
    }
    private static func cborHead(major: UInt8, value: UInt64) -> Data {
        let prefix = major << 5
        switch value {
        case 0...23: return Data([prefix | UInt8(value)])
        case 24...0xff: return Data([prefix | 24, UInt8(value)])
        case 0x100...0xffff: return Data([prefix | 25, UInt8(value >> 8), UInt8(value & 0xff)])
        default:
            return Data([prefix | 26,
                         UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
                         UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
        }
    }
}

private extension UInt32 {
    nonisolated var bigEndian4: [UInt8] { [UInt8(self >> 24 & 0xff), UInt8(self >> 16 & 0xff), UInt8(self >> 8 & 0xff), UInt8(self & 0xff)] }
}
