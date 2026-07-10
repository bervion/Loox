import XCTest
@testable import Vaultify

/// Pure parsing + predicate tests for the local search-operator grammar
/// (Loox Design DNA #10 — phase-04). No repository/environment access: these
/// exercise `SearchOperators` exactly as it runs in production, just with an
/// injected `Context` instead of a live `PasswordAudit`/passkey lookup.
final class SearchOperatorsTests: XCTestCase {

    private func item(_ id: String, category: ItemCategory = .login, totp: Bool = false) -> VaultItem {
        var fields: [DynamicField] = []
        if totp { fields.append(DynamicField(label: "One-time Code", kind: .totp, value: "123456")) }
        return VaultItem(id: id, category: category, title: "Item \(id)", fields: fields)
    }

    // MARK: Parsing — EN keywords

    func testParseRecognizesEnglishOperatorKeywords() {
        let parsed = SearchOperators.parse("weak gmail")
        XCTAssertEqual(parsed.operators, [.weakPassword])
        XCTAssertEqual(parsed.freeTextTokens, ["gmail"])
    }

    func testParseComposesMultipleOperatorsWithFreeText() {
        let parsed = SearchOperators.parse("2fa card work")
        XCTAssertEqual(Set(parsed.operators), [.hasTOTP, .category(.card)])
        XCTAssertEqual(parsed.freeTextTokens, ["work"])
    }

    func testParsePureFreeTextWhenNoOperatorRecognized() {
        let parsed = SearchOperators.parse("github personal")
        XCTAssertTrue(parsed.operators.isEmpty)
        XCTAssertEqual(parsed.freeTextTokens, ["github", "personal"])
    }

    // MARK: Parsing — VI keywords (diacritic + case insensitive)

    func testParseRecognizesVietnameseAccentedKeyword() {
        let parsed = SearchOperators.parse("yếu")
        XCTAssertEqual(parsed.operators, [.weakPassword])
        XCTAssertTrue(parsed.freeTextTokens.isEmpty)
    }

    func testParseRecognizesVietnameseKeywordWithoutDiacritics() {
        // A user typing without tone marks (common on non-VI keyboards) still matches.
        let parsed = SearchOperators.parse("trung")
        XCTAssertEqual(parsed.operators, [.reusedPassword])
    }

    func testParseRecognizesMultiWordVietnameseCategoryPhrase() {
        let parsed = SearchOperators.parse("đăng nhập netflix")
        XCTAssertEqual(parsed.operators, [.category(.login)])
        XCTAssertEqual(parsed.freeTextTokens, ["netflix"])
    }

    func testParsePrefersLongerPhraseOverShorterAlias() {
        // "ssh key" must be consumed whole, not leave a stray "key" free-text token.
        let parsed = SearchOperators.parse("ssh key production")
        XCTAssertEqual(parsed.operators, [.category(.sshKey)])
        XCTAssertEqual(parsed.freeTextTokens, ["production"])
    }

    func testParseCaseInsensitive() {
        let parsed = SearchOperators.parse("WEAK Reused PassKey")
        XCTAssertEqual(Set(parsed.operators), [.weakPassword, .reusedPassword, .hasPasskey])
    }

    func testParsePreservesDiacriticsInFreeTextTokens() {
        // Free-text tokens must keep their tone marks: `VaultItem.searchText` is
        // lowercased but NOT diacritic-folded, so a folded token ("ngan") would
        // silently miss every accented title ("ngân hàng acb"). Folding is for
        // KEYWORD recognition only.
        let parsed = SearchOperators.parse("yếu Ngân Hàng")
        XCTAssertEqual(parsed.operators, [.weakPassword])
        XCTAssertEqual(parsed.freeTextTokens, ["ngân", "hàng"])
    }

    // MARK: matches(_:operators:context:)

    func testMatchesHasTOTPReadsItemDirectly() {
        let withTOTP = item("a", totp: true)
        let withoutTOTP = item("b", totp: false)
        XCTAssertTrue(SearchOperators.matches(withTOTP, operators: [.hasTOTP], context: .empty))
        XCTAssertFalse(SearchOperators.matches(withoutTOTP, operators: [.hasTOTP], context: .empty))
    }

    func testMatchesWeakAndReusedReadFromInjectedContext() {
        let context = SearchOperators.Context(weakItemIDs: ["a"], reusedItemIDs: ["b"], passkeyItemIDs: [])
        XCTAssertTrue(SearchOperators.matches(item("a"), operators: [.weakPassword], context: context))
        XCTAssertFalse(SearchOperators.matches(item("b"), operators: [.weakPassword], context: context))
        XCTAssertTrue(SearchOperators.matches(item("b"), operators: [.reusedPassword], context: context))
    }

    func testMatchesCategoryOperator() {
        XCTAssertTrue(SearchOperators.matches(item("a", category: .card), operators: [.category(.card)], context: .empty))
        XCTAssertFalse(SearchOperators.matches(item("a", category: .login), operators: [.category(.card)], context: .empty))
    }

    func testMatchesANDsAcrossMultipleOperators() {
        let context = SearchOperators.Context(weakItemIDs: ["a"], reusedItemIDs: [], passkeyItemIDs: [])
        let matchesBoth = item("a", category: .login, totp: true)
        XCTAssertTrue(SearchOperators.matches(matchesBoth, operators: [.hasTOTP, .weakPassword, .category(.login)], context: context))
        // Fails the weak check (not in context) → AND across operators fails overall.
        let onlyTOTP = item("z", category: .login, totp: true)
        XCTAssertFalse(SearchOperators.matches(onlyTOTP, operators: [.hasTOTP, .weakPassword], context: context))
    }
}
