import Foundation

/// Structural pattern matchers: sequences, repeats, keyboard walks, dates/years.
/// All operate on the lowercased character array and return candidate segments;
/// the engine's DP decides which ones actually explain the password.
nonisolated enum PatternMatchers {

    // MARK: - Sequences (abcde, 12345, 9876)

    static func sequences(_ chars: [Character]) -> [StrengthMatch] {
        var out: [StrengthMatch] = []
        var start = 0
        while start < chars.count - 2 {
            guard let dir = step(chars[start], chars[start + 1]), abs(dir) == 1 else {
                start += 1
                continue
            }
            var end = start + 1
            while end + 1 < chars.count, step(chars[end], chars[end + 1]) == dir { end += 1 }
            let length = end - start + 1
            if length >= 3 {
                // start point (~36 alphanumerics) × direction × length.
                out.append(StrengthMatch(start: start, end: end,
                                         log10Guesses: log10(36.0 * 2 * Double(length)),
                                         label: "sequence"))
            }
            start = end
        }
        return out
    }

    private static func step(_ a: Character, _ b: Character) -> Int? {
        guard let x = a.unicodeScalars.first?.value, let y = b.unicodeScalars.first?.value,
              a.isLetter || a.isNumber, b.isLetter || b.isNumber else { return nil }
        return Int(y) - Int(x)
    }

    // MARK: - Repeats (aaa, abcabcabc)

    static func repeats(_ chars: [Character]) -> [StrengthMatch] {
        let n = chars.count
        var out: [StrengthMatch] = []
        for start in 0..<n {
            let maxEnd = min(n - 1, start + 39)
            guard start + 2 <= maxEnd else { continue }
            for end in (start + 2)...maxEnd {
                let length = end - start + 1
                guard let period = minimalPeriod(chars, start: start, length: length),
                      period < length else { continue }
                let repeats = Double(length) / Double(period)
                // Cost of guessing the block once, times the repeat count.
                let blockCost = Double(period) * log10(26.0)
                out.append(StrengthMatch(start: start, end: end,
                                         log10Guesses: min(blockCost, 3) + log10(repeats + 1),
                                         label: "repeat"))
            }
        }
        return out
    }

    /// Smallest p where chars[i] == chars[i+p] throughout, if the range is periodic.
    private static func minimalPeriod(_ chars: [Character], start: Int, length: Int) -> Int? {
        for p in 1...(length / 2) where length % p == 0 {
            var ok = true
            for i in start..<(start + length - p) where chars[i] != chars[i + p] {
                ok = false
                break
            }
            if ok { return p }
        }
        return nil
    }

    // MARK: - Keyboard walks (qwerty, asdfgh)

    private static let keyboardRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890"]

    static func keyboardWalks(_ chars: [Character]) -> [StrengthMatch] {
        let n = chars.count
        var out: [StrengthMatch] = []
        for row in keyboardRows {
            let rowChars = Array(row)
            var start = 0
            while start < n - 2 {
                guard let dir = rowStep(rowChars, chars, start), abs(dir) == 1 else {
                    start += 1
                    continue
                }
                var end = start + 1
                while end + 1 < n, rowStep(rowChars, chars, end) == dir { end += 1 }
                let length = end - start + 1
                if length >= 3 {
                    // start key (~30) × direction × length.
                    out.append(StrengthMatch(start: start, end: end,
                                             log10Guesses: log10(30.0 * 2 * Double(length)),
                                             label: "keyboard"))
                }
                start = end
            }
        }
        return out
    }

    private static func rowStep(_ row: [Character], _ chars: [Character], _ i: Int) -> Int? {
        guard let a = row.firstIndex(of: chars[i]), let b = row.firstIndex(of: chars[i + 1]) else {
            return nil
        }
        return b - a
    }

    // MARK: - Dates and years (1994, 20121994)

    static func dates(_ chars: [Character]) -> [StrengthMatch] {
        let n = chars.count
        var out: [StrengthMatch] = []
        var start = 0
        while start < n {
            guard chars[start].isNumber else { start += 1; continue }
            var end = start
            while end + 1 < n, chars[end + 1].isNumber { end += 1 }
            let run = end - start + 1
            if run == 4, let year = Int(String(chars[start...end])), (1900...2035).contains(year) {
                out.append(StrengthMatch(start: start, end: end,
                                         log10Guesses: log10(136.0), label: "year"))
            } else if run == 6 || run == 8 {
                // Plausible ddmmyy / ddmmyyyy style — ~366 days × ~120 years.
                out.append(StrengthMatch(start: start, end: end,
                                         log10Guesses: log10(366.0 * 120), label: "date"))
            }
            start = end + 1
        }
        return out
    }
}
