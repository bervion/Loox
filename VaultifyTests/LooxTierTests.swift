import XCTest
@testable import Vaultify

/// Loox membership foundation: the tier ordering, the frozen V1 quota contract
/// (proposal §3.1) and the product-ID allowlist mapping. These pins are the
/// commercial contract — a failing test here means the contract changed, which
/// requires grandfathering or an explicit owner decision, not a test edit.
final class LooxTierTests: XCTestCase {

    // MARK: Ordering

    func testTierOrderingIsFreeThenPlusThenMax() {
        XCTAssertLessThan(LooxTier.free, .plus)
        XCTAssertLessThan(LooxTier.plus, .max)
        XCTAssertEqual([LooxTier.max, .free, .plus].max(), .max)
    }

    func testDisplayNamesAreTheBrandNouns() {
        XCTAssertEqual(LooxTier.free.displayName, "Loox")
        XCTAssertEqual(LooxTier.plus.displayName, "Loox+")
        XCTAssertEqual(LooxTier.max.displayName, "Loox Max")
    }

    // MARK: Frozen quota table (V1 commercial contract)

    func testFreeQuotas() {
        let q = LooxTier.free.quotas
        XCTAssertEqual(q.personas, 1)
        XCTAssertEqual(q.retainedAliases, 1)
        XCTAssertEqual(q.linkCreates30d, 3)
        XCTAssertEqual(q.quickViewApprovals30d, 3)
        XCTAssertEqual(q.outgoingRecipients, 0)
        XCTAssertFalse(q.fullWatchtower)
        XCTAssertFalse(q.fullThemes)
    }

    func testPlusQuotas() {
        let q = LooxTier.plus.quotas
        XCTAssertEqual(q.personas, 3)
        XCTAssertEqual(q.retainedAliases, 10)
        XCTAssertEqual(q.linkCreates30d, 30)
        XCTAssertEqual(q.quickViewApprovals30d, 30)
        XCTAssertEqual(q.outgoingRecipients, 1)
        XCTAssertTrue(q.fullWatchtower)
        XCTAssertTrue(q.fullThemes)
    }

    func testMaxQuotas() {
        let q = LooxTier.max.quotas
        XCTAssertNil(q.personas, "Max personas carry no product cap")
        XCTAssertEqual(q.retainedAliases, 200)
        XCTAssertEqual(q.linkCreates30d, 300)
        XCTAssertEqual(q.quickViewApprovals30d, 300)
        XCTAssertEqual(q.outgoingRecipients, 10)
        XCTAssertTrue(q.fullWatchtower)
        XCTAssertTrue(q.fullThemes)
    }

    // MARK: Product-ID allowlist

    func testEachProductIDMapsToItsTier() {
        XCTAssertEqual(LooxProductID.tier(for: "com.bervion.vaultify.subscription.max.annual"), .max)
        XCTAssertEqual(LooxProductID.tier(for: "com.bervion.vaultify.subscription.max.monthly"), .max)
        XCTAssertEqual(LooxProductID.tier(for: "com.bervion.vaultify.subscription.plus.annual"), .plus)
        XCTAssertEqual(LooxProductID.tier(for: "com.bervion.vaultify.subscription.plus.monthly"), .plus)
    }

    func testUnknownProductIDGrantsNothing() {
        XCTAssertNil(LooxProductID.tier(for: "com.bervion.vaultify.subscription.lifetime"))
        XCTAssertNil(LooxProductID.tier(for: ""))
        // Display names must never round-trip into the allowlist.
        XCTAssertNil(LooxProductID.tier(for: "Loox Max"))
    }

    func testCatalogListsAllFourProductsMaxFirst() {
        XCTAssertEqual(LooxProductID.all, [
            "com.bervion.vaultify.subscription.max.annual",
            "com.bervion.vaultify.subscription.max.monthly",
            "com.bervion.vaultify.subscription.plus.annual",
            "com.bervion.vaultify.subscription.plus.monthly",
        ])
    }

    // MARK: Entitlement resolution (highest verified tier wins)

    func testResolveTierIsFreeWithNoEntitlements() {
        XCTAssertEqual(LooxProductID.resolveTier(from: [String]()), .free)
    }

    func testResolveTierPicksTheSingleEntitledTier() {
        XCTAssertEqual(LooxProductID.resolveTier(from: [LooxProductID.plusMonthly]), .plus)
        XCTAssertEqual(LooxProductID.resolveTier(from: [LooxProductID.maxAnnual]), .max)
    }

    func testResolveTierPicksTheHighestAcrossMultipleEntitlements() {
        // Upgrade windows can briefly expose both subscriptions — Max must win
        // regardless of order.
        XCTAssertEqual(LooxProductID.resolveTier(from: [LooxProductID.plusAnnual, LooxProductID.maxMonthly]), .max)
        XCTAssertEqual(LooxProductID.resolveTier(from: [LooxProductID.maxMonthly, LooxProductID.plusAnnual]), .max)
    }

    func testResolveTierIgnoresUnknownProductIDs() {
        XCTAssertEqual(LooxProductID.resolveTier(from: ["com.other.app.pro"]), .free)
        XCTAssertEqual(LooxProductID.resolveTier(from: ["com.other.app.pro", LooxProductID.plusMonthly]), .plus)
    }
}
