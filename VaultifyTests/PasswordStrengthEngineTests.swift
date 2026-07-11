import XCTest
@testable import Vaultify

/// Known-answer table for the zxcvbn-lite engine. These pin the grade contract:
/// composition tricks must not inflate scores, and personal context caps them.
final class PasswordStrengthEngineTests: XCTestCase {

    private func grade(_ password: String,
                       context: StrengthContext = .empty) -> PasswordGrade {
        PasswordStrengthEngine.evaluate(password, context: context).grade
    }

    // MARK: - Very weak: top-list and trivial patterns

    func testTopListPasswordsAreVeryWeak() {
        for password in ["123456", "password", "qwerty", "iloveyou", "dragon",
                         "matkhau", "anhyeuem", "111111", "abc123"] {
            XCTAssertEqual(grade(password), .veryWeak, password)
        }
    }

    func testCompositionTricksDoNotRescueCommonWords() {
        // The classic failure of the old entropy formula.
        XCTAssertLessThanOrEqual(grade("Password1!"), .weak, "Password1!")
        XCTAssertLessThanOrEqual(grade("P@ssw0rd"), .weak, "P@ssw0rd")
        XCTAssertLessThanOrEqual(grade("Qwerty123!"), .weak, "Qwerty123!")
    }

    func testSequencesAndKeyboardWalksAreVeryWeak() {
        for password in ["abcdefgh", "12345678", "qwertyuiop", "asdfghjkl", "aaaaaaaa", "abcabcabc"] {
            XCTAssertEqual(grade(password), .veryWeak, password)
        }
    }

    func testWordPlusYearIsAtMostWeak() {
        XCTAssertLessThanOrEqual(grade("Summer2026"), .weak, "Summer2026")
        XCTAssertLessThanOrEqual(grade("Michael1994"), .weak, "Michael1994")
    }

    // MARK: - Strong side

    func testRandomLongPasswordsAreExcellent() {
        for password in ["kR9#mPz$vL2@qXw7!nT4", "x7Qw!2zR8pL#mN5v"] {
            XCTAssertEqual(grade(password), .excellent, password)
        }
    }

    func testDicewareStylePassphraseIsStrongOrBetter() {
        XCTAssertGreaterThanOrEqual(grade("correct horse battery staple"), .strong)
        XCTAssertGreaterThanOrEqual(grade("lamp-orbit-quilt-navy-brisk"), .strong)
    }

    func testMediumRandomIsAtLeastFair() {
        XCTAssertGreaterThanOrEqual(grade("gT4x9Qp2"), .fair, "8-char random mixed")
    }

    // MARK: - Context awareness

    func testPasswordContainingUsernameIsCappedAtWeak() {
        let context = StrengthContext(usernames: ["chinh.nguyen"])
        XCTAssertLessThanOrEqual(grade("chinh.nguyen#2026!Xz", context: context), .weak)
    }

    func testPasswordContainingDomainIsCappedAtWeak() {
        let context = StrengthContext(domains: ["github.com"])
        let result = PasswordStrengthEngine.evaluate("github!Rz84#qm", context: context)
        XCTAssertLessThanOrEqual(result.grade, .weak)
        XCTAssertTrue(result.matchedPatterns.contains("context"))
    }

    func testURLStopwordsDoNotBecomeContext() {
        // "com" inside a random password must not trip the context cap.
        let context = StrengthContext(domains: ["example.com"])
        let result = PasswordStrengthEngine.evaluate("kR9#comPz$vL2@qXw7", context: context)
        XCTAssertFalse(result.matchedPatterns.contains("context"))
    }

    // MARK: - Edge cases

    func testEmptyPasswordIsVeryWeakWithZeroGuesses() {
        let result = PasswordStrengthEngine.evaluate("")
        XCTAssertEqual(result.grade, .veryWeak)
        XCTAssertEqual(result.log10Guesses, 0)
    }

    func testLegacyThreeTierMappingStaysMonotonic() {
        XCTAssertEqual(PasswordStrength.evaluate("password"), .weak)
        XCTAssertEqual(PasswordStrength.evaluate("kR9#mPz$vL2@qXw7!nT4"), .strong)
    }

    func testPerformance500Passwords() {
        let samples = (0..<500).map { "Sample-Pw#\($0)x9Q" }
        measure {
            for s in samples { _ = PasswordStrengthEngine.evaluate(s) }
        }
    }
}
