import XCTest
@testable import Vaultify

/// Codec + crypto round-trips for the organization model. The legacy-decode case
/// is the data-safety gate: existing sealed blobs (written before `tags`) MUST
/// still open.
final class OrganizationCodecTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    /// CRITICAL: a sealed `ItemSecret` written before `tags` existed (no `tags`
    /// key) must decode to `tags == []`, not fail — otherwise every pre-existing
    /// item would look corrupt.
    func testLegacyItemSecretDecodesWithoutTags() throws {
        let legacy = #"{"title":"Gmail","category":"login","folderId":null,"fields":[]}"#
        let secret = try JSONDecoder().decode(ItemSecret.self, from: Data(legacy.utf8))
        XCTAssertEqual(secret.title, "Gmail")
        XCTAssertEqual(secret.category, .login)
        XCTAssertNil(secret.folderId)
        XCTAssertEqual(secret.tags, [])
    }

    func testItemSecretSealRoundTripPreservesTagsAndFolder() throws {
        let item = VaultItem(category: .login, title: "AWS", folderId: "folder-1",
                             fields: [DynamicField(label: "Password", kind: .password,
                                                   value: "s3cret", protected: true)],
                             tags: ["work", "infra"])
        let sealed = try AESGCM.seal(JSONEncoder().encode(item.secret), key: testKey)
        let decoded = try JSONDecoder().decode(ItemSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertEqual(decoded.title, "AWS")
        XCTAssertEqual(decoded.folderId, "folder-1")
        XCTAssertEqual(decoded.tags, ["work", "infra"])
        XCTAssertEqual(decoded.fields.count, 1)
    }

    func testFolderSecretSealRoundTrip() throws {
        let folder = Folder(name: "Acme Corp", iconAsset: "ic_work", color: .green)
        let sealed = try AESGCM.seal(JSONEncoder().encode(folder.secret), key: testKey)
        let decoded = try JSONDecoder().decode(FolderSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertEqual(decoded.name, "Acme Corp")
    }

    func testFolderColorPaletteStable() {
        XCTAssertEqual(FolderColor.palette.count, 10)
        for c in FolderColor.allCases {
            XCTAssertEqual(FolderColor(rawValue: c.rawValue), c)
            XCTAssertNotEqual(c.light, 0)
            XCTAssertNotEqual(c.dark, 0)
        }
        XCTAssertNil(FolderColor(rawValue: "not-a-color"))
    }
}
