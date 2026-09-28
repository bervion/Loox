import XCTest
import CryptoKit
@testable import Vaultify

/// P4A Relay Principal crypto core: fingerprint determinism, Vault-Key escrow
/// round-trip, throw-not-regenerate on corruption, rotation-preserves-identity,
/// and sign/verify. No network.
final class RelayPrincipalIdentityTests: XCTestCase {

    private let vaultKey = [UInt8](repeating: 0x2a, count: 32)

    func testPrincipalIDIsDeterministicAnd32Bytes() {
        let key = P256.Signing.PrivateKey()
        let pub = key.publicKey.x963Representation
        let a = RelayPrincipalIdentity.derivePrincipalID(x963Pub: pub)
        let b = RelayPrincipalIdentity.derivePrincipalID(x963Pub: pub)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }

    func testGenesisHasEpochOneAndMatchingID() {
        let id = RelayPrincipalIdentity.generate()
        XCTAssertEqual(id.epoch, 1)
        XCTAssertEqual(id.principalID,
                       RelayPrincipalIdentity.derivePrincipalID(x963Pub: id.signingPublicKey))
    }

    func testEscrowRoundTrip() throws {
        let id = RelayPrincipalIdentity.generate()
        let restored = try RelayPrincipalIdentity.fromEscrow(id.escrowSealed(vaultKey: vaultKey), vaultKey: vaultKey)
        XCTAssertEqual(restored.principalID, id.principalID)
        XCTAssertEqual(restored.epoch, id.epoch)
        XCTAssertEqual(restored.signingPublicKey, id.signingPublicKey)
    }

    func testEscrowWrongKeyThrows() throws {
        let id = RelayPrincipalIdentity.generate()
        let sealed = try id.escrowSealed(vaultKey: vaultKey)
        XCTAssertThrowsError(try RelayPrincipalIdentity.fromEscrow(sealed, vaultKey: [UInt8](repeating: 0x99, count: 32)))
    }

    /// An app reinstall gives the device a new vault, so the escrow the old vault
    /// sealed must fail as `cannotOpenWithVaultKey`. A bare CryptoKit error was
    /// reported to the user as an iCloud problem, with no way out.
    func testEscrowFromAnotherVaultIsRecognisedAsUnopenable() throws {
        let sealed = try RelayPrincipalIdentity.generate().escrowSealed(vaultKey: vaultKey)
        let reinstalledVault = [UInt8](repeating: 0x99, count: 32)
        XCTAssertThrowsError(try RelayPrincipalIdentity.fromEscrow(sealed, vaultKey: reinstalledVault)) { error in
            XCTAssertEqual(error as? RelayPrincipalIdentity.EscrowFailure, .cannotOpenWithVaultKey)
        }
    }

    func testCorruptEnvelopeThrowsNotRegenerates() throws {
        let id = RelayPrincipalIdentity.generate()
        var sealed = try id.escrowSealed(vaultKey: vaultKey)
        sealed[sealed.count - 1] ^= 0xFF               // flip a ciphertext byte
        XCTAssertThrowsError(try RelayPrincipalIdentity.fromEscrow(sealed, vaultKey: vaultKey))
        var badVersion = try id.escrowSealed(vaultKey: vaultKey)
        badVersion[0] = 0x09                            // unknown version byte
        XCTAssertThrowsError(try RelayPrincipalIdentity.fromEscrow(badVersion, vaultKey: vaultKey)) { error in
            XCTAssertEqual(error as? RelayPrincipalIdentity.EscrowFailure, .unknownVersion)
        }
    }

    func testRotationPreservesIdentityAndAdvancesEpoch() {
        let id = RelayPrincipalIdentity.generate()
        let rotated = id.rotated()
        XCTAssertEqual(rotated.epoch, id.epoch + 1)
        XCTAssertEqual(rotated.principalID, id.principalID)     // stable id
        XCTAssertNotEqual(rotated.signingPublicKey, id.signingPublicKey)  // new key
    }

    func testRotatedEscrowRoundTripsWithoutIdentityCheck() throws {
        // After rotation the pubkey no longer derives the (frozen) principalID;
        // fromEscrow must trust the stored id for epoch > 1.
        let rotated = RelayPrincipalIdentity.generate().rotated()
        let restored = try RelayPrincipalIdentity.fromEscrow(rotated.escrowSealed(vaultKey: vaultKey), vaultKey: vaultKey)
        XCTAssertEqual(restored.principalID, rotated.principalID)
        XCTAssertEqual(restored.epoch, 2)
    }

    func testSignVerify() throws {
        let id = RelayPrincipalIdentity.generate()
        let msg = Data("relay-command".utf8)
        let sig = try id.signature(for: msg)
        XCTAssertTrue(RelayPrincipalIdentity.verify(msg, signature: sig, x963PublicKey: id.signingPublicKey))
        XCTAssertFalse(RelayPrincipalIdentity.verify(Data("tampered".utf8), signature: sig, x963PublicKey: id.signingPublicKey))
    }
}
