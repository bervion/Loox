import CryptoKit
import XCTest
@testable import Vaultify

final class WebAuthnTests: XCTestCase {
    func testRegistrationAuthenticatorDataUsesVaultifyFlagsAndAAGUID() throws {
        let registration = WebAuthn.register(relyingParty: "example.com")
        let authData = try AttestationReader.authData(from: registration.attestationObject)

        XCTAssertEqual(registration.flags, WebAuthn.newCredentialFlags)
        XCTAssertEqual(authData.prefix(32), Data(SHA256.hash(data: Data("example.com".utf8))))
        XCTAssertEqual(authData[authData.index(authData.startIndex, offsetBy: 32)], 0x5D)
        XCTAssertEqual(authData[33..<37], Data([0, 0, 0, 0]))
        XCTAssertEqual(authData[37..<53], WebAuthn.aaguid)
    }

    func testAttestationObjectIsNoneWithEmptyStatement() throws {
        let registration = WebAuthn.register(relyingParty: "example.com")
        let object = try AttestationReader.decode(registration.attestationObject)

        XCTAssertEqual(object.format, "none")
        XCTAssertTrue(object.attestationStatementIsEmpty)
        XCTAssertFalse(object.authData.isEmpty)
    }

    func testAssertionUsesStoredFlagsAndVerifiesSignature() throws {
        let registration = WebAuthn.register(relyingParty: "example.com")
        let clientHash = Data(SHA256.hash(data: Data("client".utf8)))
        let assertion = try WebAuthn.assertion(relyingParty: "example.com",
                                               clientDataHash: clientHash,
                                               privateKeyRaw: registration.privateKeyRaw,
                                               flags: registration.flags)

        XCTAssertEqual(assertion.authenticatorData[32], 0x1D)
        XCTAssertEqual(assertion.authenticatorData[33..<37], Data([0, 0, 0, 0]))
        let publicKey = try P256.Signing.PrivateKey(rawRepresentation: registration.privateKeyRaw).publicKey
        let signature = try P256.Signing.ECDSASignature(derRepresentation: assertion.signature)
        XCTAssertTrue(publicKey.isValidSignature(signature, for: assertion.authenticatorData + clientHash))
    }

    func testConditionalRegistrationOmitsUserPresenceAndVerification() throws {
        let registration = WebAuthn.register(relyingParty: "example.com",
                                             flags: WebAuthn.conditionalCredentialFlags)
        let authData = try AttestationReader.authData(from: registration.attestationObject)

        // AT|BS|BE only — a conditional creation ran no user-verification ceremony.
        XCTAssertEqual(authData[authData.index(authData.startIndex, offsetBy: 32)], 0x58)
        XCTAssertEqual(registration.flags, WebAuthn.conditionalCredentialFlags)
    }

    func testInteractiveRegistrationDefaultKeepsFullFlags() throws {
        let registration = WebAuthn.register(relyingParty: "example.com")
        let authData = try AttestationReader.authData(from: registration.attestationObject)

        // AT|BS|BE|UV|UP — the default (interactive) ceremony is user-verified.
        XCTAssertEqual(authData[authData.index(authData.startIndex, offsetBy: 32)], 0x5D)
    }

    func testAssertionFlagsAlwaysAssertVerificationAndCopyBackupBits() {
        // Assertions are user-verified by construction; stored registration
        // flags only contribute the backup bits.
        XCTAssertEqual(WebAuthn.assertionFlags(stored: nil), 0x05)                                // UP|UV
        XCTAssertEqual(WebAuthn.assertionFlags(stored: WebAuthn.legacyAssertionFlags), 0x05)      // UP|UV
        XCTAssertEqual(WebAuthn.assertionFlags(stored: WebAuthn.conditionalCredentialFlags), 0x1D) // UP|UV|BE|BS
        XCTAssertEqual(WebAuthn.assertionFlags(stored: WebAuthn.newCredentialFlags), 0x1D)         // UP|UV|BE|BS
    }

    func testAssertionOfConditionallyRegisteredCredentialAssertsVerification() throws {
        let registration = WebAuthn.register(relyingParty: "example.com",
                                             flags: WebAuthn.conditionalCredentialFlags)
        let assertion = try WebAuthn.assertion(relyingParty: "example.com",
                                               clientDataHash: Data(repeating: 2, count: 32),
                                               privateKeyRaw: registration.privateKeyRaw,
                                               flags: WebAuthn.assertionFlags(stored: registration.flags))

        XCTAssertEqual(assertion.authenticatorData[32], 0x1D)
    }

    func testLegacyAssertionKeepsOldFlags() throws {
        let registration = WebAuthn.register(relyingParty: "example.com")
        let assertion = try WebAuthn.assertion(relyingParty: "example.com",
                                               clientDataHash: Data(repeating: 1, count: 32),
                                               privateKeyRaw: registration.privateKeyRaw,
                                               flags: WebAuthn.legacyAssertionFlags)

        XCTAssertEqual(assertion.authenticatorData[32], 0x05)
    }

    func testCoseKeyHeaderAndCborIntegerBoundaries() {
        let cose = WebAuthn.coseKey(P256.Signing.PrivateKey().publicKey)
        XCTAssertEqual(cose.prefix(10), Data([0xA5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20]))
        XCTAssertEqual(cose[cose.index(cose.startIndex, offsetBy: 42)..<cose.index(cose.startIndex, offsetBy: 45)],
                       Data([0x22, 0x58, 0x20]))

        XCTAssertEqual(WebAuthn.cborInt(23), Data([0x17]))
        XCTAssertEqual(WebAuthn.cborInt(24), Data([0x18, 0x18]))
        XCTAssertEqual(WebAuthn.cborInt(255), Data([0x18, 0xFF]))
        XCTAssertEqual(WebAuthn.cborInt(256), Data([0x19, 0x01, 0x00]))
        XCTAssertEqual(WebAuthn.cborInt(65_535), Data([0x19, 0xFF, 0xFF]))
        XCTAssertEqual(WebAuthn.cborInt(65_536), Data([0x1A, 0x00, 0x01, 0x00, 0x00]))
        XCTAssertEqual(WebAuthn.cborInt(-1), Data([0x20]))
        XCTAssertEqual(WebAuthn.cborInt(-24), Data([0x37]))
        XCTAssertEqual(WebAuthn.cborInt(-25), Data([0x38, 0x18]))
    }
}

private struct AttestationObject {
    let format: String
    let attestationStatementIsEmpty: Bool
    let authData: Data
}

private enum AttestationReader {
    static func authData(from data: Data) throws -> Data {
        try decode(data).authData
    }

    static func decode(_ data: Data) throws -> AttestationObject {
        var reader = CBORReader(data)
        XCTAssertEqual(try reader.readMapCount(), 3)
        XCTAssertEqual(try reader.readText(), "fmt")
        let format = try reader.readText()
        XCTAssertEqual(try reader.readText(), "attStmt")
        let attestationStatementIsEmpty = try reader.readMapCount() == 0
        XCTAssertEqual(try reader.readText(), "authData")
        return AttestationObject(format: format,
                                 attestationStatementIsEmpty: attestationStatementIsEmpty,
                                 authData: try reader.readBytes())
    }
}

private struct CBORReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func readMapCount() throws -> Int {
        let head = try readHead(expectedMajor: 5)
        return Int(head)
    }

    mutating func readText() throws -> String {
        let count = Int(try readHead(expectedMajor: 3))
        let data = try read(count: count)
        return String(decoding: data, as: UTF8.self)
    }

    mutating func readBytes() throws -> Data {
        let count = Int(try readHead(expectedMajor: 2))
        return Data(try read(count: count))
    }

    private mutating func readHead(expectedMajor: UInt8) throws -> UInt64 {
        let byte = try readByte()
        XCTAssertEqual(byte >> 5, expectedMajor)
        let additional = byte & 0x1F
        switch additional {
        case 0...23: return UInt64(additional)
        case 24: return UInt64(try readByte())
        case 25:
            let b = try read(count: 2)
            return UInt64(b[0]) << 8 | UInt64(b[1])
        case 26:
            let b = try read(count: 4)
            return UInt64(b[0]) << 24 | UInt64(b[1]) << 16 | UInt64(b[2]) << 8 | UInt64(b[3])
        default:
            XCTFail("Unsupported CBOR head")
            return 0
        }
    }

    private mutating func readByte() throws -> UInt8 {
        let values = try read(count: 1)
        return values[0]
    }

    private mutating func read(count: Int) throws -> [UInt8] {
        XCTAssertLessThanOrEqual(offset + count, bytes.count)
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }
}
