import XCTest
@testable import Vaultify

/// ForwardingInbox model: sealed round-trip/backward-decode, remote LWW,
/// profile-email derivation (idempotent), destination resolution priority,
/// default-inbox invariant, and delete guards.
@MainActor
final class ForwardingInboxTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeRepo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    /// A persona with a profile email — the precondition for derivation.
    private func makePersonaWithEmail(_ repo: VaultRepository, email: String = "me@real.com") throws -> Persona {
        let id = try repo.addPersona(displayName: "Work", kind: .professional, isolationPolicy: .standard)
        let persona = repo.personas.first { $0.id == id }!
        repo.setDestinationEmail(email, for: persona)
        return repo.personas.first { $0.id == id }!
    }

    // MARK: Sealed round-trip / backward-decode

    func testInboxSecretSealRoundTrip() throws {
        let inbox = ForwardingInbox(email: "work@company.com", label: "Work",
                                    source: .manual, isDefault: true)
        let sealed = try AESGCM.seal(JSONEncoder().encode(inbox.secret), key: testKey)
        let decoded = try JSONDecoder().decode(ForwardingInboxSecret.self, from: AESGCM.open(sealed, key: testKey))
        XCTAssertEqual(decoded.email, "work@company.com")
        XCTAssertEqual(decoded.label, "Work")
        XCTAssertEqual(decoded.source, .manual)
        XCTAssertTrue(decoded.isDefault)
    }

    func testInboxSecretDecodesLegacyBlobToDefaults() throws {
        let legacy = #"{"email":"me@x.com"}"#
        let secret = try JSONDecoder().decode(ForwardingInboxSecret.self, from: Data(legacy.utf8))
        XCTAssertEqual(secret.email, "me@x.com")
        XCTAssertEqual(secret.source, .manual)   // defaulted
        XCTAssertFalse(secret.isDefault)         // defaulted
        XCTAssertNil(secret.personaId)
        XCTAssertEqual(secret.verificationGeneration, 0)
    }

    func testAliasSecretInboxFieldsBackwardDecodeNil() throws {
        let legacy = #"{"personaId":"p1","localPart":"x7k2"}"#
        let secret = try JSONDecoder().decode(EmailAliasSecret.self, from: Data(legacy.utf8))
        XCTAssertNil(secret.forwardingInboxID)
        XCTAssertNil(secret.label)
    }

    // MARK: Remote LWW upsert

    func testUpsertInboxFromRemoteLWW() {
        let store = VaultStore(inMemory: true)
        let old = Data([1]); let new = Data([2])
        let t0 = Date(); let t1 = t0.addingTimeInterval(60)
        store.upsertInboxFromRemote(id: "i1", sealed: old, sortIndex: 0, deletedAt: nil, createdAt: t0, updatedAt: t0, changeTag: "a")
        store.upsertInboxFromRemote(id: "i1", sealed: new, sortIndex: 0, deletedAt: nil, createdAt: t0, updatedAt: t1, changeTag: "a") // same tag → no-op
        XCTAssertEqual(store.inboxRecord(id: "i1")?.sealed, old)
        store.upsertInboxFromRemote(id: "i1", sealed: new, sortIndex: 0, deletedAt: nil, createdAt: t0, updatedAt: t1, changeTag: "b") // newer → wins
        XCTAssertEqual(store.inboxRecord(id: "i1")?.sealed, new)
    }

    // MARK: Derivation

    func testProfileInboxDerivedOncePerPersonaAndFollowsEmail() throws {
        let repo = makeRepo()
        let persona = try makePersonaWithEmail(repo)
        let derived = repo.forwardingInboxes.filter { $0.source == .personaProfile && $0.personaId == persona.id }
        XCTAssertEqual(derived.count, 1)
        XCTAssertEqual(derived.first?.email, "me@real.com")
        // Idempotent across reloads — no duplicate.
        repo.reload()
        repo.reload()
        XCTAssertEqual(repo.forwardingInboxes.filter { $0.source == .personaProfile && $0.personaId == persona.id }.count, 1)
        // Email follows the profile.
        repo.setDestinationEmail("new@real.com", for: persona)
        XCTAssertEqual(repo.forwardingInboxes.first { $0.personaId == persona.id }?.email, "new@real.com")
    }

    func testProfileEmailChangeInvalidatesVerifiedDestinationAndGeneration() throws {
        let repo = makeRepo()
        let persona = try makePersonaWithEmail(repo)
        var original = repo.forwardingInboxes.first { $0.personaId == persona.id }!
        original.relayDestinationID = "old-destination"
        original.verificationStatus = .verified
        try repo.updateInbox(original)
        let verifiedGeneration = try XCTUnwrap(repo.inbox(id: original.id)).verificationGeneration
        repo.setDestinationEmail("new@real.com", for: persona)
        let changed = repo.forwardingInboxes.first { $0.personaId == persona.id }!
        XCTAssertEqual(changed.email, "new@real.com")
        XCTAssertNil(changed.relayDestinationID)
        XCTAssertEqual(changed.verificationStatus, .unverified)
        XCTAssertEqual(changed.verificationGeneration, verifiedGeneration + 1)
    }

    func testMakingStalePendingSnapshotDefaultPreservesLiveVerificationIdentity() throws {
        let repo = makeRepo()
        let id = try repo.addManualInbox(email: "fixture@example.test")
        var pending = try XCTUnwrap(repo.inbox(id: id))
        pending.relayDestinationID = "synthetic-destination"
        pending.verificationStatus = .pending
        try repo.updateInbox(pending)
        let snapshot = try XCTUnwrap(repo.inbox(id: id))
        let verifiedState = RelayAPIClient.DestinationState(destinationId: "synthetic-destination",
            status: "verified", maskedEmail: nil, resendAfterSeconds: nil)
        XCTAssertTrue(try repo.applyDestinationState(verifiedState, snapshot: snapshot, allowDestinationChange: false))
        let verified = try XCTUnwrap(repo.inbox(id: id))
        try repo.setDefaultInbox(snapshot)
        let actual = try XCTUnwrap(repo.inbox(id: id))
        XCTAssertTrue(actual.isDefault)
        XCTAssertEqual(actual.verificationStatus, .verified)
        XCTAssertEqual(actual.relayDestinationID, verified.relayDestinationID)
        XCTAssertEqual(actual.verificationGeneration, verified.verificationGeneration)
        XCTAssertEqual(actual.email, verified.email)
    }

    // MARK: Resolution priority

    func testResolvedDestinationPriority() throws {
        let repo = makeRepo()
        let persona = try makePersonaWithEmail(repo)
        // 1) No override, no explicit default → derived profile inbox.
        let id = try repo.createPersonaAlias(for: persona)!
        var alias = repo.aliases.first { $0.id == id }!
        XCTAssertEqual(repo.resolvedDestination(for: alias), "me@real.com")
        // 2) Explicit vault default wins for unpinned aliases.
        let inboxID = try repo.addManualInbox(email: "work@company.com", label: "Work")
        try repo.setDefaultInbox(repo.inbox(id: inboxID)!)
        alias = repo.aliases.first { $0.id == id }!
        XCTAssertEqual(repo.resolvedDestination(for: alias), "work@company.com")
        XCTAssertEqual(repo.newAliasDestination(for: persona), "work@company.com")
        // 3) Per-alias pin beats the default.
        let otherID = try repo.addManualInbox(email: "alt@proton.me")
        alias.forwardingInboxID = otherID
        try repo.updateAlias(alias)
        XCTAssertEqual(repo.resolvedDestination(for: repo.aliases.first { $0.id == id }!), "alt@proton.me")
    }

    func testSetDefaultInboxIsExclusive() throws {
        let repo = makeRepo()
        let a = try repo.addManualInbox(email: "a@x.com")
        let b = try repo.addManualInbox(email: "b@x.com")
        try repo.setDefaultInbox(repo.inbox(id: a)!)
        try repo.setDefaultInbox(repo.inbox(id: b)!)
        XCTAssertEqual(repo.forwardingInboxes.filter(\.isDefault).map(\.id), [b])
    }

    // MARK: Delete guards

    func testDeleteInboxRefusedWhileAliasPinnedAndForDerived() throws {
        let repo = makeRepo()
        let persona = try makePersonaWithEmail(repo)
        // Derived profile inbox can't be deleted.
        let derived = repo.forwardingInboxes.first { $0.source == .personaProfile }!
        try repo.deleteInbox(derived)
        XCTAssertNotNil(repo.inbox(id: derived.id))
        // Manual inbox with a pinned alias can't be deleted…
        let manualID = try repo.addManualInbox(email: "work@x.com")
        let aliasID = try repo.createPersonaAlias(for: persona, forwardingInboxID: manualID)!
        try repo.deleteInbox(repo.inbox(id: manualID)!)
        XCTAssertNotNil(repo.inbox(id: manualID))
        // …until the alias is gone.
        try repo.deleteAlias(repo.aliases.first { $0.id == aliasID }!)
        try repo.deleteInbox(repo.inbox(id: manualID)!)
        XCTAssertNil(repo.inbox(id: manualID))
    }

    // MARK: Bulk-rotation pending set (journal-free resumability)

    func testAliasesNeedingRotationTracksDriftAndCheckpoints() throws {
        let repo = makeRepo()
        let persona = try makePersonaWithEmail(repo)
        let id = try repo.createPersonaAlias(for: persona)!
        // Reserved, not yet minted → never in the batch (nothing to rotate).
        XCTAssertTrue(repo.aliasesNeedingRotation.isEmpty)
        // Minted with the profile destination already applied → no drift.
        var alias = repo.aliases.first { $0.id == id }!
        alias.backendMinted = true
        alias.forwardingTarget = "me@real.com"
        try repo.updateAlias(alias)
        XCTAssertTrue(repo.aliasesNeedingRotation.isEmpty)
        // Default inbox changes → the alias drifts into the batch.
        let workID = try repo.addManualInbox(email: "work@company.com")
        try repo.setDefaultInbox(repo.inbox(id: workID)!)
        XCTAssertEqual(repo.aliasesNeedingRotation.map(\.id), [id])
        // Checkpoint (what reconcile does after a successful rotate) → batch empties.
        var rotated = repo.aliases.first { $0.id == id }!
        rotated.forwardingTarget = "work@company.com"
        try repo.updateAlias(rotated)
        XCTAssertTrue(repo.aliasesNeedingRotation.isEmpty)
    }

    func testEraseAllRemovesInboxRecords() throws {
        let repo = makeRepo()
        _ = try repo.addManualInbox(email: "a@x.com")
        XCTAssertFalse(repo.store.allInboxRecords().isEmpty)
        try repo.store.eraseAll()
        XCTAssertTrue(repo.store.allInboxRecords().isEmpty)
    }
}
