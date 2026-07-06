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
                          status: secret.status,
                          forwardingTarget: secret.forwardingTarget,
                          disabledAt: secret.disabledAt,
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

    /// The single persona-tier alias for a persona, if one exists (≤1 per persona).
    func personaAlias(forPersona personaId: String) -> EmailAlias? {
        aliases.first { $0.personaId == personaId && $0.tier == .persona }
    }

    func aliases(forItem itemId: String) -> [EmailAlias] {
        aliases.filter { $0.boundItemId == itemId }
    }
}
