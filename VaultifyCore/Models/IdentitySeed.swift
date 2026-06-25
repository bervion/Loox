import Foundation

/// Builds the mandatory default identity from the display name collected at onboarding.
/// Pure + `nonisolated` so it is unit-testable without UI and runs off-main.
///
/// Title = the trimmed display name (or `fallback` when blank); the template's "Full Name"
/// field mirrors it; the item is pre-marked as the default identity so the first-run seed
/// satisfies the single-active-default invariant immediately.
nonisolated enum IdentitySeed {
    static func make(displayName: String, fallback: String) -> VaultItem {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? fallback : trimmed
        var fields = ItemCategory.identity.fieldTemplate
        if let idx = fields.firstIndex(where: { $0.label == "Full Name" }) {
            fields[idx].value = name
        }
        return VaultItem(category: .identity, title: name, fields: fields, isDefaultIdentity: true)
    }
}
