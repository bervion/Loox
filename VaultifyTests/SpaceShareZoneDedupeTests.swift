import XCTest
@testable import Vaultify

/// `SpaceShareZoneDedupe.existingZoneName` — the persona-scoped zone-reuse
/// rule `ShareSpaceSheet` (Family full-group sharing, phase A3 stage 2) uses
/// to decide whether to reuse a recipient's existing zone or mint a fresh
/// one. Pure function; no CloudKit involved.
final class SpaceShareZoneDedupeTests: XCTestCase {

    private func record(itemId: String, zoneName: String) -> ItemShareRecord {
        ItemShareRecord(itemId: itemId, zoneName: zoneName, recipientLabel: "bob@example.com",
                        createdAtUnixMs: 1, fingerprintConfirmed: true)
    }

    func testNoExistingSharesReturnsNil() {
        XCTAssertNil(SpaceShareZoneDedupe.existingZoneName(
            recipientShares: [], activePersonaItemIds: ["item-a"]))
    }

    func testReusesZoneOfAnItemTheActivePersonaOwns() {
        let shares = [record(itemId: "item-a", zoneName: "apz-1")]
        XCTAssertEqual(SpaceShareZoneDedupe.existingZoneName(
            recipientShares: shares, activePersonaItemIds: ["item-a"]), "apz-1")
    }

    /// INV-R03: a zone that only holds a DIFFERENT persona's item must never
    /// be reused for this persona's Space fan-out.
    func testDoesNotReuseZoneOwnedByAnotherPersona() {
        let shares = [record(itemId: "item-other-persona", zoneName: "apz-1")]
        XCTAssertNil(SpaceShareZoneDedupe.existingZoneName(
            recipientShares: shares, activePersonaItemIds: ["item-a"]))
    }

    /// A recipient can hold shares across MULTIPLE zones (e.g. one per
    /// persona) — only the zone matching the active persona is picked, even
    /// when it isn't first in a differently-ordered list.
    func testPicksTheActivePersonaZoneAmongMultipleZones() {
        let shares = [record(itemId: "item-other-persona", zoneName: "apz-other"),
                     record(itemId: "item-a", zoneName: "apz-mine")]
        XCTAssertEqual(SpaceShareZoneDedupe.existingZoneName(
            recipientShares: shares, activePersonaItemIds: ["item-a"]), "apz-mine")
    }

    /// Multiple item-shares already live in the SAME zone (a prior Space
    /// fan-out) — still resolves to that one zone, not an error.
    func testMultipleItemsInSameZoneStillResolveToOneZoneName() {
        let shares = [record(itemId: "item-a", zoneName: "apz-1"),
                     record(itemId: "item-b", zoneName: "apz-1")]
        XCTAssertEqual(SpaceShareZoneDedupe.existingZoneName(
            recipientShares: shares, activePersonaItemIds: ["item-a", "item-b"]), "apz-1")
    }

    func testEmptyActivePersonaItemIdsReturnsNil() {
        let shares = [record(itemId: "item-a", zoneName: "apz-1")]
        XCTAssertNil(SpaceShareZoneDedupe.existingZoneName(
            recipientShares: shares, activePersonaItemIds: []))
    }
}
