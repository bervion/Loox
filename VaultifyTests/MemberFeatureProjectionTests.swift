import XCTest
@testable import Vaultify

@MainActor final class MemberFeatureProjectionTests: XCTestCase {
    private let personal = Persona(id: "personal", displayName: "Personal", kind: .personal, isDefault: true)
    private let work = Persona(id: "work", displayName: "Work", kind: .professional)
    private var folders: [Folder] {
        [Folder(id: "personal-space", name: "Personal", personaId: "personal"),
         Folder(id: "work-space", name: "Work", personaId: "work"),
         Folder(id: "legacy-space", name: "Legacy")]
    }
    private var items: [VaultItem] {
        [VaultItem(id: "unfiled", category: .login, title: "Unfiled"),
         VaultItem(id: "personal-item", category: .login, title: "Personal", folderId: "personal-space"),
         VaultItem(id: "work-item", category: .login, title: "Work", folderId: "work-space"),
         VaultItem(id: "legacy-item", category: .login, title: "Legacy", folderId: "legacy-space"),
         VaultItem(id: "missing-folder", category: .login, title: "Unknown owner", folderId: "deleted-space")]
    }

    private func owned(_ persona: Persona?) -> [VaultItem] {
        MemberFeatureProjection.ownedItems(items: items, folders: folders, persona: persona, defaultPersonaID: personal.id)
    }

    func testNilPrimarySpaceDoesNotGrantAllItemsAndMissingFolderFailsClosed() {
        XCTAssertNil(work.primarySpaceID)
        XCTAssertEqual(Set(owned(work).map(\.id)), ["work-item"])
        XCTAssertEqual(Set(owned(personal).map(\.id)), ["unfiled", "personal-item", "legacy-item"])
        XCTAssertFalse(owned(personal).contains { $0.id == "missing-folder" })
        XCTAssertTrue(owned(nil).isEmpty)
    }

    func testMoveChangesAllMetadataProjectionsWithoutReassigningOrphans() {
        let now = Date(timeIntervalSince1970: 2_000)
        let record = LooxLinkRecord(shareId: "link", revokeToken: "retained", itemId: "work-item",
                                    createdAt: now, expiresAt: now.addingTimeInterval(300))
        let attempt = QuickViewHistoryRow(itemID: "work-item", timestamp: now, result: .completed)
        XCTAssertTrue(MemberFeatureProjection.links([record], ownedItems: owned(personal), now: now).isEmpty)
        XCTAssertEqual(MemberFeatureProjection.browserAttempts([attempt], ownedItems: owned(work)), [attempt])

        var moved = items
        moved[2].folderId = "personal-space"
        let newPersonal = MemberFeatureProjection.ownedItems(items: moved, folders: folders, persona: personal,
                                                            defaultPersonaID: personal.id)
        let newWork = MemberFeatureProjection.ownedItems(items: moved, folders: folders, persona: work,
                                                        defaultPersonaID: personal.id)
        XCTAssertEqual(MemberFeatureProjection.links([record], ownedItems: newPersonal, now: now), [record])
        XCTAssertTrue(MemberFeatureProjection.browserAttempts([attempt], ownedItems: newWork).isEmpty)
    }

    func testDeletedAndExpiredLinksStayOutsideListWithoutMutatingCleanupCredentials() {
        let now = Date(timeIntervalSince1970: 2_000)
        let live = LooxLinkRecord(shareId: "live", revokeToken: "r1", itemId: "work-item",
                                  createdAt: now, expiresAt: now.addingTimeInterval(1))
        let expired = LooxLinkRecord(shareId: "expired", revokeToken: "r2", itemId: "work-item",
                                     createdAt: now, expiresAt: now)
        let orphan = LooxLinkRecord(shareId: "orphan", revokeToken: "r3", itemId: "deleted-item",
                                    createdAt: now, expiresAt: now.addingTimeInterval(300))
        let records = [live, expired, orphan]
        XCTAssertEqual(MemberFeatureProjection.links(records, ownedItems: owned(work), now: now), [live])
        XCTAssertEqual(records.map(\.revokeToken), ["r1", "r2", "r3"], "Filtering must not erase revoke credentials")
    }

    func testExtraProtectedAndUnsupportedItemsCannotEnterSnapshotChooser() {
        var supported = VaultItem(id: "supported", category: .login, title: "Readable", fields: [
            DynamicField(label: "Username", kind: .username, value: "owner")])
        let protectedOnly = VaultItem(id: "protected", category: .login, title: "Protected", fields: [
            DynamicField(label: "Password", kind: .password, value: "v2g:ciphertext", guard2: true)])
        var unsupported = supported
        unsupported.id = "future"; unsupported.semantics = ItemSemantics(schemaVersion: ItemSemantics.supported + 1)
        var trashed = supported
        trashed.id = "trash"; trashed.trashedAt = .now
        supported.archived = false
        XCTAssertEqual(MemberFeatureProjection.eligibleItems([supported, protectedOnly, unsupported, trashed],
                                                             needsSnapshotFields: true).map(\.id), ["supported"])
        XCTAssertEqual(Set(MemberFeatureProjection.eligibleItems([supported, protectedOnly],
                                                                 needsSnapshotFields: false).map(\.id)),
                       ["supported", "protected"])
    }

    func testFamilySharesKeepRealLifecycleAndScopeSharedZoneByItem() {
        let pending = ItemShareRecord(itemId: "work-item", zoneName: "same-zone", recipientLabel: "person@example.com",
                                      createdAtUnixMs: 1, fingerprintConfirmed: false, statusRaw: "accepted")
        let otherPersona = ItemShareRecord(itemId: "personal-item", zoneName: "same-zone", recipientLabel: "person@example.com",
                                           createdAtUnixMs: 1, fingerprintConfirmed: true)
        let orphan = ItemShareRecord(itemId: "deleted", zoneName: "orphan", recipientLabel: "hidden@example.com",
                                     createdAtUnixMs: 1, fingerprintConfirmed: false)
        let projected = MemberFeatureProjection.outgoingShares([pending, otherPersona, orphan], ownedItems: owned(work))
        XCTAssertEqual(projected.map(\.id), [pending.id])
        XCTAssertEqual(projected.first?.status, .accepted)
        XCTAssertEqual(projected.first?.recipientLabel, "person@example.com")
    }

    func testHistoryPreservesLocalOutcomeAndContainsNoReplayData() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let rows = [QuickViewHistoryRow(itemID: "work-item", timestamp: now, result: .failed),
                    QuickViewHistoryRow(itemID: "personal-item", timestamp: now, result: .completed),
                    QuickViewHistoryRow(itemID: "missing-folder", timestamp: now, result: .cancelled)]
        let result = MemberFeatureProjection.browserAttempts(rows, ownedItems: owned(work))
        XCTAssertEqual(result.map(\.result), [.failed])
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [[String: Any]])
        XCTAssertEqual(Set(dictionary[0].keys), ["itemID", "timestamp", "result"])
    }

    private func makeFlow() throws -> (VaultRepository, QuickViewApprovalFlowModel, QuickViewHistoryStore) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "member-projection-\(UUID().uuidString)"))
        let session = VaultSession(settings: SettingsStore(defaults: defaults, mirrorToSharedConfig: false))
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32), publishSharedSession: false)
        let repository = VaultRepository(store: VaultStore(inMemory: true), session: session, externalSideEffectsEnabled: false)
        repository.reload()
        try repository.add(VaultItem(id: "flow-item", category: .login, title: "Account", fields: [
            DynamicField(label: "Username", kind: .username, value: "owner")]))
        let history = QuickViewHistoryStore(persistenceEnabled: false)
        let flow = QuickViewApprovalFlowModel(itemID: "flow-item", defaultSelectedFieldIDs: [],
                                              vaultSession: session, repository: repository, history: history)
        flow.state = .verified(.init(sessionID: "s", sessionIDBytes: Data([1]), sas: "apple river 42",
                                     browserEncPublicKey: Data([4]), browserEncKeyHash: Data(), browserSigKeyHash: Data(),
                                     env: "staging", expiresAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000) + 100_000))
        TestLifetimeRetainer.retain(repository, session)
        return (repository, flow, history)
    }

    func testBrowserApprovalFailsBeforeBiometricsAfterProfileChange() async throws {
        let (repository, flow, history) = try makeFlow()
        let otherID = try repository.addPersona(displayName: "Other", kind: .professional)
        repository.setActivePersona(otherID)
        await flow.approve()
        guard case .error = flow.state else { return XCTFail("Stale profile approval must fail before any biometric or upload") }
        XCTAssertTrue(history.rows.isEmpty)
    }

    func testBrowserApprovalFailsWhenItemMovesToUnknownFolder() async throws {
        let (repository, flow, history) = try makeFlow()
        var item = try XCTUnwrap(repository.item(id: "flow-item"))
        item.folderId = "missing-folder"
        try repository.update(item)
        await flow.approve()
        guard case .error = flow.state else { return XCTFail("Unknown ownership must fail before approval") }
        XCTAssertTrue(history.rows.isEmpty)
    }

    func testBrowserCancellationIsRecordedOnceAndCompletedAttemptIsNotRelabeled() throws {
        let (_, flow, history) = try makeFlow()
        flow.cancel()
        flow.cancel()
        XCTAssertEqual(history.rows.map(\.result), [.cancelled])
        flow.state = .done
        flow.cancel()
        XCTAssertEqual(flow.state, .done)
        XCTAssertEqual(history.rows.map(\.result), [.cancelled])
    }
}
