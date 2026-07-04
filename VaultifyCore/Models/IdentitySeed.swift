import Foundation

/// Builds the mandatory default identity from the display name collected at onboarding.
/// Pure + `nonisolated` so it is unit-testable without UI and runs off-main.
///
/// Title = the trimmed display name (or `fallback` when blank); the template's "Full Name"
/// field mirrors it; the item is pre-marked as the default identity so the first-run seed
/// satisfies the single-active-default invariant immediately.
nonisolated enum IdentitySeed {
    /// `email` pre-fills the template's Email field; a non-empty `note` is appended as a
    /// multiline field (a first-run welcome); `tag` groups the starter items. Localized
    /// strings (`fallback`, `note`, `tag`) are resolved by the caller and passed in.
    static func make(displayName: String, email: String, fallback: String,
                     note: String, tag: String) -> VaultItem {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? fallback : trimmed
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        var fields = ItemCategory.identity.fieldTemplate
        if let idx = fields.firstIndex(where: { $0.label == "Full Name" }) {
            fields[idx].value = name
        }
        if !trimmedEmail.isEmpty, let idx = fields.firstIndex(where: { $0.label == "Email" }) {
            fields[idx].value = trimmedEmail
        }
        if !note.isEmpty {
            fields.append(DynamicField(label: "Note", kind: .multiline, value: note))
        }
        return VaultItem(category: .identity, title: name, fields: fields,
                         tags: tag.isEmpty ? [] : [tag], isDefaultIdentity: true)
    }
}
