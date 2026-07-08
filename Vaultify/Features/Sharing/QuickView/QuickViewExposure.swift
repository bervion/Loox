import Foundation

/// Three-state operator-declared exposure for Quick View (DEC-QV-EXPOSURE-01,
/// carried by the signed capability manifest as `quick_view.exposure`,
/// schema 2+) — deliberately NOT a binary GA gate: `beta` lets a gated cohort
/// exercise real-device App Attest learning (invalidKey, re-registration,
/// challenge retry) while assertion enforcement is still in shadow, before
/// `ga` ever goes live. Raw values are the BE wire strings.
nonisolated enum QuickViewExposure: String, Codable, Sendable {
    case hidden
    case beta
    case ga
}

/// Pure entry-visibility resolver — INV-QV-24: general availability MUST stay
/// hidden while backend assertion enforcement is below REQUIRED, UNLESS the
/// caller is already in the gated beta cohort (owner-confirmed: the beta
/// cohort keeps seeing Quick View under `ga` too — a manifest promoting
/// `beta` → `ga` is a no-op for cohort members already exercising it; a
/// general (non-beta) user still fails closed in shadow). This is only the
/// APP-SIDE half of a multi-layer gate; the backend cohort allowlist is the
/// other, load-bearing half (an app-only UI flag is insufficient — a custom
/// client bypasses UI).
///
/// Matrix (DEC-QV-EXPOSURE-01):
///   hidden / any / any                    → false
///   beta   / shadow or required / beta cohort → true
///   beta   / any / non-beta cohort         → false
///   ga     / required / any               → true
///   ga     / shadow / beta cohort          → true  (already exercising it)
///   ga     / shadow / non-beta cohort      → false (fail closed, INV-QV-24)
nonisolated enum QuickViewExposureResolver {
    static func entryVisible(exposure: QuickViewExposure,
                             assertionRequired: Bool,
                             isBetaCohort: Bool) -> Bool {
        switch exposure {
        case .hidden:
            return false
        case .beta:
            return isBetaCohort
        case .ga:
            return isBetaCohort ? true : assertionRequired
        }
    }
}
