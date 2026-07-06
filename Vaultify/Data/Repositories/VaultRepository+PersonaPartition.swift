import Foundation

/// Persona↔Space partition: a Space belongs to exactly one persona (its sealed
/// `Folder.personaId`), and an item belongs to its Space's persona (Unfiled →
/// default). These read-only filters are the single fail-closed source every
/// surface scopes through, so no view can accidentally leak another persona's
/// data (INV-R03). The in-place backfill/reconcile that populates `personaId`
/// lives in `VaultRepository.migratePartition` (it mutates the caches).
extension VaultRepository {

    /// Spaces owned by a persona. A folder whose `personaId` is still nil (not yet
    /// backfilled / synced from an old device) counts as the default's.
    func spaces(for persona: Persona) -> [Folder] {
        folders.filter { ($0.personaId ?? defaultPersona?.id) == persona.id }
    }

    /// Items owned by a persona: those filed under the persona's Spaces, plus
    /// Unfiled items only when the persona is the default (Unfiled has no Space,
    /// so it can't belong to an isolated persona).
    func items(for persona: Persona) -> [VaultItem] {
        let ownedFolderIds = Set(spaces(for: persona).map(\.id))
        return items.filter { item in
            if let folderId = item.folderId { return ownedFolderIds.contains(folderId) }
            return persona.isDefault
        }
    }

    /// The active persona's Spaces (all Spaces when no persona exists yet — the
    /// pre-persona legacy path, so a vault without personas behaves as before).
    var activePersonaSpaces: [Folder] {
        activePersona.map { spaces(for: $0) } ?? folders
    }

    /// The active persona's items (all items when no persona exists yet). Every
    /// item-listing surface draws from this so partition is enforced at the source.
    var activePersonaItems: [VaultItem] {
        activePersona.map { items(for: $0) } ?? items
    }
}
