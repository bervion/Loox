import XCTest
@testable import Vaultify

/// P0 Space Hardening: primary-Space resolver, scoped search (incl. Unfiled),
/// per-identity selected-Space persistence, and the persona-ready sealed field.
@MainActor
final class SpaceHardeningTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: S1 — primary-Space resolver

    func testPrimarySpaceIsLowestSortIndexAndNilWhenEmpty() throws {
        let repo = makeRepo()
        XCTAssertNil(repo.primarySpaceId)                    // no folders → Unfiled world
        let first = try repo.addFolder(name: "Work", icon: "ic_work", color: .blue)
        _ = try repo.addFolder(name: "Personal", icon: "ic_home", color: .green)
        XCTAssertEqual(repo.primarySpaceId, first)           // lowest sortIndex wins
    }

    // MARK: S2 / S4 — scoped search + Unfiled semantics

    func testScopedSearchFiltersBySpaceAndHandlesUnfiled() throws {
        let repo = makeRepo()
        let work = try repo.addFolder(name: "Work", icon: "ic_work", color: .blue)
        try repo.add(VaultItem(category: .login, title: "GitHub", folderId: work))
        try repo.add(VaultItem(category: .login, title: "Gmail"))   // Unfiled (folderId nil)

        // thisSpace: only that folder's items; Unfiled excluded.
        XCTAssertEqual(repo.search("github", scope: .thisSpace(id: work)).map(\.title), ["GitHub"])
        XCTAssertTrue(repo.search("gmail", scope: .thisSpace(id: work)).isEmpty)

        // allSpaces: Unfiled included, and an item matches on its Space name.
        XCTAssertEqual(repo.search("gmail", scope: .allSpaces).map(\.title), ["Gmail"])
        XCTAssertEqual(repo.search("work", scope: .allSpaces).map(\.title), ["GitHub"])

        // thisSpace does NOT match on the Space name (would contradict the scope).
        XCTAssertTrue(repo.search("work", scope: .thisSpace(id: work)).isEmpty)

        // A stale/nonexistent Space id yields empty, never the global set.
        XCTAssertTrue(repo.search("github", scope: .thisSpace(id: "does-not-exist")).isEmpty)

        // sharedWithMe is not owned-vault territory — repo returns nothing.
        XCTAssertTrue(repo.search("github", scope: .sharedWithMe).isEmpty)

        // Legacy shim keeps global behavior.
        XCTAssertEqual(repo.search("gmail").map(\.title), ["Gmail"])
    }

    func testAllSpacesSearchAllowedSeamIsTrue() {
        XCTAssertTrue(makeRepo().allSpacesSearchAllowed)
    }

    // MARK: S3 — FolderSecret personaId readiness (sealed, backward-compatible)

    func testFolderSecretDecodesLegacyBlobWithoutPersonaId() throws {
        let legacy = #"{"name":"Acme"}"#
        let secret = try JSONDecoder().decode(FolderSecret.self, from: Data(legacy.utf8))
        XCTAssertEqual(secret.name, "Acme")
        XCTAssertNil(secret.personaId)
    }

    func testFolderSecretRoundTripsPersonaId() throws {
        var secret = FolderSecret(name: "Dev")
        secret.personaId = "persona-1"
        let sealed = try AESGCM.seal(JSONEncoder().encode(secret), key: testKey)
        let decoded = try JSONDecoder().decode(FolderSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertEqual(decoded.name, "Dev")
        XCTAssertEqual(decoded.personaId, "persona-1")
    }

    // MARK: S0 — per-identity selected-Space persistence

    func testLastSelectedSpaceSetGetRemove() {
        let settings = SettingsStore()
        let persona = "test-\(UUID().uuidString)"
        defer { settings.clearLastSelectedSpace(persona: persona) }      // cleanup UserDefaults

        XCTAssertNil(settings.lastSelectedSpace(persona: persona))       // never chose yet
        settings.setLastSelectedSpace("folder-42", persona: persona)
        XCTAssertEqual(settings.lastSelectedSpace(persona: persona), "folder-42")
        // nil = the user EXPLICITLY chose "All Spaces" — stored as "" so it survives
        // relaunches and Home's single-Space auto-select can't override it. It must NOT
        // erase the key (erasing made "chose All" identical to "never chose", which
        // re-auto-selected the single Space on every return to Home).
        settings.setLastSelectedSpace(nil, persona: persona)
        XCTAssertEqual(settings.lastSelectedSpace(persona: persona), "")
    }

    func testLastSelectedSpaceIsPerIdentity() {
        let settings = SettingsStore()
        let a = "a-\(UUID().uuidString)", b = "b-\(UUID().uuidString)"
        defer { settings.clearLastSelectedSpace(persona: a); settings.clearLastSelectedSpace(persona: b) }
        settings.setLastSelectedSpace("space-a", persona: a)
        settings.setLastSelectedSpace("space-b", persona: b)
        XCTAssertEqual(settings.lastSelectedSpace(persona: a), "space-a")
        XCTAssertEqual(settings.lastSelectedSpace(persona: b), "space-b")
    }
}
