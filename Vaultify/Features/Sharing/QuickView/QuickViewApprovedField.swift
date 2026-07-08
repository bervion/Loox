import Foundation

/// One field the owner approved for this Quick View session — a typed model
/// (DEC-QV-FIELD-01), deliberately NOT a generic `[String: String]` dictionary
/// so the compiler enforces the closed `QuickViewFieldKind` vocabulary end to
/// end (composer → manifest hasher → sealer plaintext).
nonisolated struct QuickViewApprovedField: Codable, Sendable, Equatable {
    /// Stable identity across the ordered array — for persisted fields this
    /// is the underlying `DynamicField.id`; for virtual fields (currentTOTP)
    /// it is a fixed protocol constant. Used ONLY by the structural manifest
    /// hash, never by the sealer plaintext's meaning.
    var stableID: String
    var kind: QuickViewFieldKind
    /// Owner's localized label, exactly as shown in-app (e.g. "Password" /
    /// "Mật khẩu") — display only, never hashed into the structural manifest.
    var label: String
    var value: String
    /// Display hint: the browser masks the value behind a Reveal control.
    /// NOT a security boundary — the value is already decrypted client-side
    /// by the time this flag is read.
    var concealed: Bool
    /// Exact TOTP window-end (Unix ms) — set ONLY on a `.currentTOTP` field,
    /// `nil` for every other kind. Authenticated payload metadata: it rides
    /// inside the sealed plaintext (AES-GCM tag covers it), never a
    /// plaintext-mutable transport field, so the browser can't be tricked
    /// into treating a stale code as still valid. Never fed into the
    /// STRUCTURAL manifest hash (`QuickViewFieldManifest`) — that hash covers
    /// field identity/order, not this kind of time-varying metadata.
    var validUntilUnixMs: Int64? = nil
}
