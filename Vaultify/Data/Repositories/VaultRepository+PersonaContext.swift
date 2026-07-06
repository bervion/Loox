import Foundation

/// Persona-aware read helpers that enforce isolation (INV-R03) for the in-app
/// search + create-login surfaces. All reads are over already-decrypted caches;
/// no persistence. The isolation rule itself lives in `PersonaUsernameSuggester`
/// (shared with the extension); this file wires the repository into it.
extension VaultRepository {

    /// The active persona's isolation policy (default `.standard` before a persona exists).
    var activeIsolationPolicy: PersonaIsolationPolicy {
        activePersona?.isolationPolicy ?? .standard
    }

    /// Best display username for an item: email, then a username field, then a name/text field.
    func username(from item: VaultItem) -> String? {
        if let email = item.fields.first(where: { $0.kind == .email })?.value, !email.isEmpty { return email }
        if let user = item.fields.first(where: { $0.kind == .username })?.value, !user.isEmpty { return user }
        if let text = item.fields.first(where: { $0.kind == .text })?.value, !text.isEmpty { return text }
        return nil
    }

    /// The persona's own profile card (identity item), resolved via its
    /// `primaryProfileItemID`. Only a live identity item counts — a trashed or
    /// re-categorized target reads as "no profile" (nil), never a stale card.
    /// No cross-persona fallback (fail-closed): the default persona's link is
    /// seeded at bootstrap, so it still resolves to the classic default identity.
    func profileItem(for persona: Persona) -> VaultItem? {
        guard let id = persona.primaryProfileItemID,
              let item = items.first(where: { $0.id == id }),
              item.category == .identity else { return nil }
        return item
    }

    /// The ACTIVE persona's profile card — what Profile and the Home header show.
    var activeProfileItem: VaultItem? {
        activePersona.flatMap { profileItem(for: $0) }
    }

    /// The username to represent a persona: its own profile item; the global
    /// default identity is used as a fallback ONLY when the persona is not
    /// strictly anonymous (INV-R03 — an anonymous persona never borrows another
    /// identity's email).
    func identityUsername(forPersona persona: Persona) -> String? {
        if let itemID = persona.primaryProfileItemID, let item = item(id: itemID),
           let value = username(from: item) {
            return value
        }
        guard persona.isolationPolicy != .strictAnonymous, let fallback = defaultIdentity else { return nil }
        return username(from: fallback)
    }

    /// The default search scope, fail-closed for isolation. A strictAnonymous
    /// persona is scoped to its own Space and can NEVER default to All Spaces; if
    /// it has no primary Space the produced scope matches no folder → empty
    /// results, never the global set (INV-R03).
    func defaultSearchScope(currentSpaceId: String?) -> SpaceScope {
        if activeIsolationPolicy == .strictAnonymous {
            return .thisSpace(id: activePersona?.primarySpaceID ?? "")
        }
        return currentSpaceId.map { .thisSpace(id: $0) } ?? .allSpaces
    }

    /// Whether the "Shared with Me" scope may be offered — never under
    /// strictAnonymous (shared items are inherently cross-persona).
    func showsSharedScope(base: Bool) -> Bool {
        base && activeIsolationPolicy != .strictAnonymous
    }

    /// Up to 3 username suggestions for a new login under the active persona,
    /// filtered/ranked by isolation policy (strictAnonymous excludes every value
    /// not owned by the active persona, including the global default).
    func usernameSuggestions() -> [String] {
        guard let active = activePersona else { return [] }
        var candidates: [UsernameCandidate] = []

        if let itemID = active.primaryProfileItemID, let item = item(id: itemID),
           let value = username(from: item) {
            candidates.append(.init(value: value, sourcePersonaID: active.id,
                                    source: .activePersonaProfile, lastUsedAt: item.lastUsedAt))
        }
        if let fallback = defaultIdentity, let value = username(from: fallback) {
            candidates.append(.init(value: value, sourcePersonaID: nil,
                                    source: .defaultIdentity, lastUsedAt: fallback.lastUsedAt))
        }
        for item in recentlyUsed(limit: 8) where item.category == .login {
            if let value = username(from: item) {
                candidates.append(.init(value: value, sourcePersonaID: personaID(forItem: item),
                                        source: .recent, lastUsedAt: item.lastUsedAt))
            }
        }

        return Array(PersonaUsernameSuggester.suggestions(
            candidates: candidates, activePersonaID: active.id, policy: active.isolationPolicy).prefix(3))
    }

    /// The persona that owns an item — derived from its Space's `personaId`. An
    /// item with no Space (Unfiled) belongs to the default persona (fail-closed:
    /// a non-default, incl. strictAnonymous, persona never owns Unfiled items).
    func personaID(forItem item: VaultItem) -> String? {
        if let folderId = item.folderId,
           let owner = folders.first(where: { $0.id == folderId })?.personaId {
            return owner
        }
        return defaultPersona?.id
    }
}
