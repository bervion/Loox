import Foundation

/// Loads the bundled diceware wordlist, derived from the EFF large list: 7772
/// unique lowercase, letters-only words (≈ 12.9 bits/word). Letters-only matters:
/// a word can never contain the passphrase separator or the appended number.
nonisolated enum DicewareWordList {
    static let words: [String] = {
        guard let url = Bundle.main.url(forResource: "eff_large_wordlist", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }()
}

nonisolated struct PasswordOptions: Equatable, Sendable {
    var length: Int = 20
    var uppercase = true
    var lowercase = true
    var digits = true
    var symbols = true
    var avoidAmbiguous = true
}

nonisolated struct PassphraseOptions: Equatable, Sendable {
    var wordCount: Int = 5
    var separator: String = "-"
    var capitalize = true
    var includeNumber = true
}

nonisolated struct PinOptions: Equatable, Sendable {
    var length: Int = 6
}

/// Cryptographically secure password and passphrase generation.
nonisolated enum PasswordGenerator {
    private static let lower = "abcdefghijkmnpqrstuvwxyz"
    private static let lowerFull = "abcdefghijklmnopqrstuvwxyz"
    private static let upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    private static let upperFull = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digitsSafe = "23456789"
    private static let digitsFull = "0123456789"
    private static let symbols = "!@#$%^&*()-_=+[]{};:,.?"

    /// A random password of exactly `options.length` characters.
    ///
    /// Every enabled character class appears at least once whenever the length
    /// allows it. Drawing every position from the merged pool alone left a
    /// default 20-character password without a digit about 12% of the time, and
    /// sites with composition rules reject those. The guaranteed characters are
    /// then shuffled into random positions, so they carry no positional pattern.
    static func generate(_ options: PasswordOptions) -> String {
        guard options.length > 0 else { return "" }
        let classes = characterClasses(options).map(Array.init)
        let pool = classes.flatMap { $0 }
        var result = classes.prefix(options.length).map(randomElement)
        while result.count < options.length {
            result.append(randomElement(pool))
        }
        shuffle(&result)
        return String(result)
    }

    /// The enabled character classes, in a fixed order. Never empty: with every
    /// class switched off the generator falls back to lowercase letters.
    static func characterClasses(_ options: PasswordOptions) -> [String] {
        var classes: [String] = []
        if options.lowercase { classes.append(options.avoidAmbiguous ? lower : lowerFull) }
        if options.uppercase { classes.append(options.avoidAmbiguous ? upper : upperFull) }
        if options.digits { classes.append(options.avoidAmbiguous ? digitsSafe : digitsFull) }
        if options.symbols { classes.append(symbols) }
        return classes.isEmpty ? [lowerFull] : classes
    }

    private static func randomElement(_ chars: [Character]) -> Character {
        chars[CryptoRandom.int(upperBound: chars.count)]
    }

    /// Fisher-Yates over `CryptoRandom`, so every random draw in this file goes
    /// through the same audited source.
    private static func shuffle(_ chars: inout [Character]) {
        guard chars.count > 1 else { return }
        for i in stride(from: chars.count - 1, to: 0, by: -1) {
            chars.swapAt(i, CryptoRandom.int(upperBound: i + 1))
        }
    }

    static func pin(_ options: PinOptions) -> String {
        guard options.length > 0 else { return "" }
        let chars = Array(digitsFull)
        let result = (0..<options.length).map { _ in chars[CryptoRandom.int(upperBound: chars.count)] }
        return String(result)
    }

    static func passphrase(_ options: PassphraseOptions) -> String {
        let words = DicewareWordList.words
        guard !words.isEmpty else { return "" }
        var picked = (0..<max(options.wordCount, 1)).map { _ -> String in
            let word = words[CryptoRandom.int(upperBound: words.count)]
            return options.capitalize ? word.prefix(1).uppercased() + word.dropFirst() : word
        }
        if options.includeNumber, !picked.isEmpty {
            let index = CryptoRandom.int(upperBound: picked.count)
            picked[index] += String(CryptoRandom.int(upperBound: 100))
        }
        return picked.joined(separator: options.separator)
    }
}
