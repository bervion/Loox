import XCTest
@testable import Vaultify

/// Cross-version category safety: a sealed payload naming a category this
/// build does not know must (1) still decode — never a silently missing item,
/// (2) present as generic `.custom`, and (3) re-encode with the ORIGINAL raw
/// value so a round-trip through this build is lossless.
final class UnknownCategoryRoundTripTests: XCTestCase {

    private func secretJSON(category: String) -> Data {
        Data("""
        {"title":"CI Deploy Key","category":"\(category)",
         "fields":[{"id":"f1","label":"Value","kind":"text","value":"v","protected":false}],
         "tags":["infra"]}
        """.utf8)
    }

    func testUnknownCategoryDecodesAsCustomAndPreservesRaw() throws {
        let secret = try JSONDecoder().decode(ItemSecret.self, from: secretJSON(category: "developerVault"))
        XCTAssertEqual(secret.category, .custom)
        XCTAssertEqual(secret.unknownCategoryRaw, "developerVault")
        XCTAssertEqual(secret.title, "CI Deploy Key")
        XCTAssertEqual(secret.fields.count, 1)
    }

    func testUnknownCategoryReEncodesOriginalRawValue() throws {
        let secret = try JSONDecoder().decode(ItemSecret.self, from: secretJSON(category: "developerVault"))
        let reEncoded = try JSONEncoder().encode(secret)
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any])
        XCTAssertEqual(raw["category"] as? String, "developerVault",
                       "re-seal must write the original category, never the fallback")
    }

    func testKnownCategoryRoundTripsUnchanged() throws {
        let secret = try JSONDecoder().decode(ItemSecret.self, from: secretJSON(category: "sshKey"))
        XCTAssertEqual(secret.category, .sshKey)
        XCTAssertNil(secret.unknownCategoryRaw)
        let reEncoded = try JSONEncoder().encode(secret)
        let round = try JSONDecoder().decode(ItemSecret.self, from: reEncoded)
        XCTAssertEqual(round.category, .sshKey)
        XCTAssertNil(round.unknownCategoryRaw)
    }

    /// The in-memory aggregate carries the preserved raw through an edit-save
    /// cycle (`VaultItem.secret` is what the repository re-seals).
    func testVaultItemSecretCarriesUnknownRawThroughEdit() throws {
        let secret = try JSONDecoder().decode(ItemSecret.self, from: secretJSON(category: "futureType"))
        var item = VaultItem(category: secret.category, title: secret.title, fields: secret.fields)
        item.unknownCategoryRaw = secret.unknownCategoryRaw
        item.title = "Renamed by user"
        let resealed = try JSONEncoder().encode(item.secret)
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: resealed) as? [String: Any])
        XCTAssertEqual(raw["category"] as? String, "futureType")
        XCTAssertEqual(raw["title"] as? String, "Renamed by user")
    }

    // MARK: Portable backup

    func testBackupRoundTripPreservesUnknownCategory() async throws {
        var item = VaultItem(category: .custom, title: "Future item",
                             fields: [DynamicField(label: "Field", kind: .text, value: "x")])
        item.unknownCategoryRaw = "quantumCredential"
        let data = try await VaultBackup.exportEncrypted([item], passphrase: "correct horse battery")
        let imported = try await VaultBackup.importEncrypted(data, passphrase: "correct horse battery")
        let restored = try XCTUnwrap(imported.first?.item)
        XCTAssertEqual(restored.category, .custom)
        XCTAssertEqual(restored.unknownCategoryRaw, "quantumCredential")
    }

    func testBackupKnownCategoryHasNoUnknownRaw() async throws {
        let item = VaultItem(category: .note, title: "Note",
                             fields: [DynamicField(label: "Note", kind: .multiline, value: "hello")])
        let data = try await VaultBackup.exportEncrypted([item], passphrase: "correct horse battery")
        let imported = try await VaultBackup.importEncrypted(data, passphrase: "correct horse battery")
        let restored = try XCTUnwrap(imported.first?.item)
        XCTAssertEqual(restored.category, .note)
        XCTAssertNil(restored.unknownCategoryRaw)
    }
}
