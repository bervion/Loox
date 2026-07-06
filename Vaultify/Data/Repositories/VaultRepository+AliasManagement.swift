import Foundation
import SwiftData

/// Alias create/update/delete + flag-guarded status changes. All writes re-seal
/// under the Vault Key and bump `updatedAt` (whole-record LWW); delete is a
/// tombstone. A persona has at most one persona-tier alias.
extension VaultRepository {

    /// Reserve the persona's single stable alias (≤1 per persona). No-op if one
    /// already exists. `reserved`, never `active` — the relay backend isn't live.
    @discardableResult
    func createPersonaAlias(for persona: Persona) throws -> String? {
        guard personaAlias(forPersona: persona.id) == nil else { return nil }
        return try insertAlias(EmailAlias(
            personaId: persona.id,
            tier: .persona,
            localPart: AliasAddress.randomLocalPart(),
            status: .reserved,
            forwardingTarget: identityUsername(forPersona: persona),
            sortIndex: (aliases.map(\.sortIndex).max() ?? -1) + 1))
    }

    /// Reserve a unique per-site alias bound to a login item + its first website.
    @discardableResult
    func createPerSiteAlias(for persona: Persona, boundItemId: String) throws -> String {
        let domain = item(id: boundItemId).flatMap { $0.autofillHosts.first }
        return try insertAlias(EmailAlias(
            personaId: persona.id,
            tier: .perSite,
            localPart: AliasAddress.randomLocalPart(),
            boundItemId: boundItemId,
            boundDomain: domain,
            status: .reserved,
            forwardingTarget: identityUsername(forPersona: persona),
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
