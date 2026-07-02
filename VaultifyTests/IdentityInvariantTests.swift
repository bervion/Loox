import XCTest
@testable import Vaultify

/// Phase 2: the single-active default-identity invariant — set/clear, conflict normalize,
/// promotion on removal, and the last-identity removal gate. In-memory store, fixed Vault Key.
@MainActor
final class IdentityInvariantTests: XCTestCase {

    private func makeStack() -> (repo: VaultRepository, store: VaultStore) {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let store = VaultStore(inMemory: true)
        let repo = VaultRepository(store: store, session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return (repo, store)
    }

    /// Adds two identities; the first added auto-promotes to default via reload normalize.
    private func addAB(_ repo: VaultRepository) throws -> (a: String, b: String) {
        try repo.add(VaultItem(category: .identity, title: "A"))
        let a = try XCTUnwrap(repo.items.first { $0.title == "A" }).id
        try repo.add(VaultItem(category: .identity, title: "B"))
        let b = try XCTUnwrap(repo.items.first { $0.title == "B" }).id
        return (a, b)
    }

    private func item(_ repo: VaultRepository, _ id: String) throws -> VaultItem {
        try XCTUnwrap(repo.items.first { $0.id == id })
    }

    func testNoDefaultWhenNoIdentities() {
        let (repo, _) = makeStack()
        XCTAssertNil(repo.defaultIdentity)
        XCTAssertTrue(repo.activeIdentities.isEmpty)
    }

    func testFirstIdentityAutoPromotesToDefault() throws {
        let (repo, _) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "A"))
        XCTAssertEqual(repo.defaultIdentity?.title, "A")
    }

    func testSetDefaultMarksOneClearsOthers() throws {
        let (repo, _) = makeStack()
        let (a, b) = try addAB(repo)
        repo.setDefaultIdentity(try item(repo, b))
        XCTAssertEqual(repo.defaultIdentity?.id, b)
        XCTAssertFalse(try item(repo, a).isDefaultIdentity)
        repo.setDefaultIdentity(try item(repo, a))
        XCTAssertEqual(repo.defaultIdentity?.id, a)
        XCTAssertFalse(try item(repo, b).isDefaultIdentity)
    }

    func testSetDefaultBumpsUpdatedAt() throws {
        let (repo, store) = makeStack()
        let (_, b) = try addAB(repo)
        // Pin B's updatedAt to the epoch so the bump is unambiguous.
        let epoch = Date(timeIntervalSince1970: 0)
        try XCTUnwrap(store.record(id: b)).updatedAt = epoch
        try store.context.save()
        repo.reload()
        repo.setDefaultIdentity(try item(repo, b))
        XCTAssertGreaterThan(try item(repo, b).updatedAt, epoch)
    }

    func testNormalizePromotesWhenNoDefault() throws {
        let (repo, store) = makeStack()
        let (a, _) = try addAB(repo)
        // Clear the auto-promoted default → 0 defaults among 2 active identities.
        try XCTUnwrap(store.record(id: a)).isDefaultIdentity = false
        try store.context.save()
        repo.reload()
        XCTAssertEqual(repo.activeIdentities.filter(\.isDefaultIdentity).count, 1)
    }

    func testNormalizeCollapsesDoubleDefault() throws {
        let (repo, store) = makeStack()
        let (_, b) = try addAB(repo)   // A is default
        // Force a second default on B with a clearly-later updatedAt → B must win.
        let bRec = try XCTUnwrap(store.record(id: b))
        bRec.isDefaultIdentity = true
        bRec.updatedAt = Date(timeIntervalSinceNow: 10_000)
        try store.context.save()
        repo.reload()
        XCTAssertEqual(repo.activeIdentities.filter(\.isDefaultIdentity).map(\.id), [b])
    }

    func testLastActiveIdentityGateBlocks() throws {
        let (repo, _) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "A"))
        XCTAssertEqual(repo.identityRemovalGate(try item(repo, repo.items[0].id)), .lastActiveIdentity)
    }

    func testGateOkWithTwoIdentities() throws {
        let (repo, _) = makeStack()
        let (a, b) = try addAB(repo)
        XCTAssertEqual(repo.identityRemovalGate(try item(repo, a)), .ok)
        XCTAssertEqual(repo.identityRemovalGate(try item(repo, b)), .ok)
    }

    func testTrashingDefaultPromotesAnother() throws {
        let (repo, _) = makeStack()
        let (a, b) = try addAB(repo)
        repo.setDefaultIdentity(try item(repo, a))
        try repo.moveToTrash(try item(repo, a))
        XCTAssertEqual(repo.defaultIdentity?.id, b)
    }

    func testArchivingDefaultPromotesAnother() throws {
        let (repo, _) = makeStack()
        let (a, b) = try addAB(repo)
        repo.setDefaultIdentity(try item(repo, a))
        repo.archive(try item(repo, a))
        XCTAssertEqual(repo.defaultIdentity?.id, b)
    }

    func testDeletingDefaultPromotesAnother() throws {
        let (repo, _) = makeStack()
        let (a, b) = try addAB(repo)
        repo.setDefaultIdentity(try item(repo, a))
        try repo.delete(try item(repo, a))
        XCTAssertEqual(repo.defaultIdentity?.id, b)
    }
}
