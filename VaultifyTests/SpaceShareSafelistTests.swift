import XCTest
@testable import Vaultify

/// Part 2 (Family full-group sharing, A2): `SpaceShareSafelist` — the A0-6
/// field-instance safelist a blanket Space share uses to decide which fields
/// of a login item it may hand over with no per-field owner decision.
/// Exhaustive over every dimension the frozen contract names: each eligible
/// kind, `protected`, `guard2`, a mixed item, non-login categories, and the
/// empty cases (no fields at all, or fields but none eligible).
final class SpaceShareSafelistTests: XCTestCase {

    private func field(id: String = UUID().uuidString, kind: FieldKind, value: String = "v",
                       protected: Bool? = nil, guard2: Bool? = nil) -> DynamicField {
        DynamicField(id: id, label: kind.defaultLabel, kind: kind, value: value,
                    protected: protected, guard2: guard2)
    }

    private func item(category: ItemCategory = .login, fields: [DynamicField]) -> VaultItem {
        VaultItem(category: category, title: "Test Item", fields: fields)
    }

    // MARK: Each eligible kind, unprotected — included

    func testEachEligibleKindAloneIsShared() {
        for kind: FieldKind in [.username, .password, .url, .email] {
            let f = field(kind: kind, protected: false)
            let result = SpaceShareSafelist.shareableFields(for: item(fields: [f]))
            XCTAssertEqual(result, [f.id: .value(.shared)], "kind \(kind) should be eligible when unprotected")
        }
    }

    // MARK: Each ineligible kind — the item becomes fully ineligible when it's the only field

    func testEachIneligibleKindAloneMakesTheItemIneligible() {
        for kind: FieldKind in [.text, .totp, .number, .phone, .multiline, .monospace, .date, .fileRef] {
            let f = field(kind: kind, protected: false)
            let result = SpaceShareSafelist.shareableFields(for: item(fields: [f]))
            XCTAssertNil(result, "kind \(kind) alone must yield no eligible fields")
        }
    }

    // MARK: protected

    func testMaskedPasswordIsSharedBecauseMaskingIsNotExtraProtection() {
        // Password defaults to protected: true at creation (masked display).
        // Masking is a DISPLAY concern, not a sharing signal — a family login
        // share must include the password. Only guard2/SecretGuard excludes.
        let password = field(kind: .password, protected: true)
        let result = SpaceShareSafelist.shareableFields(for: item(fields: [password]))
        XCTAssertEqual(result, [password.id: .value(.shared)])
    }

    func testUnprotectedPasswordIsIncluded() {
        let password = field(kind: .password, protected: false)
        let result = SpaceShareSafelist.shareableFields(for: item(fields: [password]))
        XCTAssertEqual(result, [password.id: .value(.shared)])
    }

    // MARK: guard2 (SecretGuard Level-2)

    func testGuard2FieldIsExcludedEvenWhenNotProtected() {
        let url = field(kind: .url, protected: false, guard2: true)
        XCTAssertNil(SpaceShareSafelist.shareableFields(for: item(fields: [url])))
    }

    func testSecretGuardTaggedValueIsExcludedEvenWithoutTheGuard2Flag() {
        // Defense in depth (mirrors WebExtensionReader.releasable): the
        // SecretGuard tag on the VALUE excludes the field even if the
        // `guard2` flag itself is desynced (nil/false) — never relied on alone.
        let tagged = field(kind: .email, value: "\(SecretGuard.tag)garbage",
                           protected: false, guard2: false)
        XCTAssertNil(SpaceShareSafelist.shareableFields(for: item(fields: [tagged])))
    }

    // MARK: fileRef / attachment

    func testFileRefFieldIsExcluded() {
        let attachment = field(kind: .fileRef, protected: false)
        XCTAssertNil(SpaceShareSafelist.shareableFields(for: item(fields: [attachment])))
    }

    // MARK: Mixed item

    func testMixedItemIncludesOnlyTheTrulyEligibleFields() {
        let username = field(kind: .username, protected: false)
        let password = field(kind: .password, protected: true) // masked, but shared (masking ≠ extra-protection)
        let url = field(kind: .url, protected: false)
        let note = field(kind: .multiline, protected: false)   // wrong kind → excluded
        let email = field(kind: .email, protected: false, guard2: true) // guard2 → excluded

        let result = SpaceShareSafelist.shareableFields(
            for: item(fields: [username, password, url, note, email]))

        XCTAssertEqual(result, [username.id: .value(.shared),
                                password.id: .value(.shared),
                                url.id: .value(.shared)])
    }

    // MARK: Non-login categories

    func testNonLoginCategoryIsAlwaysIneligibleEvenWithMatchingFieldKinds() {
        for category: ItemCategory in [.note, .card, .identity, .sshKey,
                                        .recoveryCodes, .securityQuestions, .custom] {
            let email = field(kind: .email, protected: false)
            let result = SpaceShareSafelist.shareableFields(for: item(category: category, fields: [email]))
            XCTAssertNil(result, "category \(category) must never be safelisted regardless of field kind")
        }
    }

    // MARK: Empty

    func testLoginWithNoFieldsIsIneligible() {
        XCTAssertNil(SpaceShareSafelist.shareableFields(for: item(fields: [])))
    }

    func testLoginWithOnlyIneligibleFieldsIsIneligible() {
        let fields = [field(kind: .totp, protected: false), field(kind: .multiline, protected: false)]
        XCTAssertNil(SpaceShareSafelist.shareableFields(for: item(fields: fields)))
    }

    // MARK: Result is keyed by field id, not label

    func testResultIsKeyedByFieldIdNotLabel() {
        let f = DynamicField(id: "custom-id-123", label: "Site", kind: .url, value: "https://x.com",
                            protected: false)
        let result = SpaceShareSafelist.shareableFields(for: item(fields: [f]))
        XCTAssertEqual(result?.keys.first, "custom-id-123")
    }
}
