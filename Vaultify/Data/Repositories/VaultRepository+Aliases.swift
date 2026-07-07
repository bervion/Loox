import Foundation
import SwiftData

/// Email-alias sealing, decode, load, and persona-scoped resolvers — the alias
/// analogue of `+Personas`. Identity-bearing content is sealed under the Vault
/// Key. Resolvers always filter by a single `personaId`, so a caller can never
/// surface another persona's aliases (INV-R03).
extension VaultRepository {

    func sealAlias(_ alias: EmailAlias, key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(alias.secret), key: key)
    }

    private func decryptAlias(_ record: EmailAliasRecord, key: SecureBytes) throws -> EmailAlias {
        let plaintext = try AESGCM.open(record.sealed, key: key)
        let secret = try JSONDecoder().decode(EmailAliasSecret.self, from: plaintext)
        return EmailAlias(id: record.id,
                          personaId: secret.personaId,
                          tier: secret.tier,
                          localPart: secret.localPart,
                          boundItemId: secret.boundItemId,
                          boundDomain: secret.boundDomain,
                          label: secret.label,
                          status: secret.status,
                          forwardingInboxID: secret.forwardingInboxID,
                          forwardingTarget: secret.forwardingTarget,
                          disabledAt: secret.disabledAt,
                          backendMinted: secret.backendMinted,
                          relayDomainID: secret.relayDomainID,
                          sortIndex: record.sortIndex,
                          createdAt: record.createdAt,
                          updatedAt: record.updatedAt)
    }

    /// Decrypt all live aliases, sorted by sort order then creation.
    func loadAliases(key: SecureBytes) -> [EmailAlias] {
        let descriptor = FetchDescriptor<EmailAliasRecord>(predicate: #Predicate { $0.deletedAt == nil })
        guard let records = try? store.context.fetch(descriptor) else { return [] }
        return records
            .compactMap { try? decryptAlias($0, key: key) }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    // MARK: Resolvers (always persona-scoped)

    func aliases(forPersona personaId: String) -> [EmailAlias] {
        aliases.filter { $0.personaId == personaId }
    }

    /// All reusable (persona-tier) addresses of a persona — 0..N, user-labelled.
    func reusableAliases(forPersona personaId: String) -> [EmailAlias] {
        aliases.filter { $0.personaId == personaId && $0.tier == .persona }
    }

    /// First reusable address of a persona (legacy single-alias call sites).
    func personaAlias(forPersona personaId: String) -> EmailAlias? {
        reusableAliases(forPersona: personaId).first
    }

    func aliases(forItem itemId: String) -> [EmailAlias] {
        aliases.filter { $0.boundItemId == itemId }
    }

    /// Reuse suggestions for a login context, scoped to the ACTIVE persona
    /// (INV-PE01: another persona's addresses are excluded, not down-ranked).
    func aliasSuggestions(forItem itemId: String?, host: String?) -> [EmailAlias] {
        guard let active = activePersona else { return [] }
        return AliasSuggestion.ranked(aliases: aliases(forPersona: active.id),
                                      itemID: itemId, host: host,
                                      flag: RelayFeature.activeAliasesEnabled)
    }
}
