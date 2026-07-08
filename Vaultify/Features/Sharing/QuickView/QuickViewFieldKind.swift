import Foundation

/// Semantic kind of one approved Quick View field. Mirrors the shape of
/// `LooxLinkEnvelope.Field.kind` (viewer icon/formatting hint) but is its own
/// closed enum — Quick View composes `LooxLinkEnvelope`'s persisted fields
/// with a Quick-View-only virtual field (`currentTOTP`, DEC-QV-FIELD-01),
/// which the narrower `LooxLinkEnvelope` type must never learn about.
nonisolated enum QuickViewFieldKind: String, Codable, Sendable, CaseIterable {
    case username
    case password
    case email
    case website
    case note
    case custom
    /// Virtual field materialized outside the persisted envelope: a
    /// boundary-aware CURRENT TOTP code (never the seed, INV-QV-17), always
    /// appended last in the final ordered field array (V1).
    case currentTOTP
}
