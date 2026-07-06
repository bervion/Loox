import Foundation
import SwiftData

/// Persona ("identity") sealing, decode, resolvers, and minimal CRUD — the
/// persona analogue of `+Folders`/`+Identity`. Identity-bearing fields are sealed
/// under the Vault Key, mirroring the folder seal/open path. The reload-time
/// invariants (`ensurePersonaExists`/`normalizeDefaultPersona`) live in the core
/// file next to `normalizeDefaultIdentity` because they patch the `personas` cache
/// in place.
extension VaultRepository {

    // MARK: Persona sealing (mirrors the folder seal/open path)

    /// Internal (not private) so the reload-time seed in the core file can seal a
    /// freshly built persona.
    func sealPersona(_ persona: Persona, key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(persona.secret), key: key)
    }

    private func decryptPersona(_ record: PersonaRecord, key: SecureBytes) throws -> Persona {
        let plaintext = try AESGCM.open(record.sealed, key: key)
        let secret = try JSONDecoder().decode(PersonaSecret.self, from: plaintext)
        return Persona(id: record.id,
                       displayName: secret.displayName,
                       kind: secret.kind,
                       isolationPolicy: secret.isolationPolicy,
                       primaryProfileItemID: secret.primaryProfileItemID,
                       primarySpaceID: secret.primarySpaceID,
                       isDefault: record.isDefault,
                       sortIndex: record.sortIndex,
                       createdAt: record.createdAt,
                       updatedAt: record.updatedAt)
    }

    /// Decrypt all live personas, sorted by sort order then creation. Called from
    /// `reload()` while the Vault Key is in scope.
    func loadPersonas(key: SecureBytes) -> [Persona] {
        let descriptor = FetchDescriptor<PersonaRecord>(predicate: #Predicate { $0.deletedAt == nil })
        guard let records = try? store.context.fetch(descriptor) else { return [] }
        return records
            .compactMap { try? decryptPersona($0, key: key) }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    // MARK: Resolvers

    /// The synced, converged default persona (guaranteed to exist post-reload).
    var defaultPersona: Persona? { personas.first(where: \.isDefault) }

    /// The persona the UI is currently acting as: the device-local selection, or
    /// the default when that selection is unset or stale.
    var activePersona: Persona? {
        personas.first { $0.id == session.settings.activePersonaID } ?? defaultPersona
    }

    // MARK: CRUD

    /// Create a new (non-default) persona. Its primary Space defaults to the
    /// current primary so new items filed under it still have a home.
    @discardableResult
    func addPersona(displayName: String, kind: PersonaKind) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let persona = Persona(displayName: displayName,
                              kind: kind,
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

    /// Make `persona` the single default; demotes the previous one. Each flag write
    /// bumps `updatedAt` (content gate) so the change survives whole-record LWW.
    func setDefaultPersona(_ persona: Persona) {
        let now = Date()
        var didWrite = false
        for candidate in personas {
            let shouldBeDefault = candidate.id == persona.id
            guard candidate.isDefault != shouldBeDefault else { continue }
            writePersonaDefault(id: candidate.id, isDefault: shouldBeDefault, now: now)
            didWrite = true
        }
        guard didWrite else { return }
        try? store.context.save()
        reload()
        noteLocalMutation()
    }

    /// Switch which persona the UI acts as. Device-local only (no record write, no
    /// sync) — the active view is a per-device concern.
    func setActivePersona(_ id: String) {
        session.settings.activePersonaID = id
    }

    /// Link a Space to a persona by re-sealing the folder through `updateFolder`
    /// (which bumps `updatedAt`, keeping the change LWW-safe). Not called in P1's
    /// flows yet; the persona's `primarySpaceID` is the authoritative link today.
    func assignSpace(_ folder: Folder, toPersona personaId: String?) {
        var updated = folder
        updated.personaId = personaId
        try? updateFolder(updated)
    }
}
