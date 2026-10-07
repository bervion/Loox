import Foundation
import SwiftData

extension VaultRepository {
    enum AliasLinkFailure: Error, Equatable {
        case missingAlias
        case unresolvedAddress
        case wrongPersona
        case unavailableLogin
        case staleRelation
        case field(AliasWriteback.Failure)
    }

    func linkedServices(for personaID: String, aliasID: String? = nil) -> [AliasLinkedService] {
        guard activePersona?.id == personaID, let persona = personas.first(where: { $0.id == personaID }) else { return [] }
        return AliasLinkedServices.project(items: items(for: persona), aliases: aliases,
                                            personaID: personaID, aliasID: aliasID)
    }

    func legacyAliasCandidates(for personaID: String, aliasID: String? = nil) -> [AliasLinkedService] {
        guard activePersona?.id == personaID, let persona = personas.first(where: { $0.id == personaID }) else { return [] }
        return AliasLinkedServices.project(items: items(for: persona), aliases: aliases,
                                            personaID: personaID, aliasID: aliasID, legacyReview: true)
    }

    /// Synchronous local linking. Neither the alias's backend state nor the
    /// Login's real Email/username is changed. A primary legacy pointer is a hint.
    func linkAliasToLogin(aliasID: String, itemID: String,
                          expectedItemUpdatedAt: Date? = nil,
                          expectedAliasRevision: UInt64? = nil) throws {
        let (alias, login) = try ownedAliasLogin(aliasID: aliasID, itemID: itemID)
        guard expectedItemUpdatedAt == nil || login.updatedAt == expectedItemUpdatedAt,
              expectedAliasRevision == nil || alias.relationRevision == expectedAliasRevision else {
            throw AliasLinkFailure.staleRelation
        }
        guard let address = alias.resolvedAddress else { throw AliasLinkFailure.unresolvedAddress }
        let updated: VaultItem
        do { updated = try AliasWriteback.linking(login, address: address) }
        catch let failure as AliasWriteback.Failure { throw AliasLinkFailure.field(failure) }
        var linked = alias
        if linked.boundItemId == nil { linked.boundItemId = login.id }
        if linked.boundDomain == nil { linked.boundDomain = login.autofillHost }
        guard updated != login || linked != alias else { return }
        linked.relationRevision &+= 1
        try commitAliasRelation(item: updated, alias: linked)
    }

    /// The displayed row is an exact confirmation snapshot, not a wildcard.
    /// Field removal and matching primary-pointer clear share one store save.
    func unlinkAliasFromLogin(_ link: AliasLinkedService) throws {
        guard !link.isLegacyCandidate else { throw AliasLinkFailure.staleRelation }
        let (alias, login) = try ownedAliasLogin(aliasID: link.aliasID, itemID: link.itemID)
        guard alias.personaId == link.personaID, alias.resolvedAddress == link.address,
              login.updatedAt == link.itemUpdatedAt,
              alias.relationRevision == link.aliasRelationRevision else { throw AliasLinkFailure.staleRelation }
        let updated: VaultItem
        do { updated = try AliasWriteback.unlinking(login, fieldID: link.fieldID, address: link.address) }
        catch let failure as AliasWriteback.Failure { throw AliasLinkFailure.field(failure) }
        var unlinked = alias
        if unlinked.boundItemId == login.id { unlinked.boundItemId = nil }
        unlinked.relationRevision &+= 1
        try commitAliasRelation(item: updated, alias: unlinked)
    }

    /// An old editor may contain a canonical field that was unlinked on another
    /// surface while it was open. Reject that snapshot before any artifact/item
    /// save so it cannot silently resurrect the relationship.
    func validateAliasEditorBaseline(_ original: VaultItem) throws {
        guard let live = item(id: original.id), live.sharedOrigin == nil else {
            throw AliasLinkFailure.unavailableLogin
        }
        guard AliasWriteback.canonicalFields(on: live) == AliasWriteback.canonicalFields(on: original) else {
            throw AliasLinkFailure.staleRelation
        }
    }

    /// An editor detach clears the primary pointer in the same commit as the
    /// removed canonical field. Other edits keep the live relation untouched.
    func updateLoginFromEditor(_ edited: VaultItem, baseline: VaultItem) throws {
        try validateAliasEditorBaseline(baseline)
        let before = AliasWriteback.canonicalFields(on: baseline)
        let after = AliasWriteback.canonicalFields(on: edited)
        if before != after, !before.isEmpty {
            guard !ExtraProtectionDelete.blocks(before, level2Key: session.level2Key?.bytes) else {
                throw AliasLinkFailure.field(.protectedField)
            }
            // Intentional removal/repair is already authorized by the editor's
            // protection gate. Never silently replace one readable alias with another.
            if let old = try? AliasWriteback.readableField(on: baseline),
               let new = try? AliasWriteback.readableField(on: edited),
               !old.isEmpty, !new.isEmpty, old.value != new.value {
                throw AliasLinkFailure.field(.conflictingAddress)
            }
            let primary = aliases.filter { $0.personaId == activePersona?.id && $0.boundItemId == edited.id }
            if after.isEmpty, let alias = primary.first {
                guard primary.count == 1 else { throw AliasLinkFailure.staleRelation }
                var unlinked = alias
                unlinked.boundItemId = nil
                unlinked.relationRevision &+= 1
                try commitAliasRelation(item: edited, alias: unlinked)
                return
            }
            // N-association removal without a primary pointer must still advance
            // the alias generation to invalidate any delayed editor writeback.
            if after.isEmpty, let old = try? AliasWriteback.readableField(on: baseline),
               let alias = aliases.first(where: { $0.personaId == activePersona?.id && $0.resolvedAddress == old.value }) {
                var unlinked = alias
                unlinked.relationRevision &+= 1
                try commitAliasRelation(item: edited, alias: unlinked)
                return
            }
        }
        try update(edited)
    }

    func validatePendingAlias(aliasID: String, personaID: String?, relationRevision: UInt64?) throws -> EmailAlias {
        guard let alias = aliases.first(where: { $0.id == aliasID }) else { throw AliasLinkFailure.missingAlias }
        guard alias.personaId == personaID, activePersona?.id == alias.personaId else { throw AliasLinkFailure.wrongPersona }
        guard alias.resolvedAddress != nil else { throw AliasLinkFailure.unresolvedAddress }
        guard relationRevision == nil || relationRevision == alias.relationRevision else { throw AliasLinkFailure.staleRelation }
        return alias
    }

    private func ownedAliasLogin(aliasID: String, itemID: String) throws -> (EmailAlias, VaultItem) {
        guard session.vaultKey != nil else { throw AuthError.locked }
        guard let alias = aliases.first(where: { $0.id == aliasID }) else { throw AliasLinkFailure.missingAlias }
        guard activePersona?.id == alias.personaId,
              let persona = personas.first(where: { $0.id == alias.personaId }) else { throw AliasLinkFailure.wrongPersona }
        guard let login = items(for: persona).first(where: { $0.id == itemID }), login.category == .login,
              login.sharedOrigin == nil, !login.isUnsupportedSchema else { throw AliasLinkFailure.unavailableLogin }
        return (alias, login)
    }

    private func commitAliasRelation(item: VaultItem, alias: EmailAlias) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let itemRecord = store.record(id: item.id), itemRecord.deletedAt == nil,
              let aliasRecord = store.aliasRecord(id: alias.id), aliasRecord.deletedAt == nil else {
            throw AliasLinkFailure.staleRelation
        }
        var updatedItem = item
        var updatedAlias = alias
        let now = Date()
        updatedItem.updatedAt = now
        updatedAlias.updatedAt = now
        // Seal both before mutating either record. SwiftData's single save commits
        // both records atomically. Restore in-context snapshots on failure.
        let itemSealed = try AESGCM.seal(JSONEncoder().encode(updatedItem.secret), key: key)
        let aliasSealed = try sealAlias(updatedAlias, key: key)
        let oldItem = (itemRecord.sealed, itemRecord.updatedAt, itemRecord.dirty,
                       itemRecord.favorite, itemRecord.rotateDays, itemRecord.passwordChangedAt)
        let previousPassword = self.item(id: item.id)?.passwordField?.value
        let oldAlias = (aliasRecord.sealed, aliasRecord.updatedAt, aliasRecord.dirty)
        do {
            itemRecord.sealed = itemSealed
            itemRecord.updatedAt = now
            itemRecord.dirty = true
            itemRecord.favorite = updatedItem.favorite
            itemRecord.rotateDays = updatedItem.rotateDays
            if previousPassword != updatedItem.passwordField?.value { itemRecord.passwordChangedAt = now }
            aliasRecord.sealed = aliasSealed
            aliasRecord.updatedAt = now
            aliasRecord.dirty = true
            #if DEBUG
            if let save = aliasRelationSaveOverride { try save() }
            else { try store.context.save() }
            #else
            try store.context.save()
            #endif
        } catch {
            itemRecord.sealed = oldItem.0
            itemRecord.updatedAt = oldItem.1
            itemRecord.dirty = oldItem.2
            itemRecord.favorite = oldItem.3
            itemRecord.rotateDays = oldItem.4
            itemRecord.passwordChangedAt = oldItem.5
            aliasRecord.sealed = oldAlias.0
            aliasRecord.updatedAt = oldAlias.1
            aliasRecord.dirty = oldAlias.2
            throw error
        }
        reload()
        noteLocalMutation()
        didCommitItemUpdate(updatedItem, passwordChangedAt: itemRecord.passwordChangedAt)
    }
}

extension VaultRepository.AliasLinkFailure {
    var userMessage: String {
        switch self {
        case .missingAlias: appString("This private address no longer exists. Choose another address.")
        case .unresolvedAddress: appString("This address’s domain could not be verified. Open Private Email to review it.")
        case .wrongPersona, .unavailableLogin: appString("This login is unavailable in the current identity.")
        case .staleRelation: appString("This link changed while the screen was open. Reopen the login and try again.")
        case .field(.protectedField): appString("Open the login and unlock its protected field before changing this link.")
        case .field(.duplicateFields): appString("This login has more than one Private email field. Open it to review the fields.")
        case .field(.conflictingAddress): appString("This login already uses another private address. Choose another login or unlink it first.")
        case .field(.staleField): appString("This link changed while the screen was open. Reopen the login and try again.")
        }
    }
}
