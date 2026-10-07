import Foundation
import SwiftData

/// Alias create/update/delete + flag-guarded status changes. All writes re-seal
/// under the Vault Key and bump `updatedAt` (whole-record LWW); delete is a
/// tombstone. A persona has at most one persona-tier alias.
extension VaultRepository {

    enum AliasMutationError: Error {
        case unavailableDomain, unresolvedDomain, invalidOwner, staleRecord, immutableNamespace
    }

    /// Reserve a reusable (persona-tier) address — 0..N per persona, optionally
    /// labelled ("Clients"). `reserved`, never `active`, until the relay confirms.
    @discardableResult
    func createPersonaAlias(for persona: Persona, label: String? = nil,
                            forwardingInboxID: String? = nil,
                            domainID: String = AuxiliaryDomainRegistry.defaultEmailDomainID) throws -> String? {
        try validateAliasOwner(persona: persona)
        let mapping = try creationMapping(domainID: domainID)
        return try insertAlias(EmailAlias(
            personaId: persona.id,
            tier: .persona,
            localPart: AliasAddress.randomLocalPart(),
            label: label,
            status: .reserved,
            forwardingInboxID: forwardingInboxID,
            forwardingTarget: newAliasDestination(for: persona),
            relayDomainID: domainID,
            relayHostnameSnapshot: mapping.hostname,
            relayDomainMappingProof: mapping.proof,
            sortIndex: (aliases.map(\.sortIndex).max() ?? -1) + 1))
    }

    /// Reserve a unique per-site alias. `boundItemId` may be nil when the login
    /// doesn't exist yet (create-login flow binds it on save); `domain` overrides
    /// the hint derived from the bound item's first website.
    @discardableResult
    func createPerSiteAlias(for persona: Persona, boundItemId: String?,
                            domain: String? = nil,
                            domainID: String = AuxiliaryDomainRegistry.defaultEmailDomainID,
                            label: String? = nil,
                            forwardingInboxID: String? = nil) throws -> String {
        try validateAliasOwner(persona: persona)
        if let boundItemId {
            guard items(for: persona).contains(where: { $0.id == boundItemId && $0.category == .login })
            else { throw AliasMutationError.invalidOwner }
        }
        let mapping = try creationMapping(domainID: domainID)
        let domain = domain ?? boundItemId.flatMap { item(id: $0)?.autofillHosts.first }
        return try insertAlias(EmailAlias(
            personaId: persona.id,
            tier: .perSite,
            localPart: AliasAddress.randomLocalPart(),
            boundItemId: boundItemId,
            boundDomain: domain,
            label: label,
            status: .reserved,
            forwardingInboxID: forwardingInboxID,
            forwardingTarget: newAliasDestination(for: persona),
            relayDomainID: domainID,
            relayHostnameSnapshot: mapping.hostname,
            relayDomainMappingProof: mapping.proof,
            sortIndex: (aliases.map(\.sortIndex).max() ?? -1) + 1))
    }

    /// Move an alias to a new status, gated by the relay flag: a request for a
    /// relay-only state (`active`/`paused`) while the relay is off is a no-op.
    func setAliasStatus(_ alias: EmailAlias, to status: AliasStatus) throws {
        guard AliasLifecycle.canTransition(from: alias.status, to: status,
                                           flag: RelayFeature.activeAliasesEnabled) else { return }
        var updated = alias
        updated.status = status
        updated.disabledAt = status == .disabled ? .now : nil
        try updateAlias(updated)
    }

    /// Checkpoint that the backend has minted this alias, so a resumed activation
    /// skips createAlias (avoids orphaning the first mint on a collision retry).
    func markMinted(_ alias: EmailAlias) throws {
        guard let live = aliases.first(where: { $0.id == alias.id }),
              live.personaId == alias.personaId,
              live.relayDomainID == alias.relayDomainID, live.localPart == alias.localPart
        else { throw AliasMutationError.staleRecord }
        guard !live.backendMinted else { return }
        var updated = live
        if updated.relayHostnameSnapshot == nil {
            guard let hostname = updated.emailDomain else { throw AliasMutationError.unresolvedDomain }
            updated.relayHostnameSnapshot = hostname
            updated.relayDomainMappingProof = AuxiliaryDomainRegistry.signedMappingEnvelope
        }
        updated.backendMinted = true
        try updateAlias(updated)
    }

    func updateAlias(_ alias: EmailAlias) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = store.aliasRecord(id: alias.id) else { return }
        guard let live = aliases.first(where: { $0.id == alias.id }), record.deletedAt == nil,
              live.updatedAt == alias.updatedAt, live.relationRevision == alias.relationRevision
        else { throw AliasMutationError.staleRecord }
        if live.backendMinted || live.status == .active || live.status == .paused || live.status == .disabled {
            guard live.relayDomainID == alias.relayDomainID, live.localPart == alias.localPart,
                  live.relayHostnameSnapshot == nil || live.relayHostnameSnapshot == alias.relayHostnameSnapshot,
                  live.relayDomainMappingProof == nil || live.relayDomainMappingProof == alias.relayDomainMappingProof
            else { throw AliasMutationError.immutableNamespace }
        }
        guard alias.personaId == live.personaId else { throw AliasMutationError.invalidOwner }
        var updated = alias
        updated.updatedAt = .now
        let sealed = try sealAlias(updated, key: key)
        record.sealed = sealed
        record.sortIndex = updated.sortIndex
        record.updatedAt = updated.updatedAt
        record.dirty = true
        do { try store.context.save() }
        catch { store.context.rollback(); throw error }
        reload()
        noteLocalMutation()
    }

    func deleteAlias(_ alias: EmailAlias) throws {
        try tombstoneAlias(id: alias.id)
        try store.context.save()
        reload()
        noteLocalMutation()
    }

    /// Tombstone every alias owned by a persona — called when the persona is
    /// deleted so no orphan aliases remain.
    func deleteAliases(forPersona personaId: String) {
        let owned = aliases.filter { $0.personaId == personaId }
        guard !owned.isEmpty else { return }
        for alias in owned { try? tombstoneAlias(id: alias.id) }
        try? store.context.save()
    }

    // MARK: Internals

    private func validateAliasOwner(persona: Persona) throws {
        guard personas.contains(where: { $0.id == persona.id }) else {
            throw AliasMutationError.invalidOwner
        }
    }

    private func creationMapping(domainID: String) throws -> (hostname: String, proof: Data?) {
        guard let domain = AuxiliaryDomainRegistry.descriptor(id: domainID),
              domain.offersPrivateEmail, domain.lifecycle.allowsCreation,
              let hostname = AuxiliaryDomainRegistry.emailDomain(forDomainID: domainID) else {
            throw AliasMutationError.unavailableDomain
        }
        return (hostname, AuxiliaryDomainRegistry.signedMappingEnvelope)
    }

    /// Verified-only sealed migration. Sync strings never provide their own
    /// trust. Current config can backfill a missing old mapping; an existing
    /// snapshot is not replaced if the signed registry later changes.
    func backfillTrustedAliasDomains() throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        var staged: [(EmailAliasRecord, EmailAlias, Data)] = []
        for alias in aliases where alias.relayHostnameSnapshot == nil {
            guard let hostname = AuxiliaryDomainRegistry.emailDomain(forDomainID: alias.relayDomainID),
                  let record = store.aliasRecord(id: alias.id), record.deletedAt == nil else { continue }
            var updated = alias
            updated.relayHostnameSnapshot = hostname
            updated.relayDomainMappingProof = AuxiliaryDomainRegistry.signedMappingEnvelope
            updated.updatedAt = .now
            staged.append((record, updated, try sealAlias(updated, key: key)))
        }
        guard !staged.isEmpty else { return }
        for (record, alias, sealed) in staged {
            record.sealed = sealed
            record.updatedAt = alias.updatedAt
            record.dirty = true
        }
        do { try store.context.save() }
        catch { store.context.rollback(); throw error }
        reload()
        noteLocalMutation()
    }

    @discardableResult
    private func insertAlias(_ alias: EmailAlias) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let record = EmailAliasRecord(id: alias.id,
                                      sealed: try sealAlias(alias, key: key),
                                      sortIndex: alias.sortIndex,
                                      createdAt: alias.createdAt,
                                      updatedAt: alias.updatedAt)
        store.context.insert(record)
        do { try store.context.save() }
        catch { store.context.rollback(); throw error }
        reload()
        noteLocalMutation()
        return alias.id
    }

    private func tombstoneAlias(id: String) throws {
        guard let record = store.aliasRecord(id: id) else { return }
        record.deletedAt = .now
        record.updatedAt = .now
        record.dirty = true
    }
}
