import CloudKit
import XCTest
@testable import Vaultify

/// The delta-sync device mirror behind Profile › Devices: upsert/dedupe of pulled
/// `OwnerDevice` records, revocation (sign-out) markers, and the clear used by
/// Erase Vault / remote sign-out.
final class DeviceRegistryMirrorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DeviceRegistryMirror.clear()
    }

    override func tearDown() {
        DeviceRegistryMirror.clear()
        super.tearDown()
    }

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Vault", ownerName: CKCurrentUserDefaultName)
    }

    private func deviceRecord(id: String, model: String = "iPhone 16") -> CKRecord {
        let record = CKRecord(recordType: DeviceRegistryService.recordType,
                              recordID: CKRecord.ID(recordName: "owner-device-\(id)", zoneID: zoneID))
        record["deviceID"] = id as CKRecordValue
        record["name"] = "iPhone" as CKRecordValue
        record["model"] = model as CKRecordValue
        record["lastSeenAt"] = Date.now as CKRecordValue
        record["appVersion"] = "1.40.0" as CKRecordValue
        return record
    }

    private func revocationRecord(id: String) -> CKRecord {
        let record = CKRecord(recordType: DeviceRegistryService.revocationRecordType,
                              recordID: CKRecord.ID(recordName: "revoke-\(id)", zoneID: zoneID))
        record["deviceID"] = id as CKRecordValue
        return record
    }

    func testApplyUpsertsAndDedupesByDeviceID() {
        DeviceRegistryMirror.apply(deviceRecord(id: "aa"))
        DeviceRegistryMirror.apply(deviceRecord(id: "aa", model: "iPhone 17 Pro"))
        DeviceRegistryMirror.apply(deviceRecord(id: "bb"))
        let devices = DeviceRegistryMirror.devices()
        XCTAssertEqual(devices.count, 2, "same deviceID must upsert, not duplicate")
        XCTAssertEqual(devices.first { $0.id == "aa" }?.model, "iPhone 17 Pro",
                       "a re-published record must win over the stale mirror entry")
    }

    func testRevocationMarkerRoundTrip() {
        DeviceRegistryMirror.apply(revocationRecord(id: "aa"))
        XCTAssertTrue(DeviceRegistryMirror.isRevoked("aa"))
        XCTAssertFalse(DeviceRegistryMirror.isRevoked("bb"),
                       "a marker must only sign out the device it names")
    }

    func testMarkRevokedLocallyMatchesPulledMarker() {
        DeviceRegistryMirror.markRevoked("cc")
        XCTAssertTrue(DeviceRegistryMirror.isRevoked("cc"),
                      "the owner's own log-out write hides the device immediately")
    }

    func testUnrelatedRecordTypesAreIgnored() {
        let record = CKRecord(recordType: "VaultItem",
                              recordID: CKRecord.ID(recordName: "item-1", zoneID: zoneID))
        DeviceRegistryMirror.apply(record)
        XCTAssertTrue(DeviceRegistryMirror.devices().isEmpty)
        XCTAssertTrue(DeviceRegistryMirror.revokedIDs().isEmpty)
    }

    func testClearRemovesDevicesAndRevocations() {
        DeviceRegistryMirror.apply(deviceRecord(id: "aa"))
        DeviceRegistryMirror.markRevoked("bb")
        DeviceRegistryMirror.clear()
        XCTAssertTrue(DeviceRegistryMirror.devices().isEmpty)
        XCTAssertTrue(DeviceRegistryMirror.revokedIDs().isEmpty)
    }
}
