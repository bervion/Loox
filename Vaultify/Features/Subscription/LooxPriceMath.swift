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

    /// The first candidate style that formats `price` exactly as StoreKit's
    /// `displayPrice`, so a derived figure (the per-month equivalent) reads in
    /// the same format as the charged price above it. `Product.priceFormatStyle`
    /// can carry another locale than the one StoreKit used for `displayPrice`
    /// (seen on device: "34,99 US$" above "about 2.92 $ a month"). Spaces are
    /// compared loosely: formatters differ in which no-break space they emit.
    static func currencyStyle(reproducing displayPrice: String, price: Decimal,
                              from candidates: [Decimal.FormatStyle.Currency]) -> Decimal.FormatStyle.Currency? {
        let target = loosenedSpaces(displayPrice)
        return candidates.first { loosenedSpaces(price.formatted($0)) == target }
    }

    private static func loosenedSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
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
