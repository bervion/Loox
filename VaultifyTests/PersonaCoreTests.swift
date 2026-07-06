import XCTest
@testable import Vaultify

/// P1 Persona Core: seed/invariants, resolver, CRUD, `primarySpaceId` rebind,
/// sealed round-trip/backward-decode, and remote LWW upsert.
@MainActor
final class PersonaCoreTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: Seed + invariants

    func testReloadSeedsExactlyOneDefaultPersonalPersona() {
        let repo = makeRepo()
        XCTAssertEqual(repo.personas.count, 1)
        let persona = repo.personas[0]
        XCTAssertEqual(persona.id, Persona.bootstrapPersonalID)
        XCTAssertEqual(persona.kind, .personal)
        XCTAssertTrue(persona.isDefault)
        XCTAssertEqual(repo.personas.filter(\.isDefault).count, 1)
    }

    func testSeedIsIdempotent() {
        let repo = makeRepo()
        repo.reload()
        repo.reload()
        XCTAssertEqual(repo.personas.count, 1)
        XCTAssertEqual(repo.personas.filter(\.isDefault).count, 1)
    }

    func testAddPersonaKeepsExactlyOneDefault() throws {
        let repo = makeRepo()
        let newID = try repo.addPersona(displayName: "Work", kind: .professional)
        XCTAssertEqual(repo.personas.count, 2)
        XCTAssertEqual(repo.personas.filter(\.isDefault).count, 1)
        XCTAssertFalse(repo.personas.first { $0.id == newID }!.isDefault)  // new one is not default
    }

    func testSetDefaultPersonaMovesTheSingleDefault() throws {
        let repo = makeRepo()
        let newID = try repo.addPersona(displayName: "Work", kind: .professional)
        repo.setDefaultPersona(repo.personas.first { $0.id == newID }!)
        XCTAssertEqual(repo.personas.filter(\.isDefault).count, 1)
        XCTAssertTrue(repo.personas.first { $0.id == newID }!.isDefault)
        XCTAssertFalse(repo.personas.first { $0.id == Persona.bootstrapPersonalID }!.isDefault)
    }

    // MARK: Active-persona resolver

    func testActivePersonaResolvesDefaultThenSelectionThenStale() throws {
        let repo = makeRepo()
        // No selection → default.
        XCTAssertEqual(repo.activePersona?.id, Persona.bootstrapPersonalID)
        let newID = try repo.addPersona(displayName: "Work", kind: .professional)
        repo.setActivePersona(newID)
        XCTAssertEqual(repo.activePersona?.id, newID)             // valid selection
        repo.setActivePersona("does-not-exist")
        XCTAssertEqual(repo.activePersona?.id, Persona.bootstrapPersonalID)  // stale → default
    }

    // MARK: primarySpaceId rebind

    func testPrimarySpaceIdFollowsActivePersonaPointer() throws {
        let repo = makeRepo()
        let space = try repo.addFolder(name: "Work", icon: "ic_work", color: .blue)
        // A persona created now pins the current primary Space.
        let newID = try repo.addPersona(displayName: "Work", kind: .professional)
        repo.setActivePersona(newID)
        XCTAssertEqual(repo.activePersona?.primarySpaceID, space)
        XCTAssertEqual(repo.primarySpaceId, space)                // resolves via persona pointer
    }

    // MARK: Sealed round-trip / backward-decode

    func testPersonaSecretDecodesLegacyBlobToDefaults() throws {
        let legacy = #"{"displayName":"Nyx","kind":"anonymous"}"#
        let secret = try JSONDecoder().decode(PersonaSecret.self, from: Data(legacy.utf8))
        XCTAssertEqual(secret.displayName, "Nyx")
        XCTAssertEqual(secret.kind, .anonymous)
        XCTAssertEqual(secret.isolationPolicy, .standard)   // defaulted
        XCTAssertNil(secret.primarySpaceID)
        XCTAssertNil(secret.primaryProfileItemID)
    }

    func testPersonaSecretSealRoundTrip() throws {
        let persona = Persona(displayName: "Kiyo", kind: .professional,
                              isolationPolicy: .strictAnonymous,
                              primaryProfileItemID: "item-1", primarySpaceID: "folder-1")
        let sealed = try AESGCM.seal(JSONEncoder().encode(persona.secret), key: testKey)
        let decoded = try JSONDecoder().decode(PersonaSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertEqual(decoded.displayName, "Kiyo")
        XCTAssertEqual(decoded.kind, .professional)
        XCTAssertEqual(decoded.isolationPolicy, .strictAnonymous)
        XCTAssertEqual(decoded.primaryProfileItemID, "item-1")
        XCTAssertEqual(decoded.primarySpaceID, "folder-1")
    }

    // MARK: Remote LWW upsert (VaultStore)

    func testUpsertPersonaFromRemoteLWWAndDefaultPropagation() throws {
        let store = VaultStore(inMemory: true)
        let sealedOld = Data([1]); let sealedNew = Data([2])
        let t0 = Date(); let t1 = t0.addingTimeInterval(60)

        store.upsertPersonaFromRemote(id: "p1", sealed: sealedOld, isDefault: false, sortIndex: 0,
                                      deletedAt: nil, createdAt: t0, updatedAt: t0, changeTag: "a")
        XCTAssertEqual(store.personaRecord(id: "p1")?.sealed, sealedOld)

        // Same change tag → no-op even with newer payload.
        store.upsertPersonaFromRemote(id: "p1", sealed: sealedNew, isDefault: true, sortIndex: 9,
                                      deletedAt: nil, createdAt: t0, updatedAt: t1, changeTag: "a")
        XCTAssertEqual(store.personaRecord(id: "p1")?.sealed, sealedOld)

        // Newer updatedAt + new tag → content (incl. isDefault) wins.
        store.upsertPersonaFromRemote(id: "p1", sealed: sealedNew, isDefault: true, sortIndex: 9,
                                      deletedAt: nil, createdAt: t0, updatedAt: t1, changeTag: "b")
        XCTAssertEqual(store.personaRecord(id: "p1")?.sealed, sealedNew)
        XCTAssertTrue(store.personaRecord(id: "p1")!.isDefault)
    }
}
