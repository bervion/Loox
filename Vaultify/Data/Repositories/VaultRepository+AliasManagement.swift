import Foundation
import SwiftData

/// Alias create/update/delete + flag-guarded status changes. All writes re-seal
/// under the Vault Key and bump `updatedAt` (whole-record LWW); delete is a
/// tombstone. A persona has at most one persona-tier alias.
extension VaultRepository {

    /// Reserve a reusable (persona-tier) address — 0..N per persona, optionally
    /// labelled ("Clients"). `reserved`, never `active`, until the relay confirms.
    @discardableResult
    func createPersonaAlias(for persona: Persona, label: String? = nil,
                            forwardingInboxID: String? = nil,
                            domainID: String = AuxiliaryDomainRegistry.defaultEmailDomainID) throws -> String? {
        try insertAlias(EmailAlias(
            personaId: persona.id,
            tier: .persona,
            localPart: AliasAddress.randomLocalPart(),
            label: label,
            status: .reserved,
            forwardingInboxID: forwardingInboxID,
            forwardingTarget: newAliasDestination(for: persona),
            relayDomainID: domainID,
            sortIndex: (aliases.map(\.sortIndex).max() ?? -1) + 1))
    }

    /// Reserve a unique per-site alias. `boundItemId` may be nil when the login
    /// doesn't exist yet (create-login flow binds it on save); `domain` overrides
    /// the hint derived from the bound item's first website.
    @discardableResult
    func createPerSiteAlias(for persona: Persona, boundItemId: String?,
                            domain: String? = nil,
                            domainID: String = AuxiliaryDomainRegistry.defaultEmailDomainID) throws -> String {
        let domain = domain ?? boundItemId.flatMap { item(id: $0)?.autofillHosts.first }
        return try insertAlias(EmailAlias(
            personaId: persona.id,
            tier: .perSite,
            localPart: AliasAddress.randomLocalPart(),
            boundItemId: boundItemId,
            boundDomain: domain,
            status: .reserved,
            forwardingTarget: newAliasDestination(for: persona),
            relayDomainID: domainID,
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
        guard !alias.backendMinted else { return }
        var updated = alias
        updated.backendMinted = true
        try updateAlias(updated)
    }

    func updateAlias(_ alias: EmailAlias) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = store.aliasRecord(id: alias.id) else { return }
        var updated = alias
        updated.updatedAt = .now
        record.sealed = try sealAlias(updated, key: key)
        record.sortIndex = updated.sortIndex
        record.updatedAt = updated.updatedAt
        record.dirty = true
        try store.context.save()
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

    @discardableResult
    private func insertAlias(_ alias: EmailAlias) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let record = EmailAliasRecord(id: alias.id,
                                      sealed: try sealAlias(alias, key: key),
                                      sortIndex: alias.sortIndex,
                                      createdAt: alias.createdAt,
                                      updatedAt: alias.updatedAt)
        store.context.insert(record)
        try store.context.save()
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
