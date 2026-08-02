import Foundation

/// Field-level share eligibility for the surfaces that snapshot values out of
/// the vault (Quick Link, Quick View) and for per-item Approval opt-in.
///
/// This is an explicit ALLOWLIST, not a denylist: a field is shareable only
/// when a rule affirmatively admits it, so a new kind or a new secrecy flag is
/// excluded until someone decides otherwise (fail closed). It centralizes what
/// used to be per-surface exclusion lists; the capability resolver consults it
/// for the share surfaces so policy lives in one place.
nonisolated enum TransitionalSharePolicy {

    /// May this field appear in a one-shot snapshot share (Quick Link / Quick
    /// View)? Those surfaces have no recipient identity and no way to revoke a
    /// delivered copy, so the bar is the highest:
    /// - TOTP seeds: never (a snapshot is a permanent hand-over).
    /// - Attachments: never (bytes are not part of the snapshot contract).
    /// - Extra-protected (`guard2`) values: never (sealed under a separate key).
    /// - Key material — any protected multiline value (SSH private keys,
    ///   recovery codes) or any field whose semantics mark it secret-multiline:
    ///   never in v1, even though ordinary login passwords remain intentional.
    /// - Empty values: pointless, excluded.
    static func quickShareAllows(_ field: DynamicField) -> Bool {
        guard !field.isEmpty, !field.isExtraProtected else { return false }
        switch field.kind {
        case .totp, .fileRef: return false
        case .multiline: return !field.protected
        case .text, .username, .password, .url, .email,
             .number, .phone, .monospace, .date: return true
        }
    }

    /// May this field be OFFERED for per-item Approval sharing (owner opt-in,
    /// identified recipient)? Less absolute than a snapshot link — login
    /// sharing is an intentional product surface — but key material is still
    /// absent in v1: there is no developer-secret sharing policy yet, and a
    /// display-masking boolean is not consent.
    static func approvalShareAllows(_ field: DynamicField) -> Bool {
        guard !field.isExtraProtected else { return false }
        switch field.kind {
        case .fileRef: return false
        case .multiline: return !field.protected
        // TOTP has its own tri-state capability flow (off / ask each time /
        // hand over) — offering the row is allowed; the mode is decided there.
        case .totp: return true
        case .text, .username, .password, .url, .email,
             .number, .phone, .monospace, .date: return true
        }
    }
}
