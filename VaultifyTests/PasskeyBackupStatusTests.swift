import XCTest
@testable import Vaultify

final class PasskeyBackupStatusTests: XCTestCase {

    func testNewCredentialFlagsAreBackedUp() {
        XCTAssertEqual(PasskeyBackupStatus.evaluate(flags: WebAuthn.newCredentialFlags), .backedUp)
    }

    func testBackupEligibleWithoutBackupStateIsEligible() {
        let flags = WebAuthn.flagUserPresent | WebAuthn.flagUserVerified | WebAuthn.flagBackupEligible
        XCTAssertEqual(PasskeyBackupStatus.evaluate(flags: flags), .backupEligible)
    }

    func testLegacyNilFlagsAreDeviceBound() {
        XCTAssertEqual(PasskeyBackupStatus.evaluate(flags: nil), .deviceBound)
    }

    func testLegacyUPUVOnlyIsDeviceBound() {
        XCTAssertEqual(PasskeyBackupStatus.evaluate(flags: WebAuthn.legacyAssertionFlags), .deviceBound)
    }

    func testBackupStateWithoutEligibilityIsDeviceBound() {
        // BS set without BE is spec-invalid; treat conservatively as device-bound.
        let flags = WebAuthn.flagUserPresent | WebAuthn.flagUserVerified | WebAuthn.flagBackupState
        XCTAssertEqual(PasskeyBackupStatus.evaluate(flags: flags), .deviceBound)
    }
}
