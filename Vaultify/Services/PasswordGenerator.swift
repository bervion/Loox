import Foundation

/// Loads the bundled EFF large diceware wordlist (7776 words ≈ 12.9 bits/word).
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

/// Cryptographically secure password and passphrase generation.
nonisolated enum PasswordGenerator {
    private static let lower = "abcdefghijkmnpqrstuvwxyz"
    private static let lowerFull = "abcdefghijklmnopqrstuvwxyz"
    private static let upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    private static let upperFull = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digitsSafe = "23456789"
    private static let digitsFull = "0123456789"
    private static let symbols = "!@#$%^&*()-_=+[]{};:,.?"

    static func generate(_ options: PasswordOptions) -> String {
        var pool = ""
        if options.lowercase { pool += options.avoidAmbiguous ? lower : lowerFull }
        if options.uppercase { pool += options.avoidAmbiguous ? upper : upperFull }
        if options.digits { pool += options.avoidAmbiguous ? digitsSafe : digitsFull }
        if options.symbols { pool += symbols }
        let chars = Array(pool.isEmpty ? lowerFull : pool)
        guard options.length > 0 else { return "" }
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
