import XCTest
@testable import Vaultify

@MainActor
final class AliasLinkedServicesTests: XCTestCase {
    private func makeRepo() -> VaultRepository {
        let suite = UserDefaults(suiteName: "alias-links-\(UUID().uuidString)")!
        let session = VaultSession(settings: SettingsStore(defaults: suite))
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session,
                                   externalSideEffectsEnabled: false)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    private func addLogin(_ title: String, repository: VaultRepository, folderID: String? = nil) throws -> String {
        let login = VaultItem(category: .login, title: title, folderId: folderID,
                              fields: [DynamicField(label: "Username", kind: .username, value: "original-user"),
                                       DynamicField(label: "Email", kind: .email, value: "original@real.test"),
                                       DynamicField(label: "Website", kind: .url, value: "https://github.com")])
        try repository.add(login)
        return login.id
    }

    func testEditorUnlinkSharesNormalPostCommitRotationEffects() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let loginID = try addLogin("Rotation", repository: repo)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID)
        let original = try XCTUnwrap(repo.item(id: loginID))
        var edited = original
        edited.fields.removeAll { $0.label == AliasWriteback.privateEmailLabel }
        edited.rotateDays = 0
        edited.fields.append(DynamicField(label: "Password", kind: .password, value: "new-fixture-password"))
        var observed: (VaultItem, Date?)?
        repo.itemUpdateCommitObserver = { item, baseline in observed = (item, baseline) }
        try repo.updateLoginFromEditor(edited, baseline: original)
        let effect = try XCTUnwrap(observed)
        XCTAssertEqual(effect.0.rotateDays, 0, "The shared scheduler receives cadence=0 to cancel the previous reminder")
        XCTAssertNil(effect.0.privateEmailValue)
        XCTAssertEqual(effect.0.passwordField?.value, "new-fixture-password")
        XCTAssertEqual(effect.1, repo.store.record(id: loginID)?.passwordChangedAt)
        XCTAssertNotNil(effect.1, "The new password baseline reaches the post-commit reminder effect")
    }

    func testOneAliasLinksToManyLoginsUnlinkOnlyOneAndPersistAtomically() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona, label: "Reusable"))
        let ids = try ["Facebook", "Gmail", "GitHub"].map { try addLogin($0, repository: repo) }
        for id in ids { try repo.linkAliasToLogin(aliasID: aliasID, itemID: id) }
        let links = repo.linkedServices(for: persona.id)
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(Set(links.map(\.aliasID)), [aliasID])
        let alias = try XCTUnwrap(repo.aliases.first { $0.id == aliasID })
        XCTAssertEqual(alias.boundItemId, ids.first, "Additional links never repoint the primary hint")
        let first = try XCTUnwrap(links.first { $0.itemID == ids.first })
        try repo.unlinkAliasFromLogin(first)
        repo.reload()
        XCTAssertEqual(repo.linkedServices(for: persona.id).count, 2)
        let unlinked = try XCTUnwrap(repo.item(id: ids[0]))
        XCTAssertNil(unlinked.privateEmailValue)
        XCTAssertEqual(unlinked.usernameField?.value, "original-user")
        XCTAssertEqual(unlinked.fields.first { $0.label == "Email" }?.value, "original@real.test")
        let live = try XCTUnwrap(repo.aliases.first { $0.id == aliasID })
        XCTAssertNil(live.boundItemId)
        XCTAssertEqual(live.localPart, alias.localPart)
        XCTAssertEqual(live.status, alias.status)
        XCTAssertEqual(live.forwardingTarget, alias.forwardingTarget)
        XCTAssertEqual(live.label, alias.label)
        XCTAssertEqual(live.relationRevision, alias.relationRevision + 1)
        XCTAssertThrowsError(try repo.unlinkAliasFromLogin(first), "Stale confirmation cannot remove another relation")
    }

    func testLegacyOrdinaryCredentialsRequireExplicitAdoptionAndNeverChange() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let address = try XCTUnwrap(repo.aliases.first { $0.id == aliasID }?.resolvedAddress)
        let login = VaultItem(category: .login, title: "Old GitHub",
            fields: [DynamicField(label: "Email", kind: .email, value: address)])
        try repo.add(login)
        XCTAssertTrue(repo.linkedServices(for: persona.id).isEmpty)
        let candidate = try XCTUnwrap(repo.legacyAliasCandidates(for: persona.id).first)
        XCTAssertTrue(candidate.isLegacyCandidate)
        XCTAssertThrowsError(try repo.unlinkAliasFromLogin(candidate))
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: login.id,
            expectedItemUpdatedAt: candidate.itemUpdatedAt, expectedAliasRevision: candidate.aliasRelationRevision)
        let linked = try XCTUnwrap(repo.linkedServices(for: persona.id).first)
        try repo.unlinkAliasFromLogin(linked)
        XCTAssertEqual(repo.item(id: login.id)?.fields.first?.value, address)
        XCTAssertNil(repo.item(id: login.id)?.privateEmailValue)
        XCTAssertTrue(repo.linkedServices(for: persona.id).isEmpty)
        // The explicit review may show the preserved ordinary credential again;
        // normal projection and automatic writers must never adopt it themselves.
        XCTAssertEqual(repo.legacyAliasCandidates(for: persona.id).count, 1)
    }

    func testProtectedDuplicateAndConflictingFieldsFailClosed() throws {
        let alias = EmailAlias(personaId: "p", tier: .persona, localPart: "sample")
        let address = try XCTUnwrap(alias.resolvedAddress)
        let fields = [
            [DynamicField(label: "Private email", kind: .email, value: "v2g:opaque", guard2: true)],
            [DynamicField(label: "Private email", kind: .email, value: address),
             DynamicField(label: "Private email", kind: .email, value: address)],
            [DynamicField(label: "Private email", kind: .email, value: "other@relay.test")]
        ]
        for fields in fields {
            let login = VaultItem(category: .login, title: "Conflict", fields: fields)
            XCTAssertThrowsError(try AliasWriteback.linking(login, address: address))
            XCTAssertEqual(AliasWriteback.upsertPrivateEmail(on: login, address: address), login)
        }
        let protected = VaultItem(category: .login, title: "Protected", fields: fields[0])
        let duplicate = VaultItem(category: .login, title: "Duplicate", fields: fields[1])
        XCTAssertTrue(AliasLinkedServices.project(items: [protected, duplicate], aliases: [alias], personaID: "p").isEmpty)
        XCTAssertNil(protected.privateEmailValue)
        XCTAssertNil(duplicate.privateEmailValue)
    }

    func testUnknownDomainNeverProjectsOrWritesBack() throws {
        let alias = EmailAlias(personaId: "p", tier: .perSite, localPart: "example",
                               relayDomainID: "unknown-mail-domain")
        let login = VaultItem(category: .login, title: "Unknown", fields: [
            DynamicField(label: "Private email", kind: .email, value: "example@relay.looxpassword.com")])
        XCTAssertNil(alias.resolvedAddress)
        XCTAssertTrue(AliasLinkedServices.project(items: [login], aliases: [alias], personaID: "p").isEmpty)
    }

    func testStaleEditorAndDelayedActivationCannotResurrectUnlinkedField() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try repo.createPerSiteAlias(for: persona, boundItemId: nil)
        let loginID = try addLogin("GitHub", repository: repo)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID)
        let before = try XCTUnwrap(repo.item(id: loginID))
        let alias = try XCTUnwrap(repo.aliases.first { $0.id == aliasID })
        let link = try XCTUnwrap(repo.linkedServices(for: persona.id).first)
        try repo.unlinkAliasFromLogin(link)
        XCTAssertThrowsError(try repo.validateAliasEditorBaseline(before))
        try repo.attachAliasToLogin(alias, expectedRelationRevision: alias.relationRevision)
        XCTAssertNil(repo.item(id: loginID)?.privateEmailValue)
        XCTAssertThrowsError(try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID,
            expectedAliasRevision: alias.relationRevision))
    }

    func testEditorDetachClearsPrimaryPointerInSameCommit() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let loginID = try addLogin("GitHub", repository: repo)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID)
        let before = try XCTUnwrap(repo.item(id: loginID))
        var draft = before
        draft.title = "GitHub renamed"
        draft.fields.removeAll { $0.label == "Private email" }
        try repo.updateLoginFromEditor(draft, baseline: before)
        repo.reload()
        XCTAssertEqual(repo.item(id: loginID)?.title, "GitHub renamed")
        XCTAssertNil(repo.item(id: loginID)?.privateEmailValue)
        XCTAssertNil(repo.aliases.first { $0.id == aliasID }?.boundItemId)
    }

    func testForeignPersonaAndMissingFolderAreExcludedAndBlocked() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let address = try XCTUnwrap(repo.aliases.first { $0.id == aliasID }?.resolvedAddress)
        let otherID = try repo.addPersona(displayName: "Other", kind: .professional, isolationPolicy: .isolated)
        let other = try XCTUnwrap(repo.personas.first { $0.id == otherID })
        for folder in [other.primarySpaceID, "missing-folder"] {
            var login = VaultItem(category: .login, title: "Foreign", folderId: folder)
            login = try AliasWriteback.linking(login, address: address)
            try repo.add(login)
            XCTAssertThrowsError(try repo.linkAliasToLogin(aliasID: aliasID, itemID: login.id))
        }
        XCTAssertTrue(repo.linkedServices(for: persona.id).isEmpty)
        XCTAssertTrue(repo.linkedServices(for: otherID).isEmpty)
    }

    func testFailedUnlinkRestoresBothRecordSnapshotsAndCanRetry() throws {
        enum SaveFailure: Error { case injected }
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let loginID = try addLogin("GitHub", repository: repo)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID)
        let link = try XCTUnwrap(repo.linkedServices(for: persona.id).first)
        let itemRecord = try XCTUnwrap(repo.store.record(id: loginID))
        let aliasRecord = try XCTUnwrap(repo.store.aliasRecord(id: aliasID))
        let beforeItem = (itemRecord.sealed, itemRecord.updatedAt, itemRecord.dirty)
        let beforeAlias = (aliasRecord.sealed, aliasRecord.updatedAt, aliasRecord.dirty)
        repo.aliasRelationSaveOverride = { throw SaveFailure.injected }
        XCTAssertThrowsError(try repo.unlinkAliasFromLogin(link))
        XCTAssertEqual(itemRecord.sealed, beforeItem.0)
        XCTAssertEqual(itemRecord.updatedAt, beforeItem.1)
        XCTAssertEqual(itemRecord.dirty, beforeItem.2)
        XCTAssertEqual(aliasRecord.sealed, beforeAlias.0)
        XCTAssertEqual(aliasRecord.updatedAt, beforeAlias.1)
        XCTAssertEqual(aliasRecord.dirty, beforeAlias.2)
        XCTAssertEqual(repo.linkedServices(for: persona.id).count, 1)
        repo.aliasRelationSaveOverride = nil
        repo.reload()
        XCTAssertEqual(repo.linkedServices(for: persona.id).count, 1)
        try repo.unlinkAliasFromLogin(link)
        repo.reload()
        XCTAssertTrue(repo.linkedServices(for: persona.id).isEmpty)
        XCTAssertNil(repo.aliases.first { $0.id == aliasID }?.boundItemId)
    }

    func testSameServiceAccountsRemainDistinctAndOneRemovalKeepsTheOther() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let firstID = try addLogin("GitHub", repository: repo)
        let secondID = try addLogin("GitHub", repository: repo)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: firstID)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: secondID)
        XCTAssertEqual(repo.linkedServices(for: persona.id).count, 2)
        let selected = try XCTUnwrap(repo.linkedServices(for: persona.id).first { $0.itemID == secondID })
        try repo.unlinkAliasFromLogin(selected)
        XCTAssertEqual(repo.linkedServices(for: persona.id).map(\.itemID), [firstID])
    }

    func testExplicitNoneAndAbsentAuthorizationAllowCanonicalLinkWhileStricterPoliciesBlock() throws {
        for authorization in [nil, ActionAuthorization.none] {
            let field = DynamicField(label: "Private email", kind: .email, value: "same@relay.test",
                semantics: FieldSemantics(actionAuthorization: authorization))
            let item = VaultItem(category: .login, title: "Allowed", fields: [field])
            XCTAssertEqual(try AliasWriteback.readableField(on: item)?.id, field.id)
            XCTAssertEqual(try AliasWriteback.linking(item, address: field.value), item)
            XCTAssertEqual(item.privateEmailValue, field.value)
        }
        for authorization in [ActionAuthorization.reauthenticate, .level2] {
            let field = DynamicField(label: "Private email", kind: .email, value: "same@relay.test",
                semantics: FieldSemantics(actionAuthorization: authorization))
            let item = VaultItem(category: .login, title: "Protected", fields: [field])
            XCTAssertThrowsError(try AliasWriteback.readableField(on: item))
            XCTAssertThrowsError(try AliasWriteback.linking(item, address: field.value))
            XCTAssertNil(item.privateEmailValue)
        }
        let alias = EmailAlias(personaId: "p", tier: .persona, localPart: "sample")
        let address = try XCTUnwrap(alias.resolvedAddress)
        for authorization in [nil, ActionAuthorization.none] {
            let canonical = VaultItem(category: .login, title: "Canonical", fields: [
                DynamicField(label: "Private email", kind: .email, value: address,
                    semantics: FieldSemantics(actionAuthorization: authorization))])
            let legacy = VaultItem(category: .login, title: "Legacy", fields: [
                DynamicField(label: "Email", kind: .email, value: address,
                    semantics: FieldSemantics(actionAuthorization: authorization))])
            XCTAssertEqual(AliasLinkedServices.project(items: [canonical], aliases: [alias], personaID: "p").count, 1)
            XCTAssertEqual(AliasLinkedServices.project(items: [legacy], aliases: [alias], personaID: "p", legacyReview: true).count, 1)
        }
    }

    private func restored(_ state: UIStateStore.DraftState) throws -> UIStateStore.DraftState {
        let key = SecureBytes([UInt8](repeating: 0x71, count: 32))
        let encrypted = try AESGCM.seal(JSONEncoder().encode(state), key: key)
        return try JSONDecoder().decode(UIStateStore.DraftState.self, from: AESGCM.open(encrypted, key: key))
    }

    func testRestoredExistingLoginLinkUsesOriginalBaselineAndSaves() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let alias = try XCTUnwrap(repo.aliases.first { $0.id == aliasID })
        let loginID = try addLogin("GitHub", repository: repo)
        let original = try XCTUnwrap(repo.item(id: loginID))
        let draft = try AliasWriteback.linking(original, address: try XCTUnwrap(alias.resolvedAddress))
        let recovered = try restored(.init(item: draft, isNew: false, aliasID: aliasID,
            aliasPersonaID: persona.id, aliasRelationRevision: alias.relationRevision, originalItem: original))
        XCTAssertEqual(recovered.editorBaseline, original)
        _ = try repo.validatePendingAlias(aliasID: aliasID, personaID: recovered.aliasPersonaID,
                                          relationRevision: recovered.aliasRelationRevision)
        try repo.updateLoginFromEditor(recovered.item, baseline: recovered.editorBaseline)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID,
                                 expectedAliasRevision: recovered.aliasRelationRevision)
        XCTAssertEqual(repo.linkedServices(for: persona.id).map(\.itemID), [loginID])
        XCTAssertEqual(repo.item(id: loginID)?.usernameField?.value, original.usernameField?.value)
    }

    func testRestoredExistingLoginUnlinkSavesAndTrueConcurrentUnlinkStillRejects() throws {
        let repo = makeRepo()
        let persona = try XCTUnwrap(repo.activePersona)
        let aliasID = try XCTUnwrap(repo.createPersonaAlias(for: persona))
        let loginID = try addLogin("GitHub", repository: repo)
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID)
        let original = try XCTUnwrap(repo.item(id: loginID))
        var draft = original
        draft.fields.removeAll { $0.label == AliasWriteback.privateEmailLabel }
        let recovered = try restored(.init(item: draft, isNew: false, originalItem: original))
        try repo.updateLoginFromEditor(recovered.item, baseline: recovered.editorBaseline)
        XCTAssertNil(repo.item(id: loginID)?.privateEmailValue)
        XCTAssertNil(repo.aliases.first { $0.id == aliasID }?.boundItemId)
        // The exact same recovered baseline is now genuinely stale after commit.
        XCTAssertThrowsError(try repo.updateLoginFromEditor(recovered.item, baseline: recovered.editorBaseline))
        try repo.linkAliasToLogin(aliasID: aliasID, itemID: loginID)
        let linked = try XCTUnwrap(repo.item(id: loginID))
        var edited = linked; edited.title = "Unsaved rename"
        let waiting = try restored(.init(item: edited, isNew: false, originalItem: linked))
        try repo.unlinkAliasFromLogin(try XCTUnwrap(repo.linkedServices(for: persona.id).first))
        XCTAssertThrowsError(try repo.updateLoginFromEditor(waiting.item, baseline: waiting.editorBaseline))
        XCTAssertNil(repo.item(id: loginID)?.privateEmailValue)
    }

    func testAliasContextSealedDraftRoundTripAndLegacyDecode() throws {
        let draft = UIStateStore.DraftState(item: VaultItem(category: .login, title: "GitHub"),
            isNew: true, aliasID: "alias", aliasPersonaID: "persona", aliasRelationRevision: 7)
        let roundTrip = try JSONDecoder().decode(UIStateStore.DraftState.self,
                                               from: JSONEncoder().encode(draft))
        XCTAssertEqual(roundTrip, draft)
        let legacy = UIStateStore.DraftState(item: draft.item, isNew: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "aliasID")
        object.removeValue(forKey: "aliasPersonaID")
        object.removeValue(forKey: "aliasRelationRevision")
        let decoded = try JSONDecoder().decode(UIStateStore.DraftState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.aliasID)
        XCTAssertNil(decoded.aliasPersonaID)
        XCTAssertNil(decoded.aliasRelationRevision)
    }
}
