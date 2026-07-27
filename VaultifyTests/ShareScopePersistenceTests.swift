import XCTest
@testable import Vaultify

/// The owner's field selection and device scope are frozen onto the share
/// record when the invite is created, then replayed once the recipient's key
/// lands — that is what removes the second configuration pass.
///
/// Two things have to hold for that to be safe:
/// 1. records written by older builds (no scope fields) still decode, and are
///    distinguishable from records that genuinely granted nothing;
/// 2. the device scope survives the round trip, because the in-memory default
///    is the MORE permissive one. A single-device share that came back as
///    multi-device would silently widen what the owner chose.
@MainActor
final class ShareScopePersistenceTests: XCTestCase {

    private func decode(_ json: String) throws -> ItemShareRecord {
        try JSONDecoder().decode(ItemShareRecord.self, from: Data(json.utf8))
    }

    // MARK: Back-compat

    func testLegacyRecordWithoutScopeFieldsStillDecodes() throws {
        // Exactly the shape a build before persisted scope wrote.
        let legacy = """
        {"itemId":"item-1","zoneName":"apz-z","recipientLabel":"a@b.com",
         "createdAtUnixMs":123,"fingerprintConfirmed":false}
        """
        let record = try decode(legacy)
        XCTAssertEqual(record.itemId, "item-1")
        XCTAssertEqual(record.zoneName, "apz-z")
        XCTAssertNil(record.plannedCapabilities)
        XCTAssertNil(record.plannedAllowMultipleDevices)
    }

    /// A legacy record cannot be activated unattended: nil scope means "this
    /// device never recorded what the owner chose", which is NOT the same as
    /// "the owner chose nothing". Only a human can supply it.
    func testAbsentScopeIsDistinctFromAnEmptySelection() throws {
        let legacy = try decode("""
        {"itemId":"i","zoneName":"z","recipientLabel":"a@b.com",
         "createdAtUnixMs":0,"fingerprintConfirmed":false}
        """)
        XCTAssertNil(legacy.plannedCapabilities)

        var explicitlyEmpty = legacy
        explicitlyEmpty.plannedCapabilities = [:]
        XCTAssertEqual(explicitlyEmpty.plannedCapabilities, [:])
        XCTAssertNotNil(explicitlyEmpty.plannedCapabilities)
    }

    // MARK: Round trip

    func testPlannedScopeSurvivesEncodeDecode() throws {
        let capabilities: [String: FieldCapability] = [
            "f-user": .value(.shared),
            "f-pass": .value(.none),
            "f-totp": .totp(.askEachTime),
            PasskeySlot.slotId(credentialID: Data([0xAB, 0xCD])): .passkey(.shared),
        ]
        let original = ItemShareRecord(
            itemId: "item-1", zoneName: "apz-z", recipientLabel: "a@b.com",
            grantId: nil, createdAtUnixMs: 7, fingerprintConfirmed: false,
            plannedCapabilities: capabilities, plannedAllowMultipleDevices: false)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ItemShareRecord.self, from: data)

        XCTAssertEqual(decoded.plannedCapabilities, capabilities)
        XCTAssertEqual(decoded.plannedAllowMultipleDevices, false)
    }

    /// The regression this field exists to prevent: resuming a share must not
    /// re-derive device scope from the sheet's default (multi-device).
    func testSingleDeviceScopeDoesNotWidenAcrossPersistence() throws {
        let single = ItemShareRecord(
            itemId: "i", zoneName: "z", recipientLabel: "a@b.com",
            grantId: nil, createdAtUnixMs: 0, fingerprintConfirmed: false,
            plannedCapabilities: ["f": .value(.shared)],
            plannedAllowMultipleDevices: false)

        let decoded = try JSONDecoder().decode(
            ItemShareRecord.self, from: try JSONEncoder().encode(single))

        // How the activation path reads it — the `?? true` fallback must only
        // ever apply to records that never recorded a scope.
        XCTAssertEqual(decoded.plannedAllowMultipleDevices ?? true, false)
    }

    // MARK: Store persistence

    func testStoreRoundTripsScopeThroughDefaults() throws {
        let suite = "share-scope-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SharingStore(defaults: defaults)
        store.upsert(ItemShareRecord(
            itemId: "item-1", zoneName: "apz-z", recipientLabel: "a@b.com",
            grantId: nil, createdAtUnixMs: 0, fingerprintConfirmed: false,
            plannedCapabilities: ["f-pass": .value(.shared)],
            plannedAllowMultipleDevices: false))

        let reloaded = SharingStore(defaults: defaults)
        let record = try XCTUnwrap(reloaded.shares.first)
        XCTAssertEqual(record.plannedCapabilities, ["f-pass": .value(.shared)])
        XCTAssertEqual(record.plannedAllowMultipleDevices, false)
    }

    /// Revoking one item must leave its siblings in the same zone alone — a
    /// Space fan-out puts many items in ONE zone per person.
    func testRemovingOneItemLeavesZoneSiblings() throws {
        let suite = "share-scope-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SharingStore(defaults: defaults)
        for item in ["item-A", "item-B", "item-C"] {
            store.upsert(ItemShareRecord(
                itemId: item, zoneName: "apz-shared", recipientLabel: "a@b.com",
                grantId: "g-\(item)", createdAtUnixMs: 0, fingerprintConfirmed: true))
        }

        store.remove(zoneName: "apz-shared", itemId: "item-B")

        XCTAssertEqual(Set(store.shares.map(\.itemId)), ["item-A", "item-C"])
    }
}
