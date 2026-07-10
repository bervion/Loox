import XCTest
@testable import Vaultify

/// Pure card-number utilities: BIN brand detection edges, Luhn validation, digit
/// normalization, display grouping (incl. Amex 4-6-5), and the expiry auto-format function.
final class PaymentCardTests: XCTestCase {

    // MARK: Brand detection

    func testVisaDetectedByLeadingFour() {
        XCTAssertEqual(PaymentCard.brand(for: "4111111111111111"), .visa)
        XCTAssertEqual(PaymentCard.brand(for: "4"), .visa)
    }

    func testAmexDetectedByLeadingThirtyFourOrThirtySeven() {
        XCTAssertEqual(PaymentCard.brand(for: "340000000000009"), .amex)
        XCTAssertEqual(PaymentCard.brand(for: "370000000000002"), .amex)
        XCTAssertNil(PaymentCard.brand(for: "350000000000000")) // not a real Amex prefix
    }

    func testMastercardDetectedByFiftyOneToFiftyFiveRange() {
        XCTAssertEqual(PaymentCard.brand(for: "5100000000000000"), .mastercard)
        XCTAssertEqual(PaymentCard.brand(for: "5500000000000000"), .mastercard)
        XCTAssertNil(PaymentCard.brand(for: "5600000000000000"))
    }

    func testMastercardDetectedByTwoTwoTwoOneToTwoSevenTwoZeroRange() {
        // 2221-2720 boundary edges, per the 2017 Mastercard BIN range expansion.
        XCTAssertEqual(PaymentCard.brand(for: "2221000000000000"), .mastercard)
        XCTAssertEqual(PaymentCard.brand(for: "2720000000000000"), .mastercard)
        XCTAssertNil(PaymentCard.brand(for: "2220999999999999"))
        XCTAssertNil(PaymentCard.brand(for: "2721000000000000"))
    }

    func testJCBDetectedByThreeFiveTwoEightToThreeFiveEightNineRange() {
        XCTAssertEqual(PaymentCard.brand(for: "3528000000000000"), .jcb)
        XCTAssertEqual(PaymentCard.brand(for: "3589000000000000"), .jcb)
        XCTAssertNil(PaymentCard.brand(for: "3527000000000000"))
        XCTAssertNil(PaymentCard.brand(for: "3590000000000000"))
    }

    func testDiscoverDetectedBySixZeroOneOneSixtyFiveOrSixFourFourToSixFourNine() {
        XCTAssertEqual(PaymentCard.brand(for: "6011000000000000"), .discover)
        XCTAssertEqual(PaymentCard.brand(for: "6500000000000000"), .discover)
        XCTAssertEqual(PaymentCard.brand(for: "6440000000000000"), .discover)
        XCTAssertEqual(PaymentCard.brand(for: "6490000000000000"), .discover)
        XCTAssertNil(PaymentCard.brand(for: "6430000000000000"))
    }

    func testUnionPayDetectedBySixtyTwo() {
        XCTAssertEqual(PaymentCard.brand(for: "6200000000000000"), .unionPay)
    }

    func testUnrecognizedPrefixReturnsNil() {
        XCTAssertNil(PaymentCard.brand(for: "1234567890123456"))
        XCTAssertNil(PaymentCard.brand(for: ""))
    }

    func testBrandDetectionToleratesSpacesAndDashes() {
        XCTAssertEqual(PaymentCard.brand(for: "4111 1111 1111 1111"), .visa)
        XCTAssertEqual(PaymentCard.brand(for: "3400-000000-00009"), .amex)
    }

    // MARK: Luhn validation

    func testLuhnValidKnownGoodNumbers() {
        XCTAssertTrue(PaymentCard.isLuhnValid("4111111111111111"))
        XCTAssertTrue(PaymentCard.isLuhnValid("378282246310005")) // Amex test PAN
        XCTAssertTrue(PaymentCard.isLuhnValid("6011111111111117")) // Discover test PAN
    }

    func testLuhnInvalidForBadChecksum() {
        XCTAssertFalse(PaymentCard.isLuhnValid("4111111111111112"))
        XCTAssertFalse(PaymentCard.isLuhnValid("1234567890123456"))
    }

    func testLuhnInvalidForEmptyOrTooShort() {
        XCTAssertFalse(PaymentCard.isLuhnValid(""))
        XCTAssertFalse(PaymentCard.isLuhnValid("4"))
    }

    // MARK: Digit normalization

    func testDigitsOnlyStripsEverythingButDigits() {
        XCTAssertEqual(PaymentCard.digitsOnly("4111 1111-1111 1111"), "4111111111111111")
        XCTAssertEqual(PaymentCard.digitsOnly("abc"), "")
    }

    func testNormalizedForStorageCapsToBrandMaxDigits() {
        // Amex caps at 15 even if more digits are typed/pasted.
        let overlong = "3400000000000009999"
        XCTAssertEqual(PaymentCard.normalizedForStorage(overlong).count, 15)
        // Unrecognized brand caps at the generic 19-digit ceiling.
        let unknownOverlong = String(repeating: "1", count: 25)
        XCTAssertEqual(PaymentCard.normalizedForStorage(unknownOverlong).count, 19)
    }

    // MARK: Display grouping

    func testFormattedForDisplayGroupsInFoursForNonAmex() {
        XCTAssertEqual(PaymentCard.formattedForDisplay("4111111111111111"), "4111 1111 1111 1111")
    }

    func testFormattedForDisplayGroupsFourSixFiveForAmex() {
        XCTAssertEqual(PaymentCard.formattedForDisplay("378282246310005"), "3782 822463 10005")
    }

    func testFormattedForDisplayHandlesPartialInput() {
        XCTAssertEqual(PaymentCard.formattedForDisplay("41111"), "4111 1")
        XCTAssertEqual(PaymentCard.formattedForDisplay(""), "")
    }

    func testFormattedForInputCapsAtBrandMaxLength() {
        let typed = "34000000000000099" // Amex + extra digits
        let formatted = PaymentCard.formattedForInput(typed)
        XCTAssertEqual(PaymentCard.digitsOnly(formatted).count, 15)
    }

    // MARK: Expiry auto-format (pure function extracted from `ExpiryFieldEditor`)

    func testExpiryAutoFormatInsertsSlashAfterMonth() {
        XCTAssertEqual(CardExpiryFormat.autoFormat("1228"), "12/28")
        XCTAssertEqual(CardExpiryFormat.autoFormat("12"), "12/")
        XCTAssertEqual(CardExpiryFormat.autoFormat("1"), "1")
        XCTAssertEqual(CardExpiryFormat.autoFormat(""), "")
    }

    func testExpiryAutoFormatClampsMonthToTwelve() {
        XCTAssertEqual(CardExpiryFormat.autoFormat("13"), "12/")
        XCTAssertEqual(CardExpiryFormat.autoFormat("1328"), "12/28")
        XCTAssertEqual(CardExpiryFormat.autoFormat("00"), "01/")
    }

    func testExpiryAutoFormatCapsAtFourDigits() {
        XCTAssertEqual(CardExpiryFormat.autoFormat("122899999"), "12/28")
    }

    func testExpiryKnownPatternMatching() {
        XCTAssertTrue(CardExpiryFormat.matchesKnownPattern("12/28"))
        XCTAssertTrue(CardExpiryFormat.matchesKnownPattern("12/2028"))
        XCTAssertTrue(CardExpiryFormat.matchesKnownPattern("12-28"))
        XCTAssertTrue(CardExpiryFormat.matchesKnownPattern(""))
        XCTAssertFalse(CardExpiryFormat.matchesKnownPattern("December 2028"))
        XCTAssertFalse(CardExpiryFormat.matchesKnownPattern("13/28")) // invalid month, not a known shape
    }

    // MARK: Scan heuristics (pure, no VisionKit dependency)

    func testLongestLuhnValidPANAcrossLines() {
        let lines = ["JANE DOE", "4111 1111 1111 1111", "VALID THRU 12/28"]
        XCTAssertEqual(CardScanHeuristics.longestLuhnValidPAN(in: lines), "4111111111111111")
    }

    func testLongestLuhnValidPANRejectsBadChecksum() {
        XCTAssertNil(CardScanHeuristics.longestLuhnValidPAN(in: ["4111 1111 1111 1112"]))
    }

    func testExpiryHeuristicNormalizesFourDigitYear() {
        XCTAssertEqual(CardScanHeuristics.expiry(in: ["VALID THRU 12/2028"]), "12/28")
        XCTAssertEqual(CardScanHeuristics.expiry(in: ["12/28"]), "12/28")
        XCTAssertNil(CardScanHeuristics.expiry(in: ["JANE DOE"]))
    }

    func testCardholderNameHeuristicSkipsBankKeywords() {
        let lines = ["VISA CLASSIC", "4111 1111 1111 1111", "JANE DOE", "VALID THRU 12/28"]
        XCTAssertEqual(CardScanHeuristics.cardholderName(in: lines), "JANE DOE")
        XCTAssertNil(CardScanHeuristics.cardholderName(in: ["4111 1111 1111 1111"]))
    }
}
