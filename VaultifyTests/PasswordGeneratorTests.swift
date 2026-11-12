import XCTest
@testable import Vaultify

/// The password, PIN and passphrase generators. Output is random, so each
/// property is asserted over many draws: a guarantee that holds "most of the
/// time" is exactly the failure mode these tests exist to catch.
final class PasswordGeneratorTests: XCTestCase {

    private let draws = 500
    private let ambiguous: Set<Character> = ["0", "O", "1", "l", "I"]
    private let symbolSet = Set("!@#$%^&*()-_=+[]{};:,.?")

    // MARK: Password length

    func testPasswordHasExactlyTheRequestedLength() {
        for length in [1, 2, 3, 4, 8, 20, 64, 128] {
            var options = PasswordOptions()
            options.length = length
            XCTAssertEqual(PasswordGenerator.generate(options).count, length, "length \(length)")
        }
    }

    func testNonPositiveLengthYieldsEmptyPassword() {
        var options = PasswordOptions()
        options.length = 0
        XCTAssertEqual(PasswordGenerator.generate(options), "")
        options.length = -5
        XCTAssertEqual(PasswordGenerator.generate(options), "")
    }

    // MARK: Character classes

    func testDefaultPasswordAlwaysContainsEveryClass() {
        // Regression: drawing every position from the merged pool left about
        // 12% of default passwords without a digit.
        for _ in 0..<draws {
            let password = PasswordGenerator.generate(PasswordOptions())
            assertContainsEveryClass(password, options: PasswordOptions())
        }
    }

    func testShortestPasswordThatFitsEveryClassStillContainsAll() {
        var options = PasswordOptions()
        options.length = 4
        for _ in 0..<draws {
            assertContainsEveryClass(PasswordGenerator.generate(options), options: options)
        }
    }

    func testEveryClassCombinationIsHonoured() {
        for mask in 1..<16 {
            var options = PasswordOptions()
            options.lowercase = mask & 1 != 0
            options.uppercase = mask & 2 != 0
            options.digits = mask & 4 != 0
            options.symbols = mask & 8 != 0
            options.length = 12
            for _ in 0..<50 {
                let password = PasswordGenerator.generate(options)
                XCTAssertEqual(password.count, 12)
                assertContainsEveryClass(password, options: options)
                assertUsesOnlyEnabledClasses(password, options: options)
            }
        }
    }

    func testLengthBelowClassCountStaysWithinThePool() {
        var options = PasswordOptions()
        options.length = 2
        let allowed = Set(PasswordGenerator.characterClasses(options).joined())
        for _ in 0..<draws {
            let password = PasswordGenerator.generate(options)
            XCTAssertEqual(password.count, 2)
            XCTAssertTrue(Set(password).isSubset(of: allowed), password)
            // Two guaranteed characters come from two different classes.
            XCTAssertEqual(classCount(in: password), 2, password)
        }
    }

    func testAllClassesOffFallsBackToLowercase() {
        var options = PasswordOptions()
        options.lowercase = false
        options.uppercase = false
        options.digits = false
        options.symbols = false
        for _ in 0..<50 {
            let password = PasswordGenerator.generate(options)
            XCTAssertEqual(password.count, options.length)
            XCTAssertTrue(password.allSatisfy { $0.isLowercase && $0.isLetter }, password)
        }
    }

    func testAvoidAmbiguousExcludesLookalikes() {
        var options = PasswordOptions()
        options.avoidAmbiguous = true
        options.length = 64
        for _ in 0..<200 {
            let password = PasswordGenerator.generate(options)
            XCTAssertTrue(ambiguous.isDisjoint(with: password), password)
        }
    }

    func testAmbiguousCharactersAreReachableWhenAllowed() {
        var options = PasswordOptions()
        options.avoidAmbiguous = false
        options.length = 128
        var seen = Set<Character>()
        for _ in 0..<200 { seen.formUnion(PasswordGenerator.generate(options)) }
        // 25,600 draws from a ~85-character pool: missing any one is ~1e-130.
        XCTAssertTrue(ambiguous.isSubset(of: seen), "missing \(ambiguous.subtracting(seen))")
    }

    func testGuaranteedCharactersLandInRandomPositions() {
        // The shuffle must move the guaranteed characters: without it the
        // first four positions would always be lower, upper, digit, symbol.
        var options = PasswordOptions()
        options.length = 20
        var firstCharIsDigit = 0
        for _ in 0..<draws {
            let first = PasswordGenerator.generate(options).first!
            if first.isNumber { firstCharIsDigit += 1 }
        }
        XCTAssertGreaterThan(firstCharIsDigit, 0)
        XCTAssertLessThan(firstCharIsDigit, draws / 2)
    }

    func testPasswordsDoNotRepeat() {
        let passwords = (0..<draws).map { _ in PasswordGenerator.generate(PasswordOptions()) }
        XCTAssertEqual(Set(passwords).count, passwords.count)
    }

    // MARK: PIN

    func testPinIsDigitsOnlyAtRequestedLength() {
        for length in [1, 4, 6, 12] {
            let pin = PasswordGenerator.pin(PinOptions(length: length))
            XCTAssertEqual(pin.count, length)
            XCTAssertTrue(pin.allSatisfy { $0.isASCII && $0.isNumber }, pin)
        }
    }

    func testNonPositivePinLengthYieldsEmpty() {
        XCTAssertEqual(PasswordGenerator.pin(PinOptions(length: 0)), "")
    }

    func testPinCanContainZeroAndOne() {
        // PINs deliberately use the full digit set: there is nothing to misread
        // on a keypad, and dropping 0 and 1 would cost entropy.
        var seen = Set<Character>()
        for _ in 0..<200 { seen.formUnion(PasswordGenerator.pin(PinOptions(length: 12))) }
        XCTAssertEqual(seen, Set("0123456789"))
    }

    // MARK: Passphrase

    func testWordListIsLoadedAndClean() {
        let words = DicewareWordList.words
        XCTAssertEqual(words.count, 7772)
        XCTAssertEqual(Set(words).count, words.count, "duplicate words lower the entropy")
        XCTAssertTrue(words.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLowercase && $0.isLetter } })
    }

    func testPassphraseHasRequestedWordCountAndSeparator() {
        for count in [3, 5, 10] {
            var options = PassphraseOptions()
            options.wordCount = count
            options.separator = "-"
            let parts = PasswordGenerator.passphrase(options).split(separator: "-", omittingEmptySubsequences: false)
            XCTAssertEqual(parts.count, count)
        }
    }

    func testPassphraseWordCountBelowOneStillYieldsOneWord() {
        var options = PassphraseOptions()
        options.wordCount = 0
        options.includeNumber = false
        options.capitalize = false
        let phrase = PasswordGenerator.passphrase(options)
        XCTAssertFalse(phrase.contains(options.separator))
        XCTAssertTrue(DicewareWordList.words.contains(phrase))
    }

    func testPassphraseNumberIsAppendedToExactlyOneWord() {
        var options = PassphraseOptions()
        options.separator = " "
        for _ in 0..<draws {
            let words = PasswordGenerator.passphrase(options).split(separator: " ").map(String.init)
            let numbered = words.filter { $0.last?.isNumber == true }
            XCTAssertEqual(numbered.count, 1, words.joined(separator: " "))
            let digits = numbered[0].reversed().prefix { $0.isNumber }
            XCTAssertTrue((1...2).contains(digits.count))
            XCTAssertLessThan(Int(String(digits.reversed()))!, 100)
        }
    }

    func testPassphraseWordsComeFromTheListAndHonourCapitalisation() {
        let list = Set(DicewareWordList.words)
        for capitalize in [true, false] {
            var options = PassphraseOptions()
            options.capitalize = capitalize
            options.includeNumber = false
            options.separator = "."
            for _ in 0..<100 {
                for word in PasswordGenerator.passphrase(options).split(separator: ".") {
                    XCTAssertTrue(list.contains(word.lowercased()), String(word))
                    XCTAssertEqual(word.first!.isUppercase, capitalize, String(word))
                    XCTAssertTrue(word.dropFirst().allSatisfy(\.isLowercase), String(word))
                }
            }
        }
    }

    func testEmptySeparatorJoinsWordsDirectly() {
        var options = PassphraseOptions()
        options.separator = ""
        options.includeNumber = false
        options.wordCount = 4
        let phrase = PasswordGenerator.passphrase(options)
        XCTAssertTrue(phrase.allSatisfy(\.isLetter))
        XCTAssertEqual(phrase.filter(\.isUppercase).count, 4)
    }

    // MARK: Helpers

    private func classCount(in password: String) -> Int {
        [password.contains(where: \.isLowercase),
         password.contains(where: \.isUppercase),
         password.contains(where: \.isNumber),
         password.contains(where: symbolSet.contains)].filter { $0 }.count
    }

    private func assertContainsEveryClass(_ password: String, options: PasswordOptions,
                                          file: StaticString = #filePath, line: UInt = #line) {
        if options.lowercase {
            XCTAssertTrue(password.contains(where: \.isLowercase), "no lowercase: \(password)", file: file, line: line)
        }
        if options.uppercase {
            XCTAssertTrue(password.contains(where: \.isUppercase), "no uppercase: \(password)", file: file, line: line)
        }
        if options.digits {
            XCTAssertTrue(password.contains(where: \.isNumber), "no digit: \(password)", file: file, line: line)
        }
        if options.symbols {
            XCTAssertTrue(password.contains(where: symbolSet.contains), "no symbol: \(password)", file: file, line: line)
        }
    }

    private func assertUsesOnlyEnabledClasses(_ password: String, options: PasswordOptions,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let allowed = Set(PasswordGenerator.characterClasses(options).joined())
        XCTAssertTrue(Set(password).isSubset(of: allowed), "outside pool: \(password)", file: file, line: line)
    }
}
