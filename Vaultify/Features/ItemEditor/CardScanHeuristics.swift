import Foundation

/// Pure text heuristics run over VisionKit's per-line recognized text to find a card
/// number, expiry, and cardholder name on a physical card. No VisionKit/UIKit dependency —
/// kept separate from `CardScannerSheet` so the parsing logic itself stays plain and
/// unit-testable.
enum CardScanHeuristics {
    /// The longest 13-19-digit run (spaces/dashes between digits tolerated, since a
    /// printed PAN is usually grouped that way) that also passes the Luhn checksum,
    /// across every recognized line. Returns digits only.
    static func longestLuhnValidPAN(in lines: [String]) -> String? {
        lines
            .flatMap(digitRuns(in:))
            .filter { (13...19).contains($0.count) && PaymentCard.isLuhnValid($0) }
            .max { $0.count < $1.count }
    }

    /// First `MM/YY` or `MM/YYYY` (or `MM-YY`) match across every recognized line,
    /// normalized to `MM/YY` (a 4-digit year is truncated to its last 2 digits).
    static func expiry(in lines: [String]) -> String? {
        // 4-digit year alternative FIRST: `NSRegularExpression` alternation takes the first
        // branch that matches rather than the longest one, so `\d{2}` before `\d{4}` would
        // truncate "2028" down to just "20".
        let pattern = #"(0[1-9]|1[0-2])\s*[/-]\s*(\d{4}|\d{2})"#
        for line in lines {
            guard let range = line.range(of: pattern, options: .regularExpression) else { continue }
            let raw = line[range].replacingOccurrences(of: " ", with: "")
            let parts = raw.split(whereSeparator: { $0 == "/" || $0 == "-" })
            guard parts.count == 2 else { continue }
            return "\(parts[0])/\(parts[1].suffix(2))"
        }
        return nil
    }

    /// First line that reads as a cardholder name: 2+ words, letters and spaces only, all
    /// uppercase (matching embossed card lettering), and not one of the common bank/network
    /// keywords printed elsewhere on a card.
    static func cardholderName(in lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let words = trimmed.split(separator: " ")
            guard words.count >= 2,
                  trimmed.allSatisfy({ $0.isLetter || $0 == " " }),
                  trimmed == trimmed.uppercased(),
                  !words.contains(where: { bankKeywords.contains(String($0)) })
            else { continue }
            return trimmed
        }
        return nil
    }

    /// Common printed-on-card words that look like a name (all-caps, 2+ words) but aren't
    /// one — excluded so they're never mistaken for the cardholder.
    private static let bankKeywords: Set<String> = [
        "VALID", "THRU", "FROM", "GOOD", "DEBIT", "CREDIT", "BANK", "VISA", "MASTERCARD",
        "EXPIRES", "MEMBER", "SINCE", "PLATINUM", "GOLD", "CLASSIC", "SIGNATURE", "WORLD",
    ]

    /// Digit runs within a single line — a run continues across interior spaces/dashes but
    /// stops at any other character, so unrelated digits (e.g. an expiry date on the same
    /// line) don't merge into a PAN candidate.
    private static func digitRuns(in line: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for char in line {
            if char.isNumber {
                current.append(char)
            } else if char == " " || char == "-" {
                continue // tolerated separator inside a run
            } else {
                if !current.isEmpty { runs.append(current) }
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
