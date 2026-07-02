import XCTest
@testable import Vaultify

/// Pin / archive / useCount behavior + search and item lookup for the nav redesign.
@MainActor
final class NavRedesignTests: XCTestCase {

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    func testTogglePin() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "GH"))
        let item = repo.items.first!
        XCTAssertFalse(item.pinned)
        repo.togglePin(item)
        XCTAssertEqual(repo.item(id: item.id)?.pinned, true)
        XCTAssertEqual(repo.pinnedItems.count, 1)
        repo.togglePin(item)
        XCTAssertTrue(repo.pinnedItems.isEmpty)
    }

    func testArchiveMovesItemOutOfLiveListsAndBack() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "A"))
        try repo.add(VaultItem(category: .login, title: "B"))
        let a = repo.items.first { $0.title == "A" }!
        repo.archive(a)
        XCTAssertFalse(repo.items.contains { $0.id == a.id })   // out of live items
        XCTAssertTrue(repo.archived.contains { $0.id == a.id }) // in archive
        XCTAssertEqual(repo.count(forCategory: .login), 1)      // counts exclude archived
        repo.unarchive(a)
        XCTAssertTrue(repo.items.contains { $0.id == a.id })
        XCTAssertTrue(repo.archived.isEmpty)
    }

    func testMarkUsedBumpsUseCountAndRanksFrequentlyUsed() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "A"))
        try repo.add(VaultItem(category: .login, title: "B"))
        let a = repo.items.first { $0.title == "A" }!
        repo.markUsed(a); repo.markUsed(a)
        repo.markUsed(repo.items.first { $0.title == "B" }!)
        XCTAssertEqual(repo.item(id: a.id)?.useCount, 2)
        XCTAssertEqual(repo.frequentlyUsed(limit: 5).first?.title, "A")
    }

    func testRecentlyCreatedOrder() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "old", createdAt: .now.addingTimeInterval(-100)))
        try repo.add(VaultItem(category: .login, title: "new", createdAt: .now))
        XCTAssertEqual(repo.recentlyCreated(limit: 5).first?.title, "new")
    }

    func testItemLookupIncludesArchived() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "A"))
        let a = repo.items.first!
        repo.archive(a)
        XCTAssertNotNil(repo.item(id: a.id))   // resolves even though excluded from items
    }

    func testSearchMatchesSpaceName() throws {
        let repo = makeRepo()
        let work = try repo.addFolder(name: "Work", icon: "ic_work", color: .blue)
        try repo.add(VaultItem(category: .login, title: "GitHub", folderId: work))
        try repo.add(VaultItem(category: .login, title: "GitHub", folderId: nil))
        let results = repo.search("github work")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.folderId, work)
    }
}
