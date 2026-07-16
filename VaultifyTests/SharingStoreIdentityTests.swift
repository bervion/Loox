import XCTest
@testable import Vaultify

/// Part 1 (Family full-group sharing, A2): `ItemShareRecord`'s per-(zone,item)
/// composite identity — a zone can now hold N item-shares instead of one.
/// Pins two things: (a) the NEW sibling-safe behavior (upsert/remove/status
/// scoped to the right item, not the whole zone), and (b) that with exactly
/// one item per zone (today's shipped shape,
/// `FamilyShareTransport.perGrantEnabled == false`) every operation is STILL
/// byte-for-byte what it was before this rework — the back-compat bar from
/// `family-group-transport.md` A2.
@MainActor
final class SharingStoreIdentityTests: XCTestCase {

    private func record(zone: String, item: String, recipient: String = "a@b.com",
                        confirmed: Bool = false, statusRaw: String? = nil) -> ItemShareRecord {
        ItemShareRecord(itemId: item, zoneName: zone, recipientLabel: recipient,
                        grantId: confirmed ? "g-\(item)" : nil, createdAtUnixMs: 0,
                        fingerprintConfirmed: confirmed, statusRaw: statusRaw)
    }

    // MARK: Identity

    func testIdIsCompositeOfZoneAndItem() {
        let r = record(zone: "apz-z", item: "item-1")
        XCTAssertEqual(r.id, "apz-z::item-1")
    }

    func testDistinctItemsInSameZoneHaveDistinctIds() {
        let a = record(zone: "apz-fam", item: "item-A")
        let b = record(zone: "apz-fam", item: "item-B")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: Back-compat — legacy JSON decode

    func testLegacyJSONWithoutAnIdFieldStillDecodes() throws {
        // `id` was NEVER an encoded key (it was always computed, `= zoneName`
        // pre-A2) — a legacy blob has no "id" key at all.
        let legacy = """
        {"itemId":"item-9","zoneName":"apz-legacy","recipientLabel":"a@b.com",
         "createdAtUnixMs":0,"fingerprintConfirmed":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ItemShareRecord.self, from: legacy)
        XCTAssertEqual(decoded.itemId, "item-9")
        XCTAssertEqual(decoded.zoneName, "apz-legacy")
        XCTAssertEqual(decoded.id, "apz-legacy::item-9")
    }

    // MARK: Back-compat — flag-OFF (one item per zone) behavioral parity

    func testFlagOffSingleItemPerZoneUpsertRemoveStatusBehaveAsBefore() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        let pending = record(zone: "apz-solo", item: "item-1")
        store.upsert(pending)
        XCTAssertEqual(store.shares.count, 1)

        // Re-upsert under the SAME (zoneName, itemId) pair — as the real
        // pending → confirmed flow does (ShareAccessSheet) — replaces, never
        // duplicates, exactly like the old zoneName-only identity.
        var confirmed = pending
        confirmed.fingerprintConfirmed = true
        confirmed.grantId = "g1"
        store.upsert(confirmed)
        XCTAssertEqual(store.shares.count, 1)
        XCTAssertEqual(store.shares.first?.status, .active)

        store.updateStatus(zoneName: "apz-solo", to: .accepted) // no-op: already confirmed
        XCTAssertEqual(store.shares.first?.status, .active)

        store.remove(zoneName: "apz-solo")
        XCTAssertTrue(store.shares.isEmpty)
    }

    // MARK: New behavior — siblings in one zone

    func testUpsertReplacesOnlyTheMatchingItemNotTheWholeZone() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        store.upsert(record(zone: "apz-fam", item: "item-A"))
        store.upsert(record(zone: "apz-fam", item: "item-B"))
        XCTAssertEqual(store.shares.count, 2, "the old bug: upserting B wiped A")

        var updatedA = record(zone: "apz-fam", item: "item-A")
        updatedA.grantId = "grant-a-2"
        store.upsert(updatedA)

        XCTAssertEqual(store.shares.count, 2, "still 2 — replaced A in place, B untouched")
        XCTAssertEqual(store.shares.first(where: { $0.itemId == "item-A" })?.grantId, "grant-a-2")
        XCTAssertNil(store.shares.first(where: { $0.itemId == "item-B" })?.grantId)
    }

    func testRemoveByZoneAndItemRemovesOnlyThatSibling() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        store.upsert(record(zone: "apz-fam", item: "item-A"))
        store.upsert(record(zone: "apz-fam", item: "item-B"))

        store.remove(zoneName: "apz-fam", itemId: "item-A")

        XCTAssertEqual(store.shares.map(\.itemId), ["item-B"])
    }

    func testRemoveByZoneAloneRemovesEverySiblingInThatZone() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        store.upsert(record(zone: "apz-fam", item: "item-A"))
        store.upsert(record(zone: "apz-fam", item: "item-B"))
        store.upsert(record(zone: "apz-other", item: "item-C"))

        store.remove(zoneName: "apz-fam")

        XCTAssertEqual(store.shares.map(\.itemId), ["item-C"])
    }

    func testUpdateStatusAdvancesEverySiblingInTheZoneTogether() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        store.upsert(record(zone: "apz-fam", item: "item-A"))
        store.upsert(record(zone: "apz-fam", item: "item-B"))

        store.updateStatus(zoneName: "apz-fam", to: .readyForCeremony)

        XCTAssertTrue(store.shares.allSatisfy { $0.status == .readyForCeremony })
    }

    func testUpdateStatusNeverRegressesAnAlreadyConfirmedSiblingEvenWhenOthersAdvance() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        var confirmedA = record(zone: "apz-fam", item: "item-A")
        confirmedA.fingerprintConfirmed = true
        store.upsert(confirmedA)
        store.upsert(record(zone: "apz-fam", item: "item-B")) // still inviteSent

        store.updateStatus(zoneName: "apz-fam", to: .accepted)

        XCTAssertEqual(store.shares.first(where: { $0.itemId == "item-A" })?.status, .active)
        XCTAssertEqual(store.shares.first(where: { $0.itemId == "item-B" })?.status, .accepted)
    }

    func testSharesForRecipientFiltersAcrossZonesForOneRecipientOnly() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }

        store.upsert(record(zone: "apz-1", item: "item-A", recipient: "mom@example.com"))
        store.upsert(record(zone: "apz-2", item: "item-B", recipient: "mom@example.com"))
        store.upsert(record(zone: "apz-3", item: "item-C", recipient: "dad@example.com"))

        let momsShares = store.shares(forRecipient: "mom@example.com")

        XCTAssertEqual(Set(momsShares.map(\.itemId)), ["item-A", "item-B"])
    }
}
