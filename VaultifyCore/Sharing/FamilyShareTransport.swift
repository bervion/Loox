import Foundation

/// Master switch for the Family per-grant sharing transport (Project A,
/// phase A1 — see `plans/260715-1848-family-devices-crypto/family-group-transport.md`).
///
/// Disabled = the OWNER writes the grant + display-envelope records under the
/// legacy zone-wide singleton names (`"grant"` / `"display-envelope"`), byte
/// for byte what shipped before this transport existed — `main` behavior is
/// unchanged. Enabled = the owner names them deterministically per grant
/// (`grant:<grantId>` / `display:<grantId>`), which is what lets more than
/// one grant survive in the same zone (today, publishing a second item's
/// grant into a zone silently deletes the first).
///
/// The RECIPIENT read path always understands both per-grant and legacy
/// records — that half is unconditional, additive back-compat and needs no
/// flag. This flag only gates the owner's WRITE naming, so per-grant
/// transport can be exercised end to end (multi-grant zones, two iCloud
/// accounts) before the rest of Project A (`SharingStore` identity rework +
/// the membership reconciler, phase A2) lands. Flip to `true` only for that
/// in-progress work.
nonisolated enum FamilyShareTransport {
    static let perGrantEnabled = false
}
