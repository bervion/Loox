import XCTest
@testable import Vaultify

/// Create-login private-email suggestions: pure ranking priority, host
/// matching safety, persona isolation of the repo resolver, and the
/// unbound-alias create path.
@MainActor
final class AliasSuggestionTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: Host matching (conservative, no eTLD+1 truncation)

    func testRelatedHostsSubdomainButNeverAcrossRegistrableBoundary() {
        XCTAssertTrue(AliasSuggestion.relatedHosts("github.com", "github.com"))
        XCTAssertTrue(AliasSuggestion.relatedHosts("accounts.github.com", "github.com"))
        XCTAssertTrue(AliasSuggestion.relatedHosts("login.example.co.uk", "example.co.uk"))
        // The naive last-two-labels bug this design avoids:
        XCTAssertFalse(AliasSuggestion.relatedHosts("example.co.uk", "another.co.uk"))
        XCTAssertFalse(AliasSuggestion.relatedHosts("mygithub.com", "github.com"))
        XCTAssertFalse(AliasSuggestion.relatedHosts("", "github.com"))
    }

    // MARK: Ranking priority

    func testRankedPriorityExactThenDomainThenReusable() {
        let exact = EmailAlias(personaId: "p", tier: .perSite, localPart: "aa",
                               boundItemId: "item-1", boundDomain: "other.com", status: .active)
        let domain = EmailAlias(personaId: "p", tier: .perSite, localPart: "bb",
                                boundItemId: "item-2", boundDomain: "github.com", status: .active)
        let reusable = EmailAlias(personaId: "p", tier: .persona, localPart: "cc", status: .active)
        let reserved = EmailAlias(personaId: "p", tier: .persona, localPart: "dd", status: .reserved)
        let ranked = AliasSuggestion.ranked(aliases: [reserved, reusable, domain, exact],
                                            itemID: "item-1", host: "github.com", flag: true)
        XCTAssertEqual(ranked.map(\.localPart), ["aa", "bb", "cc"])  // reserved excluded
        // Flag off → no address is ever suggested as usable.
        XCTAssertTrue(AliasSuggestion.ranked(aliases: [exact], itemID: "item-1",
                                             host: nil, flag: false).isEmpty)
    }

    // MARK: Persona isolation (INV-PE01)

    func testAliasSuggestionsScopedToActivePersona() throws {
        let repo = makeRepo()
        let otherID = try repo.addPersona(displayName: "Other", kind: .professional,
                                          isolationPolicy: .standard)
        let other = repo.personas.first { $0.id == otherID }!
        repo.setDestinationEmail("o@x.com", for: other)
        _ = try repo.createPerSiteAlias(for: other, boundItemId: nil, domain: "github.com")
        // Force the other persona's alias active so it WOULD rank if not scoped.
        if let alias = repo.aliases(forPersona: otherID).first {
            try repo.setAliasStatus(alias, to: .active)
        }
        // Active persona is the default one — the other persona's alias must not appear.
        XCTAssertNotEqual(repo.activePersona?.id, otherID)
        XCTAssertTrue(repo.aliasSuggestions(forItem: nil, host: "github.com").isEmpty)
    }

    // MARK: Unbound create path (create-login flow)

    func testCreatePerSiteAliasWithoutItemThenBindLater() throws {
        let repo = makeRepo()
        let persona = repo.activePersona!
        let id = try repo.createPerSiteAlias(for: persona, boundItemId: nil, domain: "github.com")
        var alias = repo.aliases.first { $0.id == id }!
        XCTAssertNil(alias.boundItemId)
        XCTAssertEqual(alias.boundDomain, "github.com")
        XCTAssertEqual(alias.status, .reserved)
        // Bind on save (the editor's bindPendingAlias step).
        alias.boundItemId = "item-9"
        try repo.updateAlias(alias)
        XCTAssertEqual(repo.aliases(forItem: "item-9").count, 1)
    }
}
