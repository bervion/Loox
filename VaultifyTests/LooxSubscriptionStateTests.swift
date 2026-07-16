import XCTest
@testable import Vaultify

/// Pins the §8.1 state table row by row. A change here is a change to the
/// commercial/billing contract, not a refactor.
final class LooxSubscriptionStateTests: XCTestCase {

    func testStatesThatKeepFullPaidAccess() {
        for state: LooxSubscriptionState.AppleState in
            [.active, .autoRenewOffNotExpired, .upgraded, .pendingDowngrade, .billingGracePeriod] {
            XCTAssertEqual(LooxSubscriptionState.behavior(for: state), .fullPaidAccess, "\(state)")
        }
    }

    func testBillingRetryBeyondGraceBlocksNewPremiumOnly() {
        XCTAssertEqual(LooxSubscriptionState.behavior(for: .billingRetryBeyondGrace),
                       .blockNewPremiumActions)
    }

    func testExpiredFallsBackToFree() {
        XCTAssertEqual(LooxSubscriptionState.behavior(for: .expired), .freeTier)
    }

    func testRefundOrRevocationBlocksNewPremiumImmediately() {
        XCTAssertEqual(LooxSubscriptionState.behavior(for: .refundedOrRevoked),
                       .blockNewPremiumActions)
    }

    func testUndeterminedKeepsTheLastVerifiedEntitlement() {
        // A read/network failure must never downgrade or delete (§2.6, §8.1).
        XCTAssertEqual(LooxSubscriptionState.behavior(for: .undetermined), .keepLastVerified)
    }

    func testEveryStateHasAPinnedRow() {
        // CaseIterable exhaustiveness: adding a state without deciding its
        // behavior row must fail loudly here.
        XCTAssertEqual(LooxSubscriptionState.AppleState.allCases.count, 9)
    }
}
