import XCTest
@testable import Vaultify

/// Routing table for incoming CloudKit pushes, exercised through the pure
/// subscription-id overload (building a real `CKNotification` requires a
/// push userInfo dictionary the test host cannot fabricate reliably).
@MainActor
final class AppPushKindClassificationTests: XCTestCase {

    func testAcceptanceSubscriptionRoutesToShareAcceptance() {
        let id = ApprovalConfig.acceptSubscriptionPrefix + "apz-zone1"
        XCTAssertEqual(AppPushKind.classify(subscriptionID: id), .shareAcceptance)
    }

    func testRequestSubscriptionRoutesToApprovalRequest() {
        let id = ApprovalConfig.requestSubscriptionPrefix + "apz-zone1"
        XCTAssertEqual(AppPushKind.classify(subscriptionID: id), .approvalRequest)
    }

    func testSharedDatabaseSubscriptionRoutesToApprovalResponse() {
        XCTAssertEqual(
            AppPushKind.classify(subscriptionID: ApprovalConfig.sharedDatabaseSubscriptionID),
            .approvalResponse)
    }

    func testInviteInboxSubscriptionRoutesToRendezvous() {
        XCTAssertEqual(
            AppPushKind.classify(subscriptionID: ApprovalConfig.inviteInboxSubscriptionID),
            .inviteRendezvous)
    }

    func testUnknownAndMissingIDsDefaultToSyncPull() {
        // A pull is idempotent and harmless; misrouting an unknown id into
        // an approval pipeline would not be.
        XCTAssertEqual(AppPushKind.classify(subscriptionID: "some-future-subscription"),
                       .vaultRemoteChange)
        XCTAssertEqual(AppPushKind.classify(subscriptionID: nil), .vaultRemoteChange)
    }
}
