import Foundation

/// Pattern-aware strength estimator (zxcvbn-style, lite). Finds cheap attack
/// segments (dictionary words, sequences, repeats, keyboard walks, dates,
/// personal context), then takes the CHEAPEST full cover of the password via
/// dynamic programming — composition rules never inflate the score, so
/// "Password1!" grades by its parts, not its character classes.
nonisolated enum PasswordStrengthEngine {

    // Grade thresholds on log10(guesses). Calibrated by the KAT test table.
    private static let thresholds: [(PasswordGrade, Double)] = [
        (.veryWeak, 6), (.weak, 8), (.fair, 10), (.strong, 12.5),
    ]

    static func evaluate(_ password: String, context: StrengthContext = .empty) -> StrengthResult {
        let chars = Array(password)
        guard !chars.isEmpty else {
            return StrengthResult(grade: .veryWeak, log10Guesses: 0, matchedPatterns: [])
        }

        let lower = Array(password.lowercased())
        var matches: [StrengthMatch] = []
        matches += DictionaryMatcher.matches(lower: lower, contextTerms: context.terms)
        matches += PatternMatchers.sequences(lower)
        matches += PatternMatchers.repeats(lower)
        matches += PatternMatchers.keyboardWalks(lower)
        matches += PatternMatchers.dates(lower)

        let (total, labels) = cheapestCover(count: chars.count,
                                            perCharBrute: bruteLog10PerChar(chars),
                                            matches: matches)

        var grade: PasswordGrade = .excellent
        for (candidate, limit) in thresholds where total < limit {
            grade = candidate
            break
        }
        // A password echoing vault-known context (username, email, site, title)
        // is guessable by anyone targeting this account: cap at weak.
        if labels.contains("context"), grade > .weak { grade = .weak }

        return StrengthResult(grade: grade, log10Guesses: total, matchedPatterns: labels)
    }

    /// Brute-force cost per character from the character classes present —
    /// the filler cost for stretches no pattern explains.
    private static func bruteLog10PerChar(_ chars: [Character]) -> Double {
        var pool = 0
        if chars.contains(where: \.isLowercase) { pool += 26 }
        if chars.contains(where: \.isUppercase) { pool += 26 }
        if chars.contains(where: \.isNumber) { pool += 10 }
        if chars.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) { pool += 33 }
        if chars.contains(where: \.isWhitespace) { pool += 1 }
        return log10(Double(max(pool, 10)))
    }

    /// DP over prefix length: cost[i] = cheapest log10(guesses) covering chars[0..<i].
    /// Each matched segment adds a small ordering overhead (log10 2) so a long
    /// passphrase of several words is not billed as one giant lucky guess.
    private static func cheapestCover(count: Int,
                                      perCharBrute: Double,
                                      matches: [StrengthMatch]) -> (Double, [String]) {
        var matchesByEnd: [[StrengthMatch]] = Array(repeating: [], count: count)
        for m in matches where m.end < count { matchesByEnd[m.end].append(m) }

        let segmentOverhead = log10(2.0)
        var cost = [Double](repeating: .infinity, count: count + 1)
        var back = [StrengthMatch?](repeating: nil, count: count + 1)
        cost[0] = 0

        for i in 1...count {
            cost[i] = cost[i - 1] + perCharBrute
            back[i] = nil
            for m in matchesByEnd[i - 1] {
                let candidate = cost[m.start] + m.log10Guesses + segmentOverhead
                if candidate < cost[i] {
                    cost[i] = candidate
                    back[i] = m
                }
            }
        }

        var labels: [String] = []
        var i = count
        while i > 0 {
            if let m = back[i] { labels.append(m.label); i = m.start } else { i -= 1 }
        }
        return (cost[count], labels.reversed())
    }
}
