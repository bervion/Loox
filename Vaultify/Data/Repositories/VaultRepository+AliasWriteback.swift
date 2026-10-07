import Foundation

/// Writes an activated alias's address back onto the item the user sees: a
/// persona-tier alias goes onto the persona's profile card (so they know their
/// private address), a per-site alias onto its bound login (so it autofills on
/// that site). The real Email field is never touched — the alias is appended as
/// a separate "Private email" field, so the profile's first `.email` (the real
/// one) stays the value suggestions/AutoFill use.
extension VaultRepository {

    func attachAliasToProfile(_ alias: EmailAlias, persona: Persona) {
        guard let card = profileItem(for: persona), let address = alias.resolvedAddress else { return }
        try? update(AliasWriteback.upsertPrivateEmail(on: card, address: address))
    }

    /// Automatic activation writeback is valid only for the original primary
    /// relation. A late network reply must not restore an explicitly unlinked field.
    func attachAliasToLogin(_ alias: EmailAlias, expectedRelationRevision: UInt64) throws {
        guard let live = aliases.first(where: { $0.id == alias.id }),
              live.relationRevision == expectedRelationRevision,
              live.boundItemId == alias.boundItemId, let itemID = live.boundItemId else { return }
        try linkAliasToLogin(aliasID: live.id, itemID: itemID,
                             expectedAliasRevision: expectedRelationRevision)
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
// `AliasWriteback` itself lives in VaultifyCore (shared with the AutoFill
// extension, which reads the written-back field to offer the alias).
