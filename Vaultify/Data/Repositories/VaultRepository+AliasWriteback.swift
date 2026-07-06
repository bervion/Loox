import Foundation

/// Writes an activated alias's address back onto the item the user sees: a
/// persona-tier alias goes onto the persona's profile card (so they know their
/// private address), a per-site alias onto its bound login (so it autofills on
/// that site). The real Email field is never touched — the alias is appended as
/// a separate "Private email" field, so the profile's first `.email` (the real
/// one) stays the value suggestions/AutoFill use.
extension VaultRepository {

    func attachAliasToProfile(_ alias: EmailAlias, persona: Persona) {
        guard let card = profileItem(for: persona) else { return }
        try? update(AliasWriteback.upsertPrivateEmail(on: card, address: aliasAddress(alias)))
    }

    func attachAliasToLogin(_ alias: EmailAlias) {
        guard let itemId = alias.boundItemId, let login = item(id: itemId) else { return }
        try? update(AliasWriteback.upsertPrivateEmail(on: login, address: aliasAddress(alias)))
    }

    private func aliasAddress(_ alias: EmailAlias) -> String {
        AliasAddress.display(localPart: alias.localPart, status: alias.status,
                             relayDomain: RelayConfig.emailDomain)
    }

    /// Set the persona's REAL email (its aliases' forwarding destination) on the
    /// profile card's Email field — kept as the FIRST `.email` so it stays the
    /// value suggestions/AutoFill use. Callers then re-rotate active aliases.
    func setDestinationEmail(_ email: String, for persona: Persona) {
        guard let card = profileItem(for: persona) else { return }
        var updated = card
        if let index = updated.fields.firstIndex(where: {
            $0.kind == .email && $0.label != AliasWriteback.privateEmailLabel
        }) {
            updated.fields[index].value = email
        } else {
            updated.fields.insert(DynamicField(label: "Email", kind: .email, value: email), at: 0)
        }
        try? update(updated)
    }
}

/// Pure write-back helpers (label constant + idempotent field upsert).
nonisolated enum AliasWriteback {
    /// Raw field label — localized at display via `fieldLabelText`; the catalog
    /// carries the VI value. Used as the stable key for idempotent upsert.
    static let privateEmailLabel = "Private email"

    /// Append the alias as a "Private email" field, or update it in place if one
    /// already exists — never duplicates, never disturbs the real Email field.
    static func upsertPrivateEmail(on item: VaultItem, address: String) -> VaultItem {
        var updated = item
        if let index = updated.fields.firstIndex(where: {
            $0.label == privateEmailLabel && $0.kind == .email
        }) {
            updated.fields[index].value = address
        } else {
            updated.fields.append(DynamicField(label: privateEmailLabel, kind: .email, value: address))
        }
        return updated
    }
}
