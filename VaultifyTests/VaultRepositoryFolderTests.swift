import XCTest
@testable import Vaultify

/// Repository behavior for folders, counts, recents, and tags against a real
/// in-memory `VaultStore` + a session with a fixed Vault Key (no Argon2/keychain).
@MainActor
final class VaultRepositoryFolderTests: XCTestCase {

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    func testAddFolderPersistsAndAppears() throws {
        let repo = makeRepo()
        let id = try repo.addFolder(name: "Acme", icon: "ic_work", color: .blue)
        XCTAssertTrue(repo.folders.contains { $0.id == id && $0.name == "Acme" })
    }

    func testDeleteFolderReassignsMembersToUnfiled() throws {
        let repo = makeRepo()
        let id = try repo.addFolder(name: "Acme", icon: "ic_work", color: .blue)
        try repo.add(VaultItem(category: .login, title: "GH", folderId: id))
        XCTAssertEqual(repo.itemCount(for: id), 1)
        try repo.deleteFolder(repo.folders.first { $0.id == id }!)
        XCTAssertFalse(repo.folders.contains { $0.id == id })  // folder gone
        XCTAssertEqual(repo.items.count, 1)                    // item NOT deleted
        XCTAssertNil(repo.items.first?.folderId)               // moved to Unfiled
    }

    func testItemCountExcludesTrashed() throws {
        let repo = makeRepo()
        let id = try repo.addFolder(name: "Acme", icon: "ic_work", color: .blue)
        for i in 0..<3 { try repo.add(VaultItem(category: .login, title: "i\(i)", folderId: id)) }
        XCTAssertEqual(repo.itemCount(for: id), 3)
        try repo.moveToTrash(repo.items.first { $0.folderId == id }!)
        XCTAssertEqual(repo.itemCount(for: id), 2)
    }

    func testMarkUsedDoesNotReseal() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "GH"))
        let item = repo.items.first!
        let before = repo.store.record(id: item.id)!
        let sealedBefore = before.sealed, updatedBefore = before.updatedAt, dirtyBefore = before.dirty
        repo.markUsed(item)
        let after = repo.store.record(id: item.id)!
        XCTAssertEqual(after.sealed, sealedBefore)      // not re-sealed
        XCTAssertEqual(after.updatedAt, updatedBefore)  // not bumped
        XCTAssertEqual(after.dirty, dirtyBefore)        // not marked dirty
        XCTAssertNotNil(after.lastUsedAt)               // timing recorded
    }

    func testRecentlyUsedOrdering() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "A"))
        try repo.add(VaultItem(category: .login, title: "B"))
        repo.markUsed(repo.items.first { $0.title == "A" }!)
        repo.markUsed(repo.items.first { $0.title == "B" }!)   // B most recent
        let recents = repo.recentlyUsed(limit: 5)
        XCTAssertEqual(recents.first?.title, "B")
        XCTAssertEqual(Set(recents.map(\.title)), ["A", "B"])
    }

    func testAllTagsMergeCaseInsensitively() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "A", tags: ["work", "aws"]))
        try repo.add(VaultItem(category: .login, title: "B", tags: ["work", "AWS"]))
        let tags = repo.allTags()
        XCTAssertEqual(tags.first { $0.tag.caseInsensitiveCompare("work") == .orderedSame }?.count, 2)
        XCTAssertEqual(tags.first { $0.tag.caseInsensitiveCompare("aws") == .orderedSame }?.count, 2)
        XCTAssertEqual(repo.items(withTag: "aws").count, 2)
    }
}
