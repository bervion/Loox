import XCTest
@testable import Vaultify

/// Repository-side scoping for the Search screen's operator grammar (phase-04):
/// `scopedItems(scope:)` (the operator-only-query path) and `passkeyItemIDs(in:)`
/// must never widen beyond what `search(_:scope:)` would ever surface — including
/// under a strictAnonymous persona (INV-R03).
@MainActor
final class SearchScopeIsolationTests: XCTestCase {
    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    func testScopedItemsThisSpaceMatchesFolderIDOnly() throws {
        let repo = makeRepo()
        let folderA = try repo.addFolder(name: "Work", icon: "ic_work", color: .blue)
        try repo.add(VaultItem(category: .login, title: "In folder", folderId: folderA))
        try repo.add(VaultItem(category: .login, title: "Unfiled"))
        let scoped = repo.scopedItems(scope: .thisSpace(id: folderA))
        XCTAssertEqual(scoped.map(\.title), ["In folder"])
    }

    func testScopedItemsAllSpacesIncludesUnfiled() throws {
        let repo = makeRepo()
        let folderA = try repo.addFolder(name: "Work", icon: "ic_work", color: .blue)
        try repo.add(VaultItem(category: .login, title: "In folder", folderId: folderA))
        try repo.add(VaultItem(category: .login, title: "Unfiled"))
        let scoped = repo.scopedItems(scope: .allSpaces)
        XCTAssertEqual(Set(scoped.map(\.title)), ["In folder", "Unfiled"])
    }

    func testScopedItemsSharedWithMeIsAlwaysEmpty() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "Anything"))
        XCTAssertTrue(repo.scopedItems(scope: .sharedWithMe).isEmpty)
    }

    /// The operator-only-query path (`scopedItems`) exists so a bare "weak"
    /// query doesn't trip `search`'s "empty free text → []" guard — it must NOT
    /// reintroduce a cross-persona leak by skipping that guard's partition.
    /// `addPersona` seeds its own starter Space + profile item, so `.allSpaces`
    /// is legitimately non-empty for Nyx — the invariant under test is that the
    /// DEFAULT persona's item never appears in Nyx's scoped pool.
    func testScopedItemsNeverLeaksAcrossPersonaUnderStrictAnonymous() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "Default persona item"))
        let anon = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(anon)
        XCTAssertFalse(repo.scopedItems(scope: .allSpaces).contains { $0.title == "Default persona item" })
        XCTAssertTrue(repo.scopedItems(scope: .thisSpace(id: "x")).isEmpty)  // unowned folder id → empty, never global
    }

    func testPasskeyItemIDsOnlyFlagsItemsWithMatchingRelyingParty() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "GitHub",
                               fields: [DynamicField(label: "Website", kind: .url, value: "https://github.com")]))
        try repo.add(VaultItem(category: .login, title: "No passkey",
                               fields: [DynamicField(label: "Website", kind: .url, value: "https://example.org")]))

        let vault = PasskeyVault(store: repo.store)
        let registration = WebAuthn.register(relyingParty: "github.com")
        let secret = PasskeySecret(relyingParty: "github.com", userName: "me", userHandle: Data([1]),
                                   credentialID: registration.credentialID, privateKeyRaw: registration.privateKeyRaw,
                                   counter: 0, createdAt: .now, flags: registration.flags)
        _ = try vault.save(secret, key: testKey)
        repo.reload()

        let github = try XCTUnwrap(repo.items.first { $0.title == "GitHub" })
        let other = try XCTUnwrap(repo.items.first { $0.title == "No passkey" })
        let ids = repo.passkeyItemIDs(in: repo.items)
        XCTAssertTrue(ids.contains(github.id))
        XCTAssertFalse(ids.contains(other.id))
    }

    /// `passkeyItemIDs` only classifies membership within the pool it's given —
    /// passing a narrower (scoped) pool must never surface ids outside it.
    func testPasskeyItemIDsNeverWidensBeyondGivenPool() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "GitHub",
                               fields: [DynamicField(label: "Website", kind: .url, value: "https://github.com")]))
        let vault = PasskeyVault(store: repo.store)
        let registration = WebAuthn.register(relyingParty: "github.com")
        let secret = PasskeySecret(relyingParty: "github.com", userName: "me", userHandle: Data([1]),
                                   credentialID: registration.credentialID, privateKeyRaw: registration.privateKeyRaw,
                                   counter: 0, createdAt: .now, flags: registration.flags)
        _ = try vault.save(secret, key: testKey)
        repo.reload()

        XCTAssertTrue(repo.passkeyItemIDs(in: []).isEmpty)  // empty pool in → empty out
    }
}
