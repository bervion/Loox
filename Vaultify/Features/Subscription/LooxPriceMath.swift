import Foundation

/// Pure price math for the paywall's factual comparison line (proposal §4.3).
/// The line renders ONLY when live StoreKit prices prove it — never from
/// hardcoded amounts, and only comparing products in the same currency
/// (StoreKit storefront prices within one store share the currency).
nonisolated enum LooxPriceMath {
    enum AnnualVersusMonthly: Equatable {
        /// Max Annual is clearly cheaper per month than Plus Monthly.
        case cheaperPerMonth
        /// Within a few percent either way (e.g. VN 349k/12 ≈ 29k) — describe
        /// as approximately equal, never as cheaper.
        case approximatelyEqual
        /// The decoy relationship doesn't hold at this storefront — show nothing.
        case notComparable
    }

    static func perMonth(annual: Decimal) -> Decimal {
        annual / 12
    }

    /// Thresholds: "cheaper" needs a real margin (≤ 95% of the monthly price);
    /// "approximately equal" tolerates rounding up to +2%. Anything above
    /// renders no claim at all.
    static func compare(maxAnnual: Decimal, plusMonthly: Decimal) -> AnnualVersusMonthly {
        guard plusMonthly > 0, maxAnnual > 0 else { return .notComparable }
        let ratio = perMonth(annual: maxAnnual) / plusMonthly
        if ratio <= Decimal(string: "0.95")! { return .cheaperPerMonth }
        if ratio <= Decimal(string: "1.02")! { return .approximatelyEqual }
        return .notComparable
    }
}
