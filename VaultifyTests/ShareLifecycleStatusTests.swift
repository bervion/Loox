import XCTest
@testable import Vaultify

/// Owner-side share lifecycle: status derivation, legacy-record back-compat,
/// monotonic ordering, and the store's no-downgrade / no-touch-confirmed guard.
/// Pure model logic — no CloudKit — so the "stuck on Waiting" fix's status
/// machine is pinned independent of the transport.
@MainActor
final class ShareLifecycleStatusTests: XCTestCase {

    private func record(statusRaw: String?, confirmed: Bool,
                        zone: String = "apz-test") -> ItemShareRecord {
        ItemShareRecord(itemId: "item-1", zoneName: zone, recipientLabel: "a@b.com",
                        grantId: confirmed ? "g" : nil, createdAtUnixMs: 0,
                        fingerprintConfirmed: confirmed, statusRaw: statusRaw)
    }

    // MARK: Derivation

    func testConfirmedRecordIsAlwaysActive() {
        // Even a stale/absent raw status must read active once confirmed.
        XCTAssertEqual(record(statusRaw: nil, confirmed: true).status, .active)
        XCTAssertEqual(record(statusRaw: "inviteSent", confirmed: true).status, .active)
    }

    func testUnconfirmedUsesRawStatus() {
        XCTAssertEqual(record(statusRaw: "accepted", confirmed: false).status, .accepted)
        XCTAssertEqual(record(statusRaw: "readyForCeremony", confirmed: false).status,
                       .readyForCeremony)
    }

    func testUnconfirmedWithoutRawDefaultsToInviteSent() {
        XCTAssertEqual(record(statusRaw: nil, confirmed: false).status, .inviteSent)
    }

    func testRawActiveWithoutConfirmationIsIgnored() {
        // `.active` is the confirmed terminal only — a raw "active" on an
        // unconfirmed record must not fake completion.
        XCTAssertEqual(record(statusRaw: "active", confirmed: false).status, .inviteSent)
    }

    // MARK: Legacy back-compat (records that predate `statusRaw`)

    func testLegacyRecordDecodesToInviteSent() throws {
        let legacy = """
        {"itemId":"i","zoneName":"apz-x","recipientLabel":"a@b.com",
         "createdAtUnixMs":0,"fingerprintConfirmed":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ItemShareRecord.self, from: legacy)
        XCTAssertNil(decoded.statusRaw)
        XCTAssertEqual(decoded.status, .inviteSent)
    }

    func testLegacyConfirmedRecordDecodesToActive() throws {
        let legacy = """
        {"itemId":"i","zoneName":"apz-x","recipientLabel":"a@b.com",
         "createdAtUnixMs":0,"fingerprintConfirmed":true,"grantId":"g"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ItemShareRecord.self, from: legacy)
        XCTAssertEqual(decoded.status, .active)
    }

    // MARK: Ordering

    func testRankStrictlyIncreases() {
        XCTAssertLessThan(ShareLifecycle.inviteSent.rank, ShareLifecycle.accepted.rank)
        XCTAssertLessThan(ShareLifecycle.accepted.rank, ShareLifecycle.readyForCeremony.rank)
        XCTAssertLessThan(ShareLifecycle.readyForCeremony.rank, ShareLifecycle.active.rank)
    }

    // MARK: Store monotonic guard

    func testUpdateStatusAdvancesButNeverDowngrades() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }
        store.upsert(record(statusRaw: nil, confirmed: false, zone: "apz-mono"))

        store.updateStatus(zoneName: "apz-mono", to: .accepted)
        XCTAssertEqual(store.shares.first?.status, .accepted)

        // Downgrade attempt is dropped.
        store.updateStatus(zoneName: "apz-mono", to: .inviteSent)
        XCTAssertEqual(store.shares.first?.status, .accepted)

        // Forward advance sticks.
        store.updateStatus(zoneName: "apz-mono", to: .readyForCeremony)
        XCTAssertEqual(store.shares.first?.status, .readyForCeremony)
    }

    func testUpdateStatusNeverTouchesConfirmedRecord() {
        let store = SharingStore()
        store.wipe()
        defer { store.wipe() }
        store.upsert(record(statusRaw: nil, confirmed: true, zone: "apz-done"))

        store.updateStatus(zoneName: "apz-done", to: .inviteSent)
        XCTAssertEqual(store.shares.first?.status, .active)
    }
}
