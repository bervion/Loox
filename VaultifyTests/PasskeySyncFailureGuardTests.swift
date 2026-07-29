import CloudKit
import CryptoKit
import Foundation
import XCTest
@testable import Vaultify

/// Guards on the two ways the passkey plane can fail forever without saying so:
/// a record CloudKit will never accept (oversized largeBlob), and a push
/// rejection that is a permanent schema gap rather than a passing network fault.
@MainActor
final class PasskeySyncFailureGuardTests: XCTestCase {

    private let key = [UInt8](repeating: 0x2a, count: 32)

    private func makeSecret() -> PasskeySecret {
        PasskeySecret(relyingParty: "example.com", userName: "kai", userHandle: Data([1]),
                      credentialID: Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }),
                      privateKeyRaw: P256.Signing.PrivateKey().rawRepresentation,
                      counter: 0, createdAt: .now)
    }

    // MARK: largeBlob bound (an unsavable record is a permanently dirty record)

    func testOversizedLargeBlobIsRefusedAndLeavesTheRecordUntouched() throws {
        let store = VaultStore(inMemory: true)
        // `record` below is a live SwiftData model read after the last use of its
        // store, so the container has to outlive the local.
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let record = store.allPasskeyRecords().first!
        store.markPasskeySynced(record, changeTag: "t1", snapshotUpdatedAt: record.updatedAt)

        let oversized = Data(repeating: 0xAB, count: PasskeyVault.maxLargeBlobBytes + 1)
        let written = vault.setLargeBlob(oversized, credentialID: secret.credentialID, key: key)

        XCTAssertFalse(written, "the relying party must be told the write failed")
        XCTAssertNil(record.largeBlobSealed, "an oversized blob is refused, never truncated")
        XCTAssertFalse(record.dirty, "a refused write must not re-dirty a synced record")
    }

    func testLargeBlobAtTheCapStillWrites() throws {
        let store = VaultStore(inMemory: true)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)

        let atCap = Data(repeating: 0xCD, count: PasskeyVault.maxLargeBlobBytes)

        XCTAssertTrue(vault.setLargeBlob(atCap, credentialID: secret.credentialID, key: key))
        XCTAssertEqual(vault.largeBlob(credentialID: secret.credentialID, key: key), atCap)
    }

    func testTheCapKeepsASealedBlobWellUnderCloudKitsFieldLimit() {
        // CloudKit refuses a Data field beyond roughly a megabyte without a CKAsset.
        XCTAssertLessThan(PasskeyVault.maxLargeBlobBytes, 1_048_576)
    }

    // MARK: Permanent vs transient push failures

    private func ckError(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> Error {
        NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    func testUndeployedRecordTypeReadsAsAPermanentSchemaFailure() {
        // An unknown record type comes back as invalidArguments; retrying it
        // forever is exactly what hid the undeployed VaultPasskey type.
        XCTAssertTrue(CloudSyncService.isSchemaFailure(ckError(.invalidArguments)))
        XCTAssertTrue(CloudSyncService.isSchemaFailure(ckError(.serverRejectedRequest)))
    }

    func testTransientFailuresAreNotClassifiedAsSchemaFailures() {
        XCTAssertFalse(CloudSyncService.isSchemaFailure(ckError(.networkUnavailable)))
        XCTAssertFalse(CloudSyncService.isSchemaFailure(ckError(.requestRateLimited)))
        XCTAssertFalse(CloudSyncService.isSchemaFailure(ckError(.zoneBusy)))
        XCTAssertFalse(CloudSyncService.isSchemaFailure(ckError(.notAuthenticated)))
        XCTAssertFalse(CloudSyncService.isSchemaFailure(URLError(.timedOut)),
                       "a non-CloudKit error can never be a schema gap")
    }

    func testAConstraintViolationIsNotReportedAsAnUndeployedSchema() {
        // This app declares no unique index, so a constraint violation says
        // something about the data, never that a record type is undeployed —
        // the banner would name the wrong cause.
        XCTAssertFalse(CloudSyncService.isSchemaFailure(ckError(.constraintViolation)))
    }

    func testPerRecordRejectionInsideAPartialFailureIsUnwrapped() {
        // Non-atomic batch saves report the real reason per record, so the
        // classifier has to look inside instead of reading the envelope code.
        let inner = ckError(.invalidArguments)
        let itemID = CKRecord.ID(recordName: "pk-1",
                                 zoneID: CKRecordZone.ID(zoneName: "Vault",
                                                         ownerName: CKCurrentUserDefaultName))
        let partial = ckError(.partialFailure,
                              userInfo: [CKPartialErrorsByItemIDKey: [itemID: inner]])

        XCTAssertTrue(CloudSyncService.isSchemaFailure(partial))
    }

    func testPartialFailureOfOnlyTransientRejectionsStaysTransient() {
        let itemID = CKRecord.ID(recordName: "pk-1",
                                 zoneID: CKRecordZone.ID(zoneName: "Vault",
                                                         ownerName: CKCurrentUserDefaultName))
        let partial = ckError(.partialFailure,
                              userInfo: [CKPartialErrorsByItemIDKey: [itemID: ckError(.networkUnavailable)]])

        XCTAssertFalse(CloudSyncService.isSchemaFailure(partial))
    }

    // MARK: Plane identity (the status names the plane, so the planes must be distinct)

    func testEveryPlaneMapsToItsOwnRecordTypeAndName() {
        let recordTypes = CloudSyncService.Plane.allCases.map(\.recordType)
        XCTAssertEqual(Set(recordTypes).count, recordTypes.count,
                       "two planes sharing a record type would misname the failing one")
        XCTAssertTrue(recordTypes.contains("VaultPasskey"))

        let names = CloudSyncService.Plane.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count, "each plane needs a distinct label")
        XCTAssertFalse(names.contains { $0.isEmpty })
    }
}
