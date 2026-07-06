import XCTest
@testable import Vaultify

/// P4A rotation semantics at the pure crypto level (the CloudKit escrow paths in
/// RelayPrincipalEscrowService aren't unit-testable without a live container).
/// A rotate command is signed by the CURRENT key and authorizes the NEXT epoch;
/// it must verify under the OLD public key only.
final class RelayPrincipalRotationTests: XCTestCase {

    private let vaultKey = [UInt8](repeating: 0x2a, count: 32)

    func testRotationEscrowRoundTripPreservesIdentity() throws {
        let genesis = RelayPrincipalIdentity.generate()
        let rotated = genesis.rotated()
        let restored = try RelayPrincipalIdentity.fromEscrow(rotated.escrowSealed(vaultKey: vaultKey), vaultKey: vaultKey)
        XCTAssertEqual(restored.principalID, genesis.principalID)  // stable across rotation
        XCTAssertEqual(restored.epoch, 2)
        XCTAssertEqual(restored.signingPublicKey, rotated.signingPublicKey)
    }

    func testRotateCommandVerifiesUnderOldKeyOnly() throws {
        let current = RelayPrincipalIdentity.generate()
        let next = current.rotated()
        let command = RelayCommand(principalID: current.principalID, epoch: current.epoch,
                                   nonce: Data(CryptoRandom.bytes(16)),
                                   issuedAtUnixMs: 1_760_000_000_000,
                                   kind: .rotatePrincipal, newPublicKey: next.signingPublicKey)
        let signed = try RelayCommandCanonical.sign(command, using: current)

        // Verifies under the OLD (authorizing) key...
        XCTAssertTrue(RelayCommandCanonical.verify(command, signature: signed.signature,
                                                   x963PublicKey: current.signingPublicKey))
        // ...and NOT under the new key it is rotating to.
        XCTAssertFalse(RelayCommandCanonical.verify(command, signature: signed.signature,
                                                    x963PublicKey: next.signingPublicKey))
    }

    func testRotateCommandCarriesCurrentEpochAndNextKey() {
        let current = RelayPrincipalIdentity.generate()
        let next = current.rotated()
        let command = RelayCommand(principalID: current.principalID, epoch: current.epoch,
                                   nonce: Data(CryptoRandom.bytes(16)), issuedAtUnixMs: 0,
                                   kind: .rotatePrincipal, newPublicKey: next.signingPublicKey)
        XCTAssertEqual(command.epoch, current.epoch)          // signed under N, advances to N+1
        XCTAssertEqual(command.newPublicKey, next.signingPublicKey)
        XCTAssertEqual(command.principalID, current.principalID)
    }
}
