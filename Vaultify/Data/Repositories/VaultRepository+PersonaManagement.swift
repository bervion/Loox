import Foundation
import SwiftData

/// Whether a persona may be deleted. Mirrors the identity-removal gate: there
/// must always be at least one persona, and the default can't be removed until
/// another is promoted.
nonisolated enum PersonaRemovalGate: Equatable {
    case ok
    case lastPersona
    case defaultPersona
}

/// Persona edit/delete + policy-aware create. All writes re-seal under the Vault
/// Key and bump `updatedAt` so they survive the whole-record last-writer-wins
/// pull; delete is a tombstone, not a hard delete (sync-safe).
extension VaultRepository {

    func personaRemovalGate(_ persona: Persona) -> PersonaRemovalGate {
        if personas.count <= 1 { return .lastPersona }
        if persona.isDefault { return .defaultPersona }
        return .ok
    }

    /// Create a persona with an explicit isolation policy.
    @discardableResult
    func addPersona(displayName: String, kind: PersonaKind,
                    isolationPolicy: PersonaIsolationPolicy) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let persona = Persona(displayName: displayName, kind: kind, isolationPolicy: isolationPolicy,
                              primarySpaceID: folders.first?.id,
                              sortIndex: (personas.map(\.sortIndex).max() ?? -1) + 1)
        let record = PersonaRecord(id: persona.id,
                                   sealed: try sealPersona(persona, key: key),
                                   isDefault: false,
                                   sortIndex: persona.sortIndex,
                                   createdAt: persona.createdAt,
                                   updatedAt: persona.updatedAt)
        store.context.insert(record)
        try store.context.save()
        reload()
        noteLocalMutation()
        return persona.id
    }

    /// Re-seal a persona's identity content (name/kind/policy/links) and bump
    /// `updatedAt`. The `isDefault` flag is managed only by `setDefaultPersona`.
    func updatePersona(_ persona: Persona) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = store.personaRecord(id: persona.id) else { return }
        var updated = persona
        updated.updatedAt = .now
        record.sealed = try sealPersona(updated, key: key)
        record.sortIndex = updated.sortIndex
        record.updatedAt = updated.updatedAt
        record.dirty = true
        try store.context.save()
        reload()
        noteLocalMutation()
    }

    /// Tombstone a persona (guarded). Personas don't own items yet, so no item
    /// reassignment is needed — just a soft-delete that propagates via sync.
    func deletePersona(_ persona: Persona) throws {
        guard personaRemovalGate(persona) == .ok else { return }
        guard let record = store.personaRecord(id: persona.id) else { return }
        record.deletedAt = .now
        record.updatedAt = .now
        record.dirty = true
        // Cascade: tombstone this persona's aliases so none are orphaned.
        deleteAliases(forPersona: persona.id)
        try store.context.save()
        reload()
        noteLocalMutation()
    }
}
