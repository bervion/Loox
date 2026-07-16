import Foundation

/// Master switch for the Family per-grant sharing transport (Project A —
/// see `plans/260715-1848-family-devices-crypto/family-group-transport.md`).
///
/// Disabled = the OWNER writes the grant + display-envelope records under the
/// legacy zone-wide singleton names (`"grant"` / `"display-envelope"`), byte
/// for byte what shipped before this transport existed. Enabled = the owner
/// names them deterministically per grant (`grant:<grantId>` /
/// `display:<grantId>`), which is what lets more than one grant survive in
/// the same zone — required for "Share a Space" (`ShareSpaceSheet`, phase A3
/// stage 2), which fans N items' grants into ONE member zone.
///
/// The RECIPIENT read path always understands both per-grant and legacy
/// records — that half is unconditional, additive back-compat and needed no
/// flag. Enabled as of phase A3 stage 2: the ceremony UI + fan-out executor
/// (`SpaceShareMembershipExecutor`) that need multi-grant zones now exist and
/// are wired up, and `ApprovalShareService.publishGrant`'s flag-on path makes
/// a same-item republish REPLACE (not duplicate) a prior grant. Existing
/// single-item shares published under the legacy names keep working
/// unchanged — the recipient's read path and the legacy-name decode/cleanup
/// fallbacks were additive from the start (never gated on this flag).
nonisolated enum FamilyShareTransport {
    static let perGrantEnabled = true
}
