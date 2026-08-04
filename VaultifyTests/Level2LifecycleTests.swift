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

    // MARK: - Argon2 parameter policy

    func testShippedProfilesAreWithinPolicy() {
        XCTAssertTrue(KdfParams.standard.isWithinPolicy)
        XCTAssertTrue(KdfParams.constrained.isWithinPolicy)
    }

    func testPolicyAcceptsItsOwnBoundaries() {
        XCTAssertTrue(KdfParams(memoryCostKiB: KdfParams.maxMemoryCostKiB,
                                timeCost: KdfParams.maxTimeCost,
                                parallelism: KdfParams.maxParallelism).isWithinPolicy)
        // Argon2's own floor: 8 KiB overall, 8 blocks per lane, one iteration.
        XCTAssertTrue(KdfParams(memoryCostKiB: 8, timeCost: 1, parallelism: 1).isWithinPolicy)
    }

    func testPolicyRejectsParametersThatWouldStallOrOOM() {
        // The memory band: jetsam kills the process before Argon2 returns.
        XCTAssertFalse(KdfParams(memoryCostKiB: 2 * 1024 * 1024, timeCost: 3,
                                 parallelism: 4).isWithinPolicy)
        XCTAssertFalse(KdfParams(memoryCostKiB: KdfParams.maxMemoryCostKiB + 1, timeCost: 3,
                                 parallelism: 4).isWithinPolicy)
        // The time band: a permanent spinner on a pegged core.
        XCTAssertFalse(KdfParams(memoryCostKiB: 64 * 1024, timeCost: .max,
                                 parallelism: 4).isWithinPolicy)
        XCTAssertFalse(KdfParams(memoryCostKiB: 64 * 1024, timeCost: KdfParams.maxTimeCost + 1,
                                 parallelism: 4).isWithinPolicy)
        // Lanes beyond the ceiling, including a value whose 8-blocks-per-lane
        // floor would overflow if it were multiplied out first.
        XCTAssertFalse(KdfParams(memoryCostKiB: 64 * 1024, timeCost: 3,
                                 parallelism: KdfParams.maxParallelism + 1).isWithinPolicy)
        XCTAssertFalse(KdfParams(memoryCostKiB: 64 * 1024, timeCost: 3,
                                 parallelism: .max).isWithinPolicy)
    }

    func testPolicyRejectsParametersArgon2WouldRefuse() {
        // Each of these makes Argon2 return an error that reaches the user as
        // "couldn't decrypt", indistinguishable from a wrong password.
        XCTAssertFalse(KdfParams(memoryCostKiB: 0, timeCost: 3, parallelism: 4).isWithinPolicy)
        XCTAssertFalse(KdfParams(memoryCostKiB: 64 * 1024, timeCost: 0, parallelism: 4).isWithinPolicy)
        XCTAssertFalse(KdfParams(memoryCostKiB: 64 * 1024, timeCost: 3, parallelism: 0).isWithinPolicy)
        // 8 KiB total is fine for one lane, not for four.
        XCTAssertFalse(KdfParams(memoryCostKiB: 8, timeCost: 1, parallelism: 4).isWithinPolicy)
    }

    func testSaltPolicyMatchesArgon2Floor() {
        XCTAssertFalse(KdfParams.isAcceptableSalt(Data()))
        XCTAssertFalse(KdfParams.isAcceptableSalt(Data([2, 2])))
        XCTAssertTrue(KdfParams.isAcceptableSalt(Data(repeating: 2, count: KdfParams.minSaltLength)))
        XCTAssertTrue(KdfParams.isAcceptableSalt(Data(repeating: 2, count: 16)))
    }

    // MARK: - Validating decoder

    private func kdfJSON(memory: UInt64, time: UInt64, lanes: UInt64) -> Data {
        Data("""
        {"memoryCostKiB":\(memory),"timeCost":\(time),"parallelism":\(lanes)}
        """.utf8)
    }

    func testInPolicyParametersRoundTripThroughTheCodec() throws {
        for params in [KdfParams.standard, .constrained] {
            let decoded = try JSONDecoder().decode(KdfParams.self,
                                                   from: JSONEncoder().encode(params))
            XCTAssertEqual(decoded, params)
        }
    }

    func testOutOfPolicyParametersFailToDecode() {
        // 2 GiB, and a time cost that would run for years — both arrive from a
        // file whose author chose them, so they must never reach Argon2.
        XCTAssertThrowsError(try JSONDecoder().decode(
            KdfParams.self, from: kdfJSON(memory: 2 * 1024 * 1024, time: 3, lanes: 4)))
        XCTAssertThrowsError(try JSONDecoder().decode(
            KdfParams.self, from: kdfJSON(memory: 65536, time: 4_000_000, lanes: 4)))
        XCTAssertThrowsError(try JSONDecoder().decode(
            KdfParams.self, from: kdfJSON(memory: 65536, time: 3, lanes: 1_000_000)))
        // Beyond UInt32 entirely — rejected by the number decode itself.
        XCTAssertThrowsError(try JSONDecoder().decode(
            KdfParams.self, from: kdfJSON(memory: 8_000_000_000, time: 3, lanes: 4)))
    }

    /// The reason the check lives in the decoder: it fires at the wire, inside
    /// whatever envelope carries the parameters, without every reader having to
    /// remember to validate.
    func testAHostileBackupEnvelopeIsRejectedBeforeAnyDerivation() {
        let envelope = Data("""
        {"version":2,"salt":"\(Data(repeating: 1, count: 16).base64EncodedString())",
         "kdf":{"memoryCostKiB":2097152,"timeCost":3,"parallelism":4},
         "sealed":"\(Data([1, 2, 3]).base64EncodedString())"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(VaultBackup.EncryptedBackup.self,
                                                      from: envelope))
    }

    func testAHostileLevel2WrapIsRejectedBeforeItCanBePersisted() {
        let wrap = Data("""
        {"wrappedL2SK":"\(Data(repeating: 3, count: 60).base64EncodedString())",
         "salt":"\(Data(repeating: 1, count: 16).base64EncodedString())",
         "kdf":{"memoryCostKiB":262144,"timeCost":3,"parallelism":4}}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(VaultBackup.Level2Wrap.self, from: wrap))
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

    /// A wrap shaped like a real one: AES-GCM over a 32-byte key, 16-byte salt.
    private let foreignWrap = Data(repeating: 0xC3, count: 60)
    private let foreignSalt = Data(repeating: 0x2B, count: 16)

    func testAdoptFillsAnAbsentLevel2Wrap() throws {
        let adopted = try XCTUnwrap(
            VaultSession.level2AdoptedBundle(from: bundle(withLevel2: nil),
                                             wrappedL2SK: foreignWrap,
                                             salt: foreignSalt,
                                             kdf: .standard))

        XCTAssertEqual(adopted.wrappedL2SK, foreignWrap)
        XCTAssertEqual(adopted.l2Salt, foreignSalt)
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
                                                      wrappedL2SK: foreignWrap,
                                                      salt: foreignSalt,
                                                      kdf: .standard))
    }

    /// The persisted escalation: adopted parameters are written into this
    /// device's own key bundle, and every later reveal derives with them with no
    /// attacker file in play. Extra Protection cannot be turned off without the
    /// foreign password, so a bad adoption is not undoable.
    func testAdoptRefusesAnOutOfPolicyKdfEvenWithNoLocalWrap() {
        let hostile = KdfParams(memoryCostKiB: 2 * 1024 * 1024, timeCost: 3, parallelism: 4)

        XCTAssertNil(VaultSession.level2AdoptedBundle(from: bundle(withLevel2: nil),
                                                      wrappedL2SK: foreignWrap,
                                                      salt: foreignSalt,
                                                      kdf: hostile))
        XCTAssertFalse(VaultSession.isAdoptableLevel2Wrap(wrappedL2SK: foreignWrap,
                                                          salt: foreignSalt,
                                                          kdf: hostile))
    }

    func testAdoptRefusesASaltArgon2CannotUse() {
        for salt in [Data(), Data([2, 2])] {
            XCTAssertNil(VaultSession.level2AdoptedBundle(from: bundle(withLevel2: nil),
                                                          wrappedL2SK: foreignWrap,
                                                          salt: salt,
                                                          kdf: .standard),
                         "a \(salt.count)-byte salt only ever yields ARGON2_SALT_TOO_SHORT")
        }
    }

    func testAdoptRefusesAnEmptyWrap() {
        // It would leave `hasLevel2` true forever with no password able to open
        // it, and no way to remove it.
        XCTAssertNil(VaultSession.level2AdoptedBundle(from: bundle(withLevel2: nil),
                                                      wrappedL2SK: Data(),
                                                      salt: foreignSalt,
                                                      kdf: .standard))
    }

    // MARK: - Adoption outcome reported to the caller

    func testAdoptionOutcomeDistinguishesItsThreeEndings() {
        let hostile = KdfParams(memoryCostKiB: 2 * 1024 * 1024, timeCost: 3, parallelism: 4)

        XCTAssertEqual(VaultSession.level2Adoption(for: bundle(withLevel2: nil),
                                                   wrappedL2SK: foreignWrap,
                                                   salt: foreignSalt, kdf: .standard),
                       .adopted)
        // Restoring your own backup onto a device that already has a different
        // Extra Password: every sealed field imports as unopenable ciphertext,
        // so "imported successfully" would be a lie.
        XCTAssertEqual(VaultSession.level2Adoption(for: bundle(withLevel2: Data([0xAA])),
                                                   wrappedL2SK: foreignWrap,
                                                   salt: foreignSalt, kdf: .standard),
                       .skippedDeviceHasOwnWrap)
        XCTAssertEqual(VaultSession.level2Adoption(for: bundle(withLevel2: nil),
                                                   wrappedL2SK: foreignWrap,
                                                   salt: foreignSalt, kdf: hostile),
                       .refusedInvalidPolicy)
        XCTAssertEqual(VaultSession.level2Adoption(for: bundle(withLevel2: nil),
                                                   wrappedL2SK: foreignWrap,
                                                   salt: Data([2, 2]), kdf: .standard),
                       .refusedInvalidPolicy)
    }

    /// A refusal outranks the collision: with nothing safe to write, "this
    /// device keeps its own Extra Password" would describe the wrong reason.
    func testPolicyRefusalIsReportedEvenWhenTheDeviceAlsoHasItsOwnWrap() {
        let hostile = KdfParams(memoryCostKiB: 2 * 1024 * 1024, timeCost: 3, parallelism: 4)

        XCTAssertEqual(VaultSession.level2Adoption(for: bundle(withLevel2: Data([0xAA])),
                                                   wrappedL2SK: foreignWrap,
                                                   salt: foreignSalt, kdf: hostile),
                       .refusedInvalidPolicy)
    }

    func testAdoptionWithoutAKeyBundleIsRefusedRatherThanReportedAsAdopted() {
        XCTAssertEqual(VaultSession.level2Adoption(for: nil,
                                                   wrappedL2SK: foreignWrap,
                                                   salt: foreignSalt, kdf: .standard),
                       .refusedInvalidPolicy)
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

    // MARK: - Turn-off transaction (preflight → persist → verify)

    private func item(_ id: String, fields: [DynamicField],
                      archived: Bool = false, trashed: Bool = false) -> VaultItem {
        var item = VaultItem(id: id, category: .login, title: id, fields: fields)
        item.archived = archived
        if trashed { item.trashedAt = Date(timeIntervalSince1970: 1) }
        return item
    }

    func testUnsealedRewritesEveryLevel2FieldIncludingArchivedAndTrashed() throws {
        let live = item("live", fields: [try sealedLevel2Field()])
        let archived = item("archived", fields: [try sealedLevel2Field()], archived: true)
        let trashed = item("trashed", fields: [try sealedLevel2Field()], trashed: true)
        let untouched = item("plain", fields: [DynamicField(label: "U", kind: .username, value: "me")])

        let out = try Level2Disable.unsealed([live, archived, trashed, untouched], l2Key: Self.key)

        // Only items that actually carried a seal come back — and all of them do,
        // regardless of live/archived/trashed placement.
        XCTAssertEqual(Set(out.map(\.id)), ["live", "archived", "trashed"])
        for rewritten in out {
            XCTAssertEqual(rewritten.fields[0].value, "hunter2")
            XCTAssertFalse(rewritten.fields[0].isExtraProtected)
        }
    }

    func testUnsealedAbortsOnAForeignKeyWithoutPartialResults() throws {
        // First item opens fine, second is sealed under a different L2SK — the
        // preflight must throw (so the caller never starts writing), not return
        // a half-converted batch.
        let mine = item("mine", fields: [try sealedLevel2Field()])
        let foreignField = DynamicField(
            label: "Secret", kind: .password,
            value: try SecretGuard.sealLevel2("other", l2Key: Self.foreignKey),
            protected: true, guard2: true)
        let foreign = item("foreign", fields: [foreignField])

        XCTAssertThrowsError(try Level2Disable.unsealed([mine, foreign], l2Key: Self.key))
    }

    func testUnsealedIsIdempotentAcrossARetry() throws {
        // A crash between persist and verify leaves some items already plaintext.
        // The retry must skip them (no throw, no rewrite) and finish the rest.
        let done = item("done", fields: [DynamicField(label: "Secret", kind: .password,
                                                      value: "hunter2", protected: true)])
        let pending = item("pending", fields: [try sealedLevel2Field()])

        let out = try Level2Disable.unsealed([done, pending], l2Key: Self.key)

        XCTAssertEqual(out.map(\.id), ["pending"])
    }

    func testLeftoverScanCatchesAnySurvivingCiphertext() throws {
        let clean = item("clean", fields: [DynamicField(label: "U", kind: .username, value: "me")])
        let sealed = item("sealed", fields: [try sealedLevel2Field()], trashed: true)

        XCTAssertFalse(Level2Disable.hasSealedLeftovers([clean]))
        XCTAssertTrue(Level2Disable.hasSealedLeftovers([clean, sealed]))
    }
}
