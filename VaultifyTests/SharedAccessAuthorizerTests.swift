import CloudKit
import XCTest
@testable import Vaultify

/// Layer-B outcome mapping (INV-01/03/06): live grant fetch result → gate
/// state. Pure function — the async plumbing around it is exercised in the
/// two-device QA pass.
final class SharedAccessAuthorizerTests: XCTestCase {

    private let expectedId = "grant-1"
    private let expectedEpoch: UInt32 = 3

    private func outcome(_ live: Result<(id: String, epoch: UInt32), any Error>)
        -> SharedAccessAuthorizer.State {
        SharedAccessAuthorizer.outcome(expectedGrantId: expectedId,
                                       expectedEpoch: expectedEpoch, live: live)
    }

    func testMatchingGrantAuthorizes() {
        XCTAssertEqual(outcome(.success(("grant-1", 3))), .authorized)
    }

    func testEpochDriftFailsClosed() {
        // Revoke bumps the epoch — a stale projection must not stay authorized.
        XCTAssertEqual(outcome(.success(("grant-1", 4))), .unavailable)
    }

    func testGrantIdDriftFailsClosed() {
        XCTAssertEqual(outcome(.success(("grant-2", 3))), .unavailable)
    }

    func testZoneGoneMeansRevoked() {
        XCTAssertEqual(outcome(.failure(CKError(.zoneNotFound))), .revoked)
        XCTAssertEqual(outcome(.failure(CKError(.userDeletedZone))), .revoked)
    }

    func testTransientErrorsAreUnavailableNotOfflineNotRevoked() {
        XCTAssertEqual(outcome(.failure(CKError(.networkFailure))), .unavailable)
        XCTAssertEqual(outcome(.failure(CancellationError())), .unavailable) // deadline hit
    }
}
