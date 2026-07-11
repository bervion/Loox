import Foundation

/// Finds substrings that are common passwords, common words/names, or terms the
/// vault already knows about this account (username, email, site, title).
/// L33t substitutions are normalized before lookup so "P@ssw0rd" matches
/// "password".
nonisolated enum DictionaryMatcher {

    /// Conservative single-target l33t map (zxcvbn's most common substitutions).
    private static let l33t: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
        "7": "t", "8": "b", "@": "a", "$": "s", "!": "i", "+": "t",
    ]

    static func matches(lower: [Character], contextTerms: [String]) -> [StrengthMatch] {
        let n = lower.count
        guard n >= 3 else { return [] }
        let normalized = lower.map { l33t[$0] ?? $0 }
        let contextSet = Set(contextTerms)

        var out: [StrengthMatch] = []
        for start in 0..<n {
            let maxEnd = min(n - 1, start + 29)
            guard start + 2 <= maxEnd else { continue }
            for end in (start + 2)...maxEnd {
                let raw = String(lower[start...end])
                let norm = String(normalized[start...end])
                // ×4 when the match needed l33t decoding (substitution choices).
                let l33tPenalty = raw == norm ? 0.0 : log10(4.0)

                // Personal context: an attacker targeting this account tries
                // these first — near-free guesses.
                if contextSet.contains(raw) || contextSet.contains(norm) {
                    out.append(StrengthMatch(start: start, end: end,
                                             log10Guesses: log10(2.0), label: "context"))
                    continue
                }
                if let rank = CommonPasswords.rank[norm] {
                    out.append(StrengthMatch(start: start, end: end,
                                             log10Guesses: log10(Double(rank)) + l33tPenalty,
                                             label: "common-password"))
                } else if let rank = CommonWords.rank[norm] {
                    // Words sit behind the password list in real cracking order.
                    out.append(StrengthMatch(start: start, end: end,
                                             log10Guesses: log10(Double(rank) + 1000) + l33tPenalty,
                                             label: "dictionary"))
                }
            }
        }
        return out
    }
}
