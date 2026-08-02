import XCTest
@testable import Vaultify

/// Legacy-role inference is conservative: authoritative roles appear only
/// where category + kind + cardinality PROVE them; ambiguous or label-keyed
/// shapes stay role-less; existing semantics and unknown categories are
/// untouched; values are never modified.
final class LegacySemanticsInferenceTests: XCTestCase {

    func testLoginFieldsGainKindProvableRoles() {
        var item = VaultItem(category: .login, title: "GitHub",
                             fields: ItemCategory.login.fieldTemplate)
        item.fields.append(DynamicField(label: "2FA", kind: .totp, value: "SEED"))
        item.fields.append(DynamicField(label: "Site", kind: .url, value: "github.com"))
        let inferred = LegacySemanticsInference.applied(to: item)
        XCTAssertEqual(inferred.semantics?.kindID, .login)
        XCTAssertEqual(inferred.fields.first { $0.kind == .username }?.roleID, .username)
        XCTAssertEqual(inferred.fields.first { $0.kind == .password }?.roleID, .password)
        XCTAssertEqual(inferred.fields.first { $0.kind == .totp }?.roleID, .totp)
        XCTAssertEqual(inferred.fields.first { $0.kind == .url }?.roleID, .website)
        // Values byte-for-byte unchanged.
        XCTAssertEqual(inferred.fields.map(\.value), item.fields.map(\.value))
    }

    func testSSHTemplateShapeGainsKeyRoles() {
        let item = VaultItem(category: .sshKey, title: "Deploy",
                             fields: ItemCategory.sshKey.fieldTemplate)
        let inferred = LegacySemanticsInference.applied(to: item)
        XCTAssertEqual(inferred.semantics?.kindID, .sshKey)
        XCTAssertEqual(inferred.fields[0].roleID, .sshPrivateKey)
        XCTAssertEqual(inferred.fields[1].roleID, .sshPublicKey)
    }

    func testModifiedSSHShapeStaysRoleLess() {
        // TWO protected multilines: which is the private key is no longer
        // provable — neither gets the role.
        var fields = ItemCategory.sshKey.fieldTemplate
        fields.append(DynamicField(label: "Backup key", kind: .multiline, value: "x",
                                   protected: true))
        let item = VaultItem(category: .sshKey, title: "K", fields: fields)
        let inferred = LegacySemanticsInference.applied(to: item)
        XCTAssertNil(inferred.fields[0].roleID)
        XCTAssertNil(inferred.fields.last?.roleID)
        // The public key (still unique) keeps its provable role.
        XCTAssertEqual(inferred.fields[1].roleID, .sshPublicKey)
    }

    func testLabelKeyedCategoriesGetNoAuthoritativeRoles() {
        for category in [ItemCategory.card, .identity, .securityQuestions, .custom] {
            let item = VaultItem(category: category, title: "T",
                                 fields: category.fieldTemplate)
            let inferred = LegacySemanticsInference.applied(to: item)
            XCTAssertTrue(inferred.fields.allSatisfy { $0.roleID == nil },
                          "\(category): labels are editable — nothing is provable")
        }
    }

    func testAlreadySemanticItemsAreUntouched() {
        var item = VaultItem(category: .custom, title: "API", fields: [])
        item.semantics = ItemSemantics(kindID: .apiSecret, templateVersion: 1)
        let result = LegacySemanticsInference.applied(to: item)
        XCTAssertEqual(result, item)
    }

    func testUnknownCategoryAndUnsupportedSchemaAreUntouched() {
        var unknown = VaultItem(category: .custom, title: "?", fields: [])
        unknown.unknownCategoryRaw = "futureCat"
        XCTAssertEqual(LegacySemanticsInference.applied(to: unknown), unknown)

        var future = VaultItem(category: .login, title: "F", fields: [])
        future.semantics = ItemSemantics(schemaVersion: ItemSemantics.supported + 1)
        XCTAssertEqual(LegacySemanticsInference.applied(to: future), future)
    }

    func testUnknownKindFieldNeverGainsARole() {
        let json = Data("""
        {"id":"f1","label":"X","kind":"hologram","value":"v","protected":true}
        """.utf8)
        let alien = try! JSONDecoder().decode(DynamicField.self, from: json)
        let item = VaultItem(category: .login, title: "L", fields: [alien])
        let inferred = LegacySemanticsInference.applied(to: item)
        XCTAssertNil(inferred.fields[0].roleID)
    }
}
