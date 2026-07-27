import Foundation

/// The recipient's trust decision about the person behind a share's pinned
/// owner key.
///
/// Two mechanisms guard a received share, and they do different jobs:
///
/// - **The pin** is the crypto anchor. It freezes whichever owner signing key
///   is FIRST seen in a zone and REJECTS a later key change (never re-pins),
///   so a substituted key is caught without any human involvement. It is
///   stronger than a human code comparison and costs nothing.
/// - **This state** is the human fact: a person agreed to receive content from
///   this sender. It gates USE of the content (chiefly the AutoFill/QuickType
///   mirror), because the pin alone cannot tell a share you wanted from a
///   share a stranger who knows your iCloud address pushed at you.
///
/// The human fact is established at ACCEPT time, where the sender's
/// CloudKit-authenticated identity is on screen — that is the one moment the
/// recipient actually chooses. Comparing the safety code out of band remains
/// available afterwards for anyone who wants the anti-substitution property
/// verified by hand, but it never blocks first use.
///
/// Decisions only ever move UP the ranking (see `supersedes`): an automatic
/// marker can never quietly undo a comparison a person actually performed.
nonisolated enum OwnerKeyVerification: String, Codable, Sendable {
    /// No decision recorded. Content stays out of AutoFill. Absence of a
    /// stored marker reads as `pending` — fail closed, never default-trust.
    /// Reachable for shares accepted before the identity-at-accept flow, and
    /// whenever a marker write failed.
    case pending
    /// The recipient accepted this share knowing who sent it. The zone only
    /// exists in the shared database because this account accepted its
    /// CKShare, and acceptance names the sender.
    case accepted
    /// The recipient compared the safety code with the owner out of band and
    /// it matched. The strongest state: it also excludes a substituted key.
    case confirmed
    /// Legacy: the recipient was asked to compare the code before first use
    /// and explicitly declined. Still written when someone opens the optional
    /// comparison on an undecided share and chooses to use it as is.
    case skipped

    /// `pending` is the only undecided state; everything else is terminal for
    /// gating purposes. Re-verification on a key change is impossible by
    /// construction — the pin rejects changed keys instead of re-pinning them.
    var isDecided: Bool { self != .pending }

    /// Content may be used (values revealed, requests sent, AutoFill fed)
    /// only once a person has agreed to the sender.
    var allowsUse: Bool { isDecided }

    /// How much the human actually established. Used to keep stored state
    /// monotonic — `accepted` and `skipped` both mean "agreed, did not
    /// compare", so neither replaces the other.
    private var rank: Int {
        switch self {
        case .pending: 0
        case .accepted, .skipped: 1
        case .confirmed: 2
        }
    }

    /// True when this decision says strictly more than what is already stored
    /// (a missing marker counts as `pending`).
    func supersedes(_ stored: OwnerKeyVerification?) -> Bool {
        rank > (stored?.rank ?? 0)
    }

    /// Migration rule for shares pinned before any decision was recorded:
    /// they have been in active use under the silent trust model, so they are
    /// marked once instead of retro-prompting. `accepted` rather than
    /// `confirmed` — nobody compared a code, they just took delivery. Returns
    /// the state to store, or the unchanged existing state; a zone without a
    /// pin gets no marker — the normal path applies when its pin lands.
    static func backfillState(hasPin: Bool,
                              existing: OwnerKeyVerification?) -> OwnerKeyVerification? {
        guard existing == nil else { return existing }
        return hasPin ? .accepted : nil
    }
}
