import CryptoKit
import XCTest
@testable import Vaultify

/// Pins the exact failure that stranded the recipient: a participant escrow
/// sealed under one Vault Key cannot be opened with a different key — it throws
/// `CryptoKitError.authenticationFailure`. The recovery path in
/// `ParticipantEscrowService` keys off precisely this `fromEscrow` failure to
/// regenerate the identity instead of failing forever.
final class ParticipantEscrowStaleKeyTests: XCTestCase {

    private let keyA = [UInt8](repeating: 0x11, count: 32)
    private let keyB = [UInt8](repeating: 0x22, count: 32)

    func testRoundtripWithSameKeyRecoversIdentity() throws {
        let identity = ParticipantIdentity.generate()
        let envelope = try identity.escrowSealed(vaultKey: keyA)
        let reopened = try ParticipantIdentity.fromEscrow(envelope, vaultKey: keyA)
        XCTAssertEqual(reopened.publicKeyRaw, identity.publicKeyRaw)
    }

    func testWrongVaultKeyThrowsAuthenticationFailure() throws {
        // A stale cloud escrow (previous vault) opened with the current key.
        let envelope = try ParticipantIdentity.generate().escrowSealed(vaultKey: keyA)
        XCTAssertThrowsError(try ParticipantIdentity.fromEscrow(envelope, vaultKey: keyB)) { error in
            XCTAssertTrue(error is CryptoKitError,
                          "expected the GCM tag mismatch that strands the recipient, got \(error)")
        }
    }

    func testUnknownVersionByteThrows() throws {
        var envelope = try ParticipantIdentity.generate().escrowSealed(vaultKey: keyA)
        envelope[envelope.startIndex] = 0xFF // corrupt the version prefix
        XCTAssertThrowsError(try ParticipantIdentity.fromEscrow(envelope, vaultKey: keyA))
    }
}
