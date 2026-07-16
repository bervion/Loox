import Foundation

/// A0-6 field-instance safelist for Family full-group ("Space") sharing: which
/// fields of ONE item a blanket Space share may hand over automatically, with
/// no per-field owner decision. Pure + total — no CloudKit, no vault store;
/// callers pass an already-decrypted `VaultItem`.
///
/// Eligible = category `.login` AND kind ∈ {`.username`, `.password`, `.url`,
/// `.email`} AND NOT `guard2`/extra-protected (Level-2 / `SecretGuard`).
/// Everything else — notes (`.multiline`), custom `.text`/`.monospace`, TOTP,
/// attachments (`.fileRef`), passkeys (not `DynamicField`s at all, see
/// `PasskeySlot`), and any EXTRA-protected field — stays private even though
/// the rest of the Space is shared. `VaultItem.fields` never contains
/// synthetic/virtual entries (those exist only as a separate type,
/// `QuickViewApprovedField`, for a different flow), so "not derived/virtual"
/// is satisfied by construction — nothing extra to check here.
///
/// The normal `protected` (masked-display) flag does NOT exclude a field:
/// `.password`/`.totp` default to `protected: true` at creation
/// (`FieldKind.defaultsProtected`), but masking is a DISPLAY concern, not a
/// sharing signal — a family login share MUST include the password (its whole
/// purpose; the shipped copy promises "usernames, passwords, email addresses,
/// and websites"). Only EXTRA-protection the user deliberately applied — the
/// `guard2` flag or a `SecretGuard` Level-2 value tag — keeps a field private.
/// TOTP and passkeys are excluded by KIND, never by the masked flag.
///
/// Copy states exactly what ships: "This shares usernames, passwords, email
/// addresses, and websites for every eligible login currently in this Space."
nonisolated enum SpaceShareSafelist {
    /// The only field kinds a blanket Space share may hand over. An allowlist
    /// (not a denylist) so a NEW `FieldKind` added later defaults to PRIVATE
    /// until explicitly added here — fail closed (INV-08).
    private static let eligibleKinds: Set<FieldKind> = [.username, .password, .url, .email]

    /// The safelisted capability map for one item, or `nil` when the item is
    /// ineligible entirely — not a login, or a login with zero eligible
    /// fields. `nil` names the reason distinctly from an eligible item that
    /// (transiently) safelists to an empty set, which cannot occur today
    /// (both collapse to "skip this item" for
    /// `SpaceShareMembershipReconciler.desired`).
    static func shareableFields(for item: VaultItem) -> [String: FieldCapability]? {
        guard item.category == .login else { return nil }
        var fields: [String: FieldCapability] = [:]
        for field in item.fields where isEligible(field) {
            fields[field.id] = .value(.shared)
        }
        return fields.isEmpty ? nil : fields
    }

    /// The `SecretGuard` tag check on the raw value is defense in depth against
    /// a `guard2` flag desynced from the stored value (mirrors
    /// `WebExtensionReader.releasable`) — never relied on alone; the `guard2`
    /// flag is the primary extra-protection gate. The masked `protected` flag
    /// is deliberately NOT checked here (see the type doc): a masked password
    /// is still shared — masking is display, not a sharing decision.
    private static func isEligible(_ field: DynamicField) -> Bool {
        eligibleKinds.contains(field.kind)
            && !field.isExtraProtected
            && !SecretGuard.isProtected(field.value)
    }
}
