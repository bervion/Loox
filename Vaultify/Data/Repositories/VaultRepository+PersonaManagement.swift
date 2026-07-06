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

    /// Create a persona with an explicit isolation policy, and a starter Space it
    /// owns so its items have a home. The persona's `primarySpaceID` points at that
    /// starter — never another persona's Space (the pre-partition leak).
    @discardableResult
    func addPersona(displayName: String, kind: PersonaKind,
                    isolationPolicy: PersonaIsolationPolicy) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let personaID = UUID().uuidString

        // Starter Space owned by the new persona.
        let starter = Folder(name: displayName, iconAsset: "ic_folder", color: .blue,
                             sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1,
                             personaId: personaID)
        let folderRecord = FolderRecord(id: starter.id,
                                        sealed: try sealFolder(starter, key: key),
                                        iconAsset: starter.iconAsset,
                                        colorRaw: starter.color.rawValue,
                                        sortIndex: starter.sortIndex,
                                        createdAt: starter.createdAt,
                                        updatedAt: starter.updatedAt)
        store.context.insert(folderRecord)

        let persona = Persona(id: personaID, displayName: displayName, kind: kind,
                              isolationPolicy: isolationPolicy, primarySpaceID: starter.id,
                              sortIndex: (personas.map(\.sortIndex).max() ?? -1) + 1)
        let personaRecord = PersonaRecord(id: persona.id,
                                          sealed: try sealPersona(persona, key: key),
                                          isDefault: false,
                                          sortIndex: persona.sortIndex,
                                          createdAt: persona.createdAt,
                                          updatedAt: persona.updatedAt)
        store.context.insert(personaRecord)
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

    /// Tombstone a persona (guarded). Its Spaces (and thereby their items) are
    /// REASSIGNED to the default persona — never destroyed — so deleting an
    /// identity never loses user data. Aliases are cascaded (tombstoned).
    func deletePersona(_ persona: Persona) throws {
        guard personaRemovalGate(persona) == .ok else { return }
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = store.personaRecord(id: persona.id),
              let defaultID = defaultPersona?.id else { return }

        // Reassign owned Spaces → default (batched into the single save below).
        for folder in folders where folder.personaId == persona.id {
            guard let folderRecord = store.folderRecord(id: folder.id) else { continue }
            var updated = folder
            updated.personaId = defaultID
            updated.updatedAt = .now
            folderRecord.sealed = try sealFolder(updated, key: key)
            folderRecord.updatedAt = updated.updatedAt
            folderRecord.dirty = true
        }
        deleteAliases(forPersona: persona.id)
        record.deletedAt = .now
        record.updatedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
        noteLocalMutation()
    }
}
