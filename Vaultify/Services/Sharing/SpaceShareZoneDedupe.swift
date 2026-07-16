import Foundation

/// Pure zone-reuse rule for the "Share a Space" ceremony (Family full-group
/// sharing, phase A3 stage 2): which of a recipient's EXISTING zones (if any)
/// `ShareSpaceSheet` should hand to
/// `ApprovalShareService.createShare(recipientEmail:existingZoneName:)`
/// instead of minting a fresh one.
///
/// The single-item ceremony (`ShareAccessSheet`) only ever dedupes within
/// `SharingStore.shares(forItem:)` — scoped to the ONE item being shared — so
/// two different items shared to the same recipient mint two different zones
/// today. A Space share deliberately reuses ONE zone per recipient instead
/// (the whole point of the per-grant transport, A1-A3): this is where that
/// "which zone" decision is made.
///
/// Scoped to the ACTIVE persona's items (INV-R03): a zone is reusable only if
/// it already carries at least one item-share for an item the active persona
/// owns. A recipient's zone that holds only a DIFFERENT persona's earlier
/// share must never receive this persona's Space fan-out — that would mix two
/// personas' items into the same CloudKit zone. Safe by construction: no zone
/// can hold items from more than one persona today (every existing
/// zone-minting path is either per-item single-persona at mint time, or this
/// same persona-scoped reuse rule), so "at least one matching item" is
/// equivalent to "every item in that zone belongs to the active persona."
nonisolated enum SpaceShareZoneDedupe {
    /// `recipientShares` — every `ItemShareRecord` for this recipient, across
    /// all their zones (`SharingStore.shares(forRecipient:)`).
    /// `activePersonaItemIds` — ids of every item the active persona owns
    /// (`VaultRepository.activePersonaItems`).
    /// Returns the first matching zone name in `recipientShares`'s order, or
    /// `nil` when this recipient has no zone yet under the active persona
    /// (a fresh zone should be minted).
    static func existingZoneName(recipientShares: [ItemShareRecord],
                                 activePersonaItemIds: Set<String>) -> String? {
        recipientShares.first { activePersonaItemIds.contains($0.itemId) }?.zoneName
    }
}
