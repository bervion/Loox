import XCTest
@testable import Vaultify

/// Persona↔Space hard partition: backfill, item→persona derivation, fail-closed
/// filters (INV-R03), create-path ownership, and persona-delete reassign.
@MainActor
final class PersonaPartitionTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: Backfill + derivation

    func testBackfillAssignsNilFoldersToDefaultAndIsIdempotent() throws {
        let repo = makeRepo()
        let id = try repo.addFolder(name: "Personal", icon: "ic", color: .blue)
        repo.reload()
        let folder = repo.folders.first { $0.id == id }!
        XCTAssertEqual(folder.personaId, repo.defaultPersona?.id)
        let before = folder.updatedAt
        repo.reload()
        XCTAssertEqual(repo.folders.first { $0.id == id }?.updatedAt, before)  // idempotent
    }

    func testItemPersonaDerivation() throws {
        let repo = makeRepo()
        let folderId = try repo.addFolder(name: "Personal", icon: "ic", color: .blue)
        try repo.add(VaultItem(category: .login, title: "GH", folderId: folderId))
        try repo.add(VaultItem(category: .login, title: "Unfiled"))
        XCTAssertEqual(repo.personaID(forItem: repo.items.first { $0.title == "GH" }!), repo.defaultPersona?.id)
        XCTAssertEqual(repo.personaID(forItem: repo.items.first { $0.title == "Unfiled" }!), repo.defaultPersona?.id)
    }

    // MARK: Fail-closed isolation (INV-R03)

    func testStrictAnonymousNeverSeesDefaultSpacesOrItems() throws {
        let repo = makeRepo()
        let defFolder = try repo.addFolder(name: "Personal", icon: "ic", color: .blue)  // default-owned
        try repo.add(VaultItem(category: .login, title: "GH", folderId: defFolder))
        try repo.add(VaultItem(category: .login, title: "Loose"))  // Unfiled → default only
        let nyxID = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(nyxID)
        let nyx = repo.activePersona!

        XCTAssertFalse(repo.spaces(for: nyx).contains { $0.id == defFolder })  // not the default's Space
        XCTAssertTrue(repo.items(for: nyx).isEmpty)                            // no default items
        XCTAssertEqual(repo.unfiledCount, 0)                                   // Unfiled is default-only
        XCTAssertTrue(repo.search("gh", scope: .allSpaces).isEmpty)
        XCTAssertTrue(repo.search("loose", scope: .allSpaces).isEmpty)
    }

    func testStandardNonDefaultPersonaAlsoPartitioned() throws {
        let repo = makeRepo()
        let folderId = try repo.addFolder(name: "Personal", icon: "ic", color: .blue)
        try repo.add(VaultItem(category: .login, title: "GH", folderId: folderId))
        let workID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        repo.setActivePersona(workID)
        XCTAssertTrue(repo.activePersonaItems.isEmpty)                 // its starter Space is empty
        XCTAssertFalse(repo.items(for: repo.defaultPersona!).isEmpty)  // default keeps its items
    }

    func testUnfiledOnlyUnderDefault() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .login, title: "Loose"))
        let workID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        let work = repo.personas.first { $0.id == workID }!
        XCTAssertTrue(repo.items(for: repo.defaultPersona!).contains { $0.title == "Loose" })
        XCTAssertFalse(repo.items(for: work).contains { $0.title == "Loose" })
    }

    // MARK: Create paths (Phase 03)

    func testNewSpaceOwnedByActivePersona() throws {
        let repo = makeRepo()
        let workID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        repo.setActivePersona(workID)
        let folderId = try repo.addFolder(name: "Servers", icon: "ic", color: .teal)
        XCTAssertEqual(repo.folders.first { $0.id == folderId }?.personaId, workID)
        XCTAssertTrue(repo.spaces(for: repo.activePersona!).contains { $0.id == folderId })
        XCTAssertFalse(repo.spaces(for: repo.defaultPersona!).contains { $0.id == folderId })
    }

    func testNewPersonaGetsOwnedStarterSpace() throws {
        let repo = makeRepo()
        let defSpaceCount = repo.spaces(for: repo.defaultPersona!).count
        let workID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        let work = repo.personas.first { $0.id == workID }!
        XCTAssertNotNil(work.primarySpaceID)
        XCTAssertEqual(repo.folders.first { $0.id == work.primarySpaceID }?.personaId, workID)  // owns it
        XCTAssertEqual(repo.spaces(for: work).count, 1)
        XCTAssertEqual(repo.spaces(for: repo.defaultPersona!).count, defSpaceCount)  // default unchanged
    }

    func testNewItemInheritsActivePersonaViaPrimarySpace() throws {
        let repo = makeRepo()
        let workID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        repo.setActivePersona(workID)
        // The editor files a new item into primarySpaceId (the persona's starter).
        try repo.add(VaultItem(category: .login, title: "L", folderId: repo.primarySpaceId))
        let created = repo.items.first { $0.title == "L" }!
        XCTAssertEqual(repo.personaID(forItem: created), workID)
        XCTAssertTrue(repo.items(for: repo.activePersona!).contains { $0.id == created.id })
    }

    // MARK: Delete reassign (Phase 04)

    func testDeletePersonaReassignsSpacesToDefaultNoDataLoss() throws {
        let repo = makeRepo()
        let workID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        repo.setActivePersona(workID)
        let space = repo.primarySpaceId!
        try repo.add(VaultItem(category: .login, title: "Server", folderId: space))
        let itemsBefore = repo.items.count

        repo.setActivePersona(repo.defaultPersona!.id)   // switch away before delete
        try repo.deletePersona(repo.personas.first { $0.id == workID }!)

        XCTAssertFalse(repo.personas.contains { $0.id == workID })                 // gone
        XCTAssertEqual(repo.folders.first { $0.id == space }?.personaId, repo.defaultPersona?.id)  // reassigned
        XCTAssertEqual(repo.items.count, itemsBefore)                              // no data loss
        XCTAssertTrue(repo.items(for: repo.defaultPersona!).contains { $0.title == "Server" })
        XCTAssertFalse(repo.folders.contains { $0.personaId == workID })           // no dangling ownership
    }
}
