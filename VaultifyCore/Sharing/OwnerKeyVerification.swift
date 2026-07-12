import Foundation

/// The recipient's one-time human trust decision for a share's pinned owner
/// key. The Keychain pin freezes whichever owner signing key is FIRST seen
/// in a zone (a later key change is rejected, never re-pinned) — but the pin
/// alone is silent trust: whoever controls the zone at first sight gets
/// believed. This state records whether a person actually compared the
/// safety code with the owner (or explicitly chose not to) before the
/// share's content was used.
///
/// Trust model: the pin is the crypto anchor, this is the human decision.
/// Pinning stays where it is (first sight, projection refresh) so a swapped
/// key between fetches is still caught; the verification state only governs
/// USE of the content.
nonisolated enum OwnerKeyVerification: String, Codable, Sendable {
    /// Pinned but not yet decided: values, requests, and AutoFill stay
    /// withheld, and every first-use surface re-prompts. Absence of a
    /// stored marker on a new pin reads as `pending` — fail closed, never
    /// default-trust.
    case pending
    /// The user compared the safety code with the owner and it matched.
    case confirmed
    /// The user explicitly chose to use the share without comparing. An
    /// informed, recorded skip — strictly better than a silent default.
    case skipped

    /// `confirmed` and `skipped` are terminal: they never re-prompt.
    /// Re-verification on a key change is impossible by construction — the
    /// pin rejects changed keys instead of re-pinning them.
    var isDecided: Bool { self != .pending }

    /// Content may be used (values revealed, requests sent, AutoFill fed)
    /// only after an explicit decision.
    var allowsUse: Bool { isDecided }

    /// Migration rule for shares pinned before the verification gate
    /// existed: they have been in active use under the silent model, so
    /// they are marked `confirmed` once instead of retro-prompting (the
    /// safety-code row remains as a manual re-check surface). Returns the
    /// state to store, or the unchanged existing state; a zone without a
    /// pin gets no marker — the normal `pending` path applies when its pin
    /// lands.
    static func backfillState(hasPin: Bool,
                              existing: OwnerKeyVerification?) -> OwnerKeyVerification? {
        guard existing == nil else { return existing }
        return hasPin ? .confirmed : nil
    }
}
