import XCTest
@testable import Vaultify

/// Phase 1: the synced `isDefaultIdentity` / `avatarSealed` columns round-trip through the
/// store + repository, survive the `update` re-seal path, and the `.identity` template carries
/// the profile fields. Uses a real in-memory `VaultStore` with a fixed Vault Key (no Argon2).
@MainActor
final class IdentityDataModelTests: XCTestCase {

    private func makeStack() -> (repo: VaultRepository, store: VaultStore) {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let store = VaultStore(inMemory: true)
        let repo = VaultRepository(store: store, session: session)
        repo.reload()
        return (repo, store)
    }

    /// The column defaults to false and non-identity items are never marked. (A lone
    /// `.identity` would auto-promote to default via the Phase-2 invariant, so this uses
    /// a `.login` to isolate the column default.)
    func testDefaultMarkerDefaultsFalseForNonIdentity() throws {
        let (repo, _) = makeStack()
        try repo.add(VaultItem(category: .login, title: "GitHub"))
        let item = try XCTUnwrap(repo.items.first { $0.title == "GitHub" })
        XCTAssertFalse(item.isDefaultIdentity)
    }

    func testDefaultMarkerPersistsThroughReload() throws {
        let (repo, store) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "Me"))
        let id = try XCTUnwrap(repo.items.first).id
        let record = try XCTUnwrap(store.record(id: id))
        record.isDefaultIdentity = true
        try store.context.save()
        repo.reload()
        XCTAssertTrue(try XCTUnwrap(repo.items.first { $0.id == id }).isDefaultIdentity)
    }

    func testUpdatePreservesDefaultMarker() throws {
        let (repo, store) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "Me"))
        let id = try XCTUnwrap(repo.items.first).id
        let record = try XCTUnwrap(store.record(id: id))
        record.isDefaultIdentity = true
        try store.context.save()
        repo.reload()
        var item = try XCTUnwrap(repo.items.first { $0.id == id })
        item.title = "Me Edited"           // re-seal path
        try repo.update(item)
        repo.reload()
        XCTAssertTrue(try XCTUnwrap(repo.items.first { $0.id == id }).isDefaultIdentity)
    }

    func testAvatarSealedColumnRoundTrips() throws {
        let (repo, store) = makeStack()
        try repo.add(VaultItem(category: .identity, title: "Me"))
        let id = try XCTUnwrap(repo.items.first).id
        let bytes = Data([1, 2, 3, 4, 5])
        let record = try XCTUnwrap(store.record(id: id))
        record.avatarSealed = bytes
        try store.context.save()
        XCTAssertEqual(store.record(id: id)?.avatarSealed, bytes)
    }

    func testIdentityTemplateHasProfileFields() {
        let kinds = ItemCategory.identity.fieldTemplate.map(\.kind)
        XCTAssertTrue(kinds.contains(.email))
        XCTAssertTrue(kinds.contains(.multiline)) // Address
        XCTAssertTrue(kinds.contains(.date))      // Date of Birth
    }
}
