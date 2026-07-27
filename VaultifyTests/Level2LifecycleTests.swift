import XCTest
@testable import Vaultify

/// The Extra Protection (Level-2) crypto contract and the parts of its lifecycle
/// that can be proven without a device.
///
/// Deliberately NOT covered here: biometric enrolment and
/// `unlockLevel2WithBiometrics()`. Both go through a `.biometryCurrentSet`
/// Keychain item and a real Face ID / Touch ID prompt, which no simulator or CI
/// runner can satisfy — a test around them could only assert against a fake, and
/// the thing worth testing IS the Keychain. Same reason the file-backed
/// `VaultKeyBundle` paths are exercised through their pure step
/// (`VaultSession.level2AdoptedBundle`) rather than by writing a key bundle into
/// the shared App Group container a test run has no business touching.
final class Level2LifecycleTests: XCTestCase {

    private func key(_ byte: UInt8) -> [UInt8] { [UInt8](repeating: byte, count: 32) }

    // MARK: - Seal / open round trip

    func testSealedValueRoundTripsUnderTheSameKey() throws {
        let l2sk = key(0x11)

        let sealed = try SecretGuard.sealLevel2("hunter2", l2Key: l2sk)

        XCTAssertTrue(SecretGuard.isProtected(sealed))
        XCTAssertEqual(SecretGuard.scheme(of: sealed), .level2)
        // The whole point: the plaintext is nowhere in the stored value.
        XCTAssertFalse(sealed.contains("hunter2"))
        XCTAssertEqual(try SecretGuard.openLevel2(sealed, l2Key: l2sk), "hunter2")
    }

    func testEmptyAndUnicodeValuesSurviveTheRoundTrip() throws {
        let l2sk = key(0x22)
        for plaintext in ["", "  ", "mật khẩu chính", "🔐 pass / word"] {
            let sealed = try SecretGuard.sealLevel2(plaintext, l2Key: l2sk)
            XCTAssertEqual(try SecretGuard.openLevel2(sealed, l2Key: l2sk), plaintext)
        }
    }

    func testSealingTheSameValueTwiceProducesDifferentPayloads() throws {
        let l2sk = key(0x33)

        let first = try SecretGuard.sealLevel2("same", l2Key: l2sk)
        let second = try SecretGuard.sealLevel2("same", l2Key: l2sk)

        // AES-GCM nonces are per-seal; identical ciphertext would leak equality
        // between two protected fields.
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try SecretGuard.openLevel2(first, l2Key: l2sk), "same")
        XCTAssertEqual(try SecretGuard.openLevel2(second, l2Key: l2sk), "same")
    }

    // MARK: - Wrong key

    func testWrongKeyCannotOpenASealedValue() throws {
        let sealed = try SecretGuard.sealLevel2("hunter2", l2Key: key(0x44))

        XCTAssertThrowsError(try SecretGuard.openLevel2(sealed, l2Key: key(0x45)),
                             "a different L2SK must never open this payload")
    }

    func testShortKeyIsRejectedRatherThanPadded() {
        XCTAssertThrowsError(try SecretGuard.sealLevel2("x", l2Key: [1, 2, 3]))
    }

    func testTamperedCiphertextIsRejected() throws {
        let l2sk = key(0x55)
        let sealed = try SecretGuard.sealLevel2("hunter2", l2Key: l2sk)
        // Drop the last base64 character: still decodes to *a* payload shape or
        // fails outright — either way it must never open.
        let damaged = String(sealed.dropLast())

        XCTAssertThrowsError(try SecretGuard.openLevel2(damaged, l2Key: l2sk))
    }

    // MARK: - Malformed payloads

    func testPlainTextIsNotMistakenForAPayload() {
        for value in ["", "hunter2", "v2ghunter2", "V2G:abc"] {
            XCTAssertFalse(SecretGuard.isProtected(value))
            XCTAssertNil(SecretGuard.scheme(of: value))
            XCTAssertThrowsError(try SecretGuard.openLevel2(value, l2Key: key(0x66)))
        }
    }

    func testTaggedButUndecodableValuesThrowInsteadOfCrashing() {
        for value in ["v2g:", "v2g:!!!!", "v2g:" + Data("not json".utf8).base64EncodedString()] {
            XCTAssertThrowsError(try SecretGuard.openLevel2(value, l2Key: key(0x77)))
            XCTAssertNil(SecretGuard.scheme(of: value))
        }
    }

    func testCustomCodePayloadIsRefusedByTheLevel2Opener() async throws {
        // The two schemes share a payload envelope; opening one with the other's
        // key must be rejected as the type confusion it is, not left to fail as
        // an ordinary decrypt error.
        let sealed = try await SecretGuard.sealCustom(
            "hunter2", code: "1234",
            params: KdfParams(memoryCostKiB: 8, timeCost: 1, parallelism: 1))
        XCTAssertEqual(SecretGuard.scheme(of: sealed), .custom)

        XCTAssertThrowsError(try SecretGuard.openLevel2(sealed, l2Key: key(0x88))) { error in
            switch error {
            case SecretGuard.Failure.malformed: break
            default: XCTFail("expected a malformed-payload error, got \(error)")
            }
        }
    }

    // MARK: - Adopting a backup's Level-2 wrap

    private func bundle(withLevel2 wrap: Data?) -> VaultKeyBundle {
        VaultKeyBundle(version: VaultKeyBundle.currentVersion,
                       createdAt: Date(timeIntervalSince1970: 0),
                       kdfSalt: Data([1, 2, 3, 4]),
                       kdf: .constrained,
                       wrappedByPassword: Data([9, 9]),
                       recoverySalt: nil,
                       wrappedByRecovery: nil,
                       l2Salt: wrap == nil ? nil : Data([7, 7]),
                       l2Kdf: wrap == nil ? nil : .standard,
                       wrappedL2SK: wrap)
    }

    func testAdoptFillsAnAbsentLevel2Wrap() throws {
        let adopted = try XCTUnwrap(
            VaultSession.level2AdoptedBundle(from: bundle(withLevel2: nil),
                                             wrappedL2SK: Data([1, 1, 1]),
                                             salt: Data([2, 2]),
                                             kdf: .standard))

        XCTAssertEqual(adopted.wrappedL2SK, Data([1, 1, 1]))
        XCTAssertEqual(adopted.l2Salt, Data([2, 2]))
        XCTAssertEqual(adopted.l2Kdf, .standard)
        // Everything else is carried over untouched.
        XCTAssertEqual(adopted.wrappedByPassword, Data([9, 9]))
        XCTAssertEqual(adopted.kdf, .constrained)
    }

    func testAdoptNeverOverwritesAnExistingLevel2Wrap() {
        let local = bundle(withLevel2: Data([0xAA, 0xBB]))

        // Nil means "nothing to save" — the local Extra Password keeps working,
        // and clobbering its wrap would orphan this device's own sealed fields.
        XCTAssertNil(VaultSession.level2AdoptedBundle(from: local,
                                                      wrappedL2SK: Data([1, 1, 1]),
                                                      salt: Data([2, 2]),
                                                      kdf: .standard))
    }

    // MARK: - Swipe-delete gate

    /// A real key, so the gate's decrypt attempt is a genuine one.
    private static let key = [UInt8](repeating: 0x5A, count: 32)
    private static let foreignKey = [UInt8](repeating: 0x17, count: 32)

    /// Genuinely sealed under `Self.key` (the gate now tries to OPEN the payload,
    /// so a hand-built envelope with fake ciphertext would read as "cannot open").
    private func sealedLevel2Field() throws -> DynamicField {
        DynamicField(label: "Secret", kind: .password,
                     value: try SecretGuard.sealLevel2("hunter2", l2Key: Self.key),
                     protected: true, guard2: true)
    }

    /// A per-field custom-code payload. The editor never holds that code, so no
    /// Level-2 key makes it readable there.
    private func sealedCustomField() throws -> DynamicField {
        let payload = SecretGuard.Payload(v: 1, scheme: .custom, salt: nil, kdf: nil, ct: Data([1, 2]))
        let encoded = try JSONEncoder().encode(payload)
        return DynamicField(label: "Secret", kind: .password,
                            value: SecretGuard.tag + encoded.base64EncodedString(),
                            protected: true, guard2: true)
    }

    func testPlainFieldsAreAlwaysDeletable() {
        let plain = [DynamicField(label: "Username", kind: .username, value: "me@example.com")]

        XCTAssertFalse(ExtraProtectionDelete.blocks(plain, level2Key: nil))
        XCTAssertFalse(ExtraProtectionDelete.blocks(plain, level2Key: Self.key))
    }

    func testSealedFieldCannotBeSwipedAwayWhileLevel2IsLocked() throws {
        let fields = [try sealedLevel2Field()]

        XCTAssertTrue(ExtraProtectionDelete.blocks(fields, level2Key: nil))
        XCTAssertFalse(ExtraProtectionDelete.blocks(fields, level2Key: Self.key))
    }

    /// A restore can adopt a FOREIGN Level-2 wrap, leaving the session holding a
    /// key that opens nothing this device sealed earlier. The row renders locked,
    /// so the swipe must stay blocked too — "a key exists" is not "this opens".
    func testSealedFieldStaysBlockedUnderAForeignLevel2Key() throws {
        let fields = [try sealedLevel2Field()]

        XCTAssertTrue(ExtraProtectionDelete.blocks(fields, level2Key: Self.foreignKey))
    }

    func testCustomCodeFieldStaysBlockedEvenWithLevel2Unlocked() throws {
        let fields = [try sealedCustomField()]

        XCTAssertTrue(ExtraProtectionDelete.blocks(fields, level2Key: Self.key))
    }

    func testOneSealedFieldBlocksTheWholeBatch() throws {
        let fields = [
            DynamicField(label: "Username", kind: .username, value: "me@example.com"),
            try sealedLevel2Field(),
        ]

        XCTAssertTrue(ExtraProtectionDelete.blocks(fields, level2Key: nil))
    }
}
