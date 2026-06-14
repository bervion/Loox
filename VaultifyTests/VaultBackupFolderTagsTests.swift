import XCTest
@testable import Vaultify

/// CSV + encrypted-backup round-trips for folders/tags, including back-compat
/// with files that predate the new columns/keys.
final class VaultBackupFolderTagsTests: XCTestCase {

    func testCSVExportIncludesFolderAndTags() {
        let item = VaultItem(category: .login, title: "GitHub", folderId: "f1",
                             fields: [DynamicField(label: "Username", kind: .username, value: "octocat")],
                             tags: ["dev", "work"])
        let csv = VaultBackup.makeCSV([item], folderNames: ["f1": "Acme"])
        let header = csv.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(header.contains("folder"))
        XCTAssertTrue(header.contains("tags"))
        XCTAssertTrue(csv.contains("Acme"))
        XCTAssertTrue(csv.contains("dev; work"))
    }

    func testCSVImportReadsFolderAndTags() {
        let csv = "name,username,password,folder,tags\nGitHub,octocat,pw,Acme,dev; work"
        let rows = VaultBackup.parseCSVWithFolders(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].folderName, "Acme")
        XCTAssertEqual(rows[0].item.tags, ["dev", "work"])
    }

    func testLegacyCSVWithoutNewColumnsStillImports() {
        let csv = "name,username,password\nGmail,me@x.com,pw"
        let rows = VaultBackup.parseCSVWithFolders(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].folderName)
        XCTAssertEqual(rows[0].item.tags, [])
    }

    /// Back-compat: an encrypted backup written before folders/tags has no
    /// `tags`/`folderName` keys and must still decode.
    func testLegacyPortableItemDecodes() throws {
        let legacy = #"[{"title":"Gmail","category":"login","fields":[]}]"#
        let items = try JSONDecoder().decode([VaultBackup.PortableItem].self, from: Data(legacy.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].tags, [])
        XCTAssertNil(items[0].folderName)
    }
}
