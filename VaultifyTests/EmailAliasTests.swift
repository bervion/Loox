import XCTest
@testable import Vaultify

/// P3 Local Email Alias model: pure helpers, sealed round-trip/backward-decode,
/// remote LWW, repo CRUD, flag gating, and persona-delete cascade.
@MainActor
final class EmailAliasTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    // MARK: Pure helpers

    func testAddressNeverEmitsAtSuffixWhenFlagOff() {
        for status in AliasStatus.allCases {
            let s = AliasAddress.display(localPart: "abc123", status: status, relayDomain: "relay.looxpassword.com", flag: false)
            XCTAssertFalse(s.contains("@"), "no live-looking address pre-relay (status=\(status))")
        }
    }

    func testAddressKeepsDomainBeforeActivationAndWhilePaused() {
        XCTAssertEqual(
            AliasAddress.display(localPart: "abc", status: .active, relayDomain: "relay.x", flag: true),
            "abc@relay.x")
        XCTAssertEqual(
            AliasAddress.display(localPart: "abc", status: .reserved, relayDomain: "relay.x", flag: true),
            "abc@relay.x")
        for status in AliasStatus.allCases {
            XCTAssertEqual(AliasAddress.display(localPart: "abc", status: status,
                                                relayDomain: "relay.x", flag: true), "abc@relay.x")
        }
    }

    func testLifecycleBlocksActiveWhenFlagOff() {
        XCTAssertFalse(AliasLifecycle.canTransition(from: .reserved, to: .active, flag: false))
        XCTAssertTrue(AliasLifecycle.canTransition(from: .reserved, to: .disabled, flag: false))
        XCTAssertTrue(AliasLifecycle.canTransition(from: .reserved, to: .active, flag: true))
    }

    func testEmailMaskKeepsPrefixAndDomain() {
        XCTAssertEqual(EmailMask.masked("chinh@gmail.com"), "ch***@gmail.com")
        XCTAssertEqual(EmailMask.masked("a@x.co"), "a***@x.co")      // short local part
        XCTAssertEqual(EmailMask.masked("no-at-sign"), "no-at-sign") // not an email → unchanged
        XCTAssertEqual(EmailMask.masked("@lead.com"), "@lead.com")   // empty local → unchanged
    }

    func testRandomLocalPartIsUnpredictableAndClean() {
        let a = AliasAddress.randomLocalPart(), b = AliasAddress.randomLocalPart()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 12)
        XCTAssertFalse(a.contains("@"))
    }

    // MARK: Sealed round-trip / backward-decode

    func testAliasSecretDecodesLegacyBlobToDefaults() throws {
        let legacy = #"{"personaId":"p1","localPart":"x7k2"}"#
        let secret = try JSONDecoder().decode(EmailAliasSecret.self, from: Data(legacy.utf8))
        XCTAssertEqual(secret.personaId, "p1")
        XCTAssertEqual(secret.localPart, "x7k2")
        XCTAssertEqual(secret.tier, .perSite)   // defaulted
        XCTAssertEqual(secret.status, .draft)   // defaulted
        XCTAssertNil(secret.boundItemId)
    }

    func testAliasSecretSealRoundTrip() throws {
        let alias = EmailAlias(personaId: "p1", tier: .perSite, localPart: "r7kp2d",
                               boundItemId: "item-1", boundDomain: "reddit.com",
                               status: .reserved, forwardingTarget: "me@x.com")
        let sealed = try AESGCM.seal(JSONEncoder().encode(alias.secret), key: testKey)
        let decoded = try JSONDecoder().decode(EmailAliasSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertEqual(decoded.tier, .perSite)
        XCTAssertEqual(decoded.boundDomain, "reddit.com")
        XCTAssertEqual(decoded.status, .reserved)
        XCTAssertEqual(decoded.forwardingTarget, "me@x.com")
    }

    // MARK: Remote LWW upsert

    func testUpsertAliasFromRemoteLWW() {
        let store = VaultStore(inMemory: true)
        let old = Data([1]); let new = Data([2])
        let t0 = Date(); let t1 = t0.addingTimeInterval(60)
        store.upsertAliasFromRemote(id: "a1", sealed: old, sortIndex: 0, deletedAt: nil, createdAt: t0, updatedAt: t0, changeTag: "a")
        store.upsertAliasFromRemote(id: "a1", sealed: new, sortIndex: 0, deletedAt: nil, createdAt: t0, updatedAt: t1, changeTag: "a") // same tag → no-op
        XCTAssertEqual(store.aliasRecord(id: "a1")?.sealed, old)
        store.upsertAliasFromRemote(id: "a1", sealed: new, sortIndex: 0, deletedAt: nil, createdAt: t0, updatedAt: t1, changeTag: "b") // newer → wins
        XCTAssertEqual(store.aliasRecord(id: "a1")?.sealed, new)
    }

    // MARK: Repo CRUD + flag gating

    func testMultipleReusableAliasesPerPersonaAllowed() throws {
        let repo = makeRepo()
        let persona = repo.activePersona!
        XCTAssertNotNil(try repo.createPersonaAlias(for: persona, label: "Clients"))
        XCTAssertNotNil(try repo.createPersonaAlias(for: persona, label: "Newsletter"))
        let reusable = repo.reusableAliases(forPersona: persona.id)
        XCTAssertEqual(reusable.count, 2)
        XCTAssertEqual(Set(reusable.compactMap(\.label)), ["Clients", "Newsletter"])
    }

    func testSetAliasStatusActiveGatedByRelayFlag() throws {
        let repo = makeRepo()
        let persona = repo.activePersona!
        _ = try repo.createPersonaAlias(for: persona)
        let alias = repo.personaAlias(forPersona: persona.id)!
        try repo.setAliasStatus(alias, to: .active)
        // The relay is live (RelayFeature.activeAliasesEnabled) → the transition is
        // allowed. Guarded so if the backend is ever pulled (flag off) this reverts
        // to a no-op that keeps aliases from rendering as live when they aren't.
        let expected: AliasStatus = RelayFeature.activeAliasesEnabled ? .active : .reserved
        XCTAssertEqual(repo.personaAlias(forPersona: persona.id)?.status, expected)
    }

    func testDeletePersonaCascadesAliases() throws {
        let repo = makeRepo()
        let newID = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        let persona = repo.personas.first { $0.id == newID }!
        _ = try repo.createPersonaAlias(for: persona)
        XCTAssertEqual(repo.aliases(forPersona: newID).count, 1)
        try repo.deletePersona(persona)
        XCTAssertTrue(repo.aliases(forPersona: newID).isEmpty)  // cascade tombstoned them
    }

    // MARK: Destination + write-back (relay destination feature)

    func testAliasSecretBackendMintedBackwardDecodesFalse() throws {
        let legacy = #"{"personaId":"p1","localPart":"x7k2"}"#
        let secret = try JSONDecoder().decode(EmailAliasSecret.self, from: Data(legacy.utf8))
        XCTAssertFalse(secret.backendMinted)   // absent → false
        var minted = EmailAlias(personaId: "p", tier: .persona, localPart: "y", backendMinted: true)
        minted.forwardingTarget = "me@x.com"
        let sealed = try AESGCM.seal(JSONEncoder().encode(minted.secret), key: testKey)
        let decoded = try JSONDecoder().decode(EmailAliasSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertTrue(decoded.backendMinted)
        XCTAssertEqual(decoded.forwardingTarget, "me@x.com")
    }

    func testUpsertPrivateEmailAppendsOnceKeepsRealEmailFirst() {
        var item = VaultItem(category: .identity, title: "Me",
                             fields: [DynamicField(label: "Email", kind: .email, value: "me@real.com")])
        item = AliasWriteback.upsertPrivateEmail(on: item, address: "nyx@relay.x")
        let emails = item.fields.filter { $0.kind == .email }
        XCTAssertEqual(emails.count, 2)
        XCTAssertEqual(emails.first?.value, "me@real.com")   // real stays first (suggestions use it)
        XCTAssertTrue(item.fields.contains { $0.label == "Private email" && $0.value == "nyx@relay.x" })
        // Idempotent: re-activation updates the same field, never duplicates.
        item = AliasWriteback.upsertPrivateEmail(on: item, address: "nyx2@relay.x")
        XCTAssertEqual(item.fields.filter { $0.label == "Private email" }.count, 1)
        XCTAssertEqual(item.fields.first { $0.label == "Private email" }?.value, "nyx2@relay.x")
    }

    func testDestinationEmailExcludesWrittenBackAlias() throws {
        let repo = makeRepo()
        // A persona created via addPersona has its own profile card (which starts
        // without an email — so no forwarding destination yet).
        let id = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        let persona = repo.personas.first { $0.id == id }!
        XCTAssertNil(repo.destinationEmail(for: persona))
        repo.setDestinationEmail("me@real.com", for: persona)
        XCTAssertEqual(repo.destinationEmail(for: persona), "me@real.com")
        // Writing back an alias adds a "Private email" field — destination stays real.
        if let card = repo.profileItem(for: persona) {
            try repo.update(AliasWriteback.upsertPrivateEmail(on: card, address: "nyx@relay.x"))
        }
        XCTAssertEqual(repo.destinationEmail(for: persona), "me@real.com")
    }

    func testEraseAllRemovesAliasRecords() throws {
        let repo = makeRepo()
        _ = try repo.createPersonaAlias(for: repo.activePersona!)
        XCTAssertFalse(repo.store.allAliasRecords().filter { $0.deletedAt == nil }.isEmpty)
        try repo.store.eraseAll()
        XCTAssertTrue(repo.store.allAliasRecords().isEmpty)
    }
}
