import XCTest
@testable import Vaultify

/// P2 Persona Context + AutoFill: the pure suggestion engine, in-app isolation
/// consumption (INV-R03), the App-Group mirror, and the management delete gate.
@MainActor
final class PersonaIsolationTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: P2.1 — pure suggestion engine (INV-R03)

    func testStrictAnonymousExcludesOtherPersonaAndGlobalDefault() {
        let candidates = [
            UsernameCandidate(value: "me@personal.com", sourcePersonaID: nil, source: .defaultIdentity, lastUsedAt: nil),
            UsernameCandidate(value: "b@work.com", sourcePersonaID: "B", source: .activePersonaProfile, lastUsedAt: nil),
            UsernameCandidate(value: "nyx@relay.com", sourcePersonaID: "A", source: .activePersonaProfile, lastUsedAt: nil),
        ]
        let out = PersonaUsernameSuggester.suggestions(candidates: candidates, activePersonaID: "A", policy: .strictAnonymous)
        XCTAssertEqual(out, ["nyx@relay.com"])  // only persona A's own value survives
    }

    func testStandardRanksOwnThenDefaultThenRecentsDeduped() {
        let candidates = [
            UsernameCandidate(value: "R@x.com", sourcePersonaID: nil, source: .recent, lastUsedAt: .now),
            UsernameCandidate(value: "me@personal.com", sourcePersonaID: nil, source: .defaultIdentity, lastUsedAt: nil),
            UsernameCandidate(value: "own@a.com", sourcePersonaID: "A", source: .activePersonaProfile, lastUsedAt: nil),
            UsernameCandidate(value: "OWN@a.com", sourcePersonaID: "A", source: .recent, lastUsedAt: .now),  // dupe (case)
        ]
        let out = PersonaUsernameSuggester.suggestions(candidates: candidates, activePersonaID: "A", policy: .standard)
        XCTAssertEqual(out.first, "own@a.com")            // own persona first
        XCTAssertEqual(out.filter { $0.lowercased() == "own@a.com" }.count, 1)  // deduped
        XCTAssertTrue(out.contains("me@personal.com"))
    }

    func testIsolatedKeepsOthersButRanksOwnFirst() {
        let candidates = [
            UsernameCandidate(value: "b@work.com", sourcePersonaID: "B", source: .activePersonaProfile, lastUsedAt: nil),
            UsernameCandidate(value: "own@a.com", sourcePersonaID: "A", source: .recent, lastUsedAt: nil),
        ]
        let out = PersonaUsernameSuggester.suggestions(candidates: candidates, activePersonaID: "A", policy: .isolated)
        XCTAssertEqual(out.first, "own@a.com")   // own first
        XCTAssertTrue(out.contains("b@work.com")) // others kept
    }

    // MARK: P2.2 — in-app isolation consumption

    func testAllSpacesSearchAllowedGatedByStrictAnonymous() throws {
        let repo = makeRepo()
        XCTAssertTrue(repo.allSpacesSearchAllowed)  // default persona = standard
        let id = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(id)
        XCTAssertFalse(repo.allSpacesSearchAllowed) // INV-R03
    }

    func testDefaultSearchScopeNeverAllSpacesUnderStrictAnonymous() throws {
        let repo = makeRepo()
        let id = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(id)
        let scope = repo.defaultSearchScope(currentSpaceId: nil)
        if case .allSpaces = scope { XCTFail("strictAnonymous must never default to .allSpaces") }
        // No own Space → the scope matches no folder → empty results, never global.
        try repo.add(VaultItem(category: .login, title: "GitHub"))
        XCTAssertTrue(repo.search("github", scope: scope).isEmpty)
    }

    func testUsernameSuggestionsExcludeDefaultIdentityUnderStrictAnonymous() throws {
        let repo = makeRepo()
        // A default identity with an email exists.
        try repo.add(VaultItem(category: .identity, title: "Me",
                               fields: [DynamicField(label: "Email", kind: .email, value: "me@personal.com")],
                               isDefaultIdentity: true))
        let id = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(id)
        XCTAssertFalse(repo.usernameSuggestions().contains("me@personal.com"))  // INV-R03
    }

    func testIdentityUsernameNoFallbackForStrictAnonymous() throws {
        let repo = makeRepo()
        try repo.add(VaultItem(category: .identity, title: "Me",
                               fields: [DynamicField(label: "Email", kind: .email, value: "me@personal.com")],
                               isDefaultIdentity: true))
        let strict = Persona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        XCTAssertNil(repo.identityUsername(forPersona: strict))  // no borrow of the default email
        let standard = Persona(displayName: "Me", kind: .personal, isolationPolicy: .standard)
        XCTAssertEqual(repo.identityUsername(forPersona: standard), "me@personal.com")  // fallback allowed
    }

    func testShowsSharedScopeSuppressedUnderStrictAnonymous() throws {
        let repo = makeRepo()
        XCTAssertTrue(repo.showsSharedScope(base: true))
        let id = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(id)
        XCTAssertFalse(repo.showsSharedScope(base: true))
    }

    // MARK: P2.3 — App-Group mirror

    func testMirrorWritesActivePersonaContext() throws {
        let repo = makeRepo()
        let id = try repo.addPersona(displayName: "Nyx", kind: .anonymous, isolationPolicy: .strictAnonymous)
        repo.setActivePersona(id)
        XCTAssertEqual(SharedConfig.sharedDefaults.string(forKey: SharedConfig.activePersonaPolicyKey),
                       PersonaIsolationPolicy.strictAnonymous.rawValue)
    }

    // MARK: P2.4 — management gate

    func testPersonaRemovalGate() throws {
        let repo = makeRepo()
        let onlyPersona = repo.personas[0]
        XCTAssertEqual(repo.personaRemovalGate(onlyPersona), .lastPersona)  // can't delete the last

        let newID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        let def = repo.personas.first { $0.isDefault }!
        XCTAssertEqual(repo.personaRemovalGate(def), .defaultPersona)       // can't delete the default
        let nonDefault = repo.personas.first { $0.id == newID }!
        XCTAssertEqual(repo.personaRemovalGate(nonDefault), .ok)

        try repo.deletePersona(nonDefault)
        XCTAssertFalse(repo.personas.contains { $0.id == newID })
    }

    func testUpdatePersonaResealsPolicy() throws {
        let repo = makeRepo()
        var persona = repo.personas[0]
        persona.isolationPolicy = .strictAnonymous
        try repo.updatePersona(persona)
        XCTAssertEqual(repo.personas.first { $0.id == persona.id }?.isolationPolicy, .strictAnonymous)
        XCTAssertEqual(repo.personas.filter(\.isDefault).count, 1)  // invariant preserved
    }
}
