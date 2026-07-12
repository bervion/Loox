import Foundation
import SwiftData

/// Read-only Space ("Folder") listing for the AutoFill extension's create/save
/// flows. Mirrors `VaultRepository.spaces(for:)` / `activePersonaSpaces`
/// (`VaultRepository+PersonaPartition.swift`) read-only, without pulling in the
/// app's full repository — the extension only needs enough to (a) show a
/// persona-scoped Space picker and (b) pick a sane default for a brand-new item.
/// Persona context (active persona id / default flag / primary Space / last
/// selected Space) is mirrored into the App Group by
/// `VaultRepository.mirrorActivePersonaContext()` — see `SharedConfig`.
enum VaultSpaceReader {
    /// A Space as shown in the extension's picker: just enough to render + select.
    struct Space: Identifiable, Equatable {
        let id: String
        let name: String
    }

    /// Decrypt a folder record's sealed name + persona link. `nil` on any
    /// decrypt/decode failure (corrupt or foreign-keyed blob) — the folder is
    /// simply omitted from the picker rather than crashing the save flow.
    private static func decrypt(_ record: FolderRecord, key: SecureBytes) -> (name: String, personaId: String?)? {
        guard let plaintext = try? AESGCM.open(record.sealed, key: key),
              let secret = try? JSONDecoder().decode(FolderSecret.self, from: plaintext)
        else { return nil }
        return (secret.name, secret.personaId)
    }

    /// Live (non-deleted) Spaces owned by the mirrored active persona, decrypted
    /// and sorted like the app's Spaces grid. Persona isolation (INV-R03): a Space
    /// with no `personaId` link belongs to the DEFAULT persona only — replicating
    /// `VaultRepository.spaces(for:)` exactly using the mirrored `isDefault` flag.
    /// Returns `[]` when no persona context has been mirrored yet (pre-persona
    /// vaults, or the app hasn't opened since this mirroring shipped) — the
    /// extension's save flow then falls back to Unfiled only, never guesses.
    @MainActor static func activePersonaSpaces(store: VaultStore, vaultKey: SecureBytes) -> [Space] {
        let defaults = SharedConfig.sharedDefaults
        guard let activeId = defaults.string(forKey: SharedConfig.activePersonaIdKey) else { return [] }
        let isDefault = defaults.bool(forKey: SharedConfig.activePersonaIsDefaultKey)

        let records = store.allFolderRecords()
            .filter { $0.deletedAt == nil }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }

        return records.compactMap { record -> Space? in
            guard let decoded = decrypt(record, key: vaultKey) else { return nil }
            let owner = decoded.personaId ?? (isDefault ? activeId : nil)
            guard owner == activeId else { return nil }
            return Space(id: record.id, name: decoded.name)
        }
    }

    /// The Space a NEW item saved in the extension defaults into. Fallback chain
    /// (mirrors `ItemEditorScreen`'s `preselectedFolderId ?? env.repository.primarySpaceId`):
    /// 1. The Home Space last selected in-app for this persona, IF it still exists
    ///    and is still owned by this persona (a deleted/reassigned/foreign id falls through).
    /// 2. The persona's mirrored primary Space, same validation.
    /// 3. `nil` (Unfiled) — never guesses a foreign persona's Space.
    @MainActor static func defaultSpaceId(store: VaultStore, vaultKey: SecureBytes) -> String? {
        let owned = Set(activePersonaSpaces(store: store, vaultKey: vaultKey).map(\.id))
        guard !owned.isEmpty else { return nil }
        let defaults = SharedConfig.sharedDefaults
        if let last = defaults.string(forKey: SharedConfig.activePersonaLastSpaceKey), owned.contains(last) {
            return last
        }
        if let primary = defaults.string(forKey: SharedConfig.activePersonaPrimarySpaceKey), owned.contains(primary) {
            return primary
        }
        return nil
    }
}
