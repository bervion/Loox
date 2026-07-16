import XCTest
@testable import Vaultify

/// The paywall's factual per-month comparison (proposal §4.3): the line may
/// only claim what live prices prove, so the thresholds themselves are pinned.
final class LooxPriceMathTests: XCTestCase {

    func testPerMonthDividesAnAnnualPriceByTwelve() {
        XCTAssertEqual(LooxPriceMath.perMonth(annual: 24), 2)
        XCTAssertEqual(LooxPriceMath.perMonth(annual: 0), 0)
    }

    func testLaunchUSPricesReadApproximatelyEqualNotCheaper() {
        // 34.99 / 12 = 2.9158… vs 2.99 → ratio ≈ 0.975: within the ±few-percent
        // band but NOT clear-margin cheaper, so no "costs less" claim.
        XCTAssertEqual(LooxPriceMath.compare(maxAnnual: Decimal(string: "34.99")!,
                                             plusMonthly: Decimal(string: "2.99")!),
                       .approximatelyEqual)
    }

    func testLaunchVietnamPricesReadApproximatelyEqual() {
        // 349 000 / 12 = 29 083 vs 29 000 → ratio ≈ 1.003 (§4.3: VN must be
        // described as approximately equal).
        XCTAssertEqual(LooxPriceMath.compare(maxAnnual: 349_000, plusMonthly: 29_000),
                       .approximatelyEqual)
    }

    func testClearMarginReadsCheaperPerMonth() {
        // 24 / 12 = 2.00 vs 2.99 → ratio ≈ 0.67.
        XCTAssertEqual(LooxPriceMath.compare(maxAnnual: 24, plusMonthly: Decimal(string: "2.99")!),
                       .cheaperPerMonth)
    }

    func testBrokenDecoyRelationshipRendersNoClaim() {
        // 48 / 12 = 4.00 vs 2.99 → the decoy math fails; the line must vanish.
        XCTAssertEqual(LooxPriceMath.compare(maxAnnual: 48, plusMonthly: Decimal(string: "2.99")!),
                       .notComparable)
    }

    func testDegeneratePricesRenderNoClaim() {
        XCTAssertEqual(LooxPriceMath.compare(maxAnnual: 0, plusMonthly: Decimal(string: "2.99")!), .notComparable)
        XCTAssertEqual(LooxPriceMath.compare(maxAnnual: Decimal(string: "34.99")!, plusMonthly: 0), .notComparable)
    }
}
