import Foundation

/// Recognized card network, detected from the PAN's leading digits (BIN ranges). Text-badge
/// identification only — no logo assets ship for third-party network marks (trademark).
nonisolated enum CardBrand: String, CaseIterable, Sendable {
    case visa, mastercard, amex, jcb, discover, unionPay

    /// Short caps label for the TEXT badge shown next to a recognized card number.
    var displayName: String {
        switch self {
        case .visa: return "VISA"
        case .mastercard: return "MASTERCARD"
        case .amex: return "AMEX"
        case .jcb: return "JCB"
        case .discover: return "DISCOVER"
        case .unionPay: return "UNIONPAY"
        }
    }

    /// Shortest valid PAN length for this network — used to decide when a typed/scanned
    /// number is "complete enough" to run the Luhn check against (a partial number should
    /// never flash a validation warning).
    var minDigits: Int {
        self == .amex ? 15 : 16
    }

    /// Longest PAN length this app will accept for this network (hard input cap).
    var maxDigits: Int {
        self == .amex ? 15 : 19
    }

    /// Security-code (CVV/CID) length for this network.
    var cvvLength: Int {
        self == .amex ? 4 : 3
    }
}

/// Pure card-number utilities: BIN-based brand detection, Luhn checksum, digit
/// normalization, and display grouping. Foundation-only and `nonisolated` — this file
/// compiles into the AutoFill extension target too (via `VaultifyCore/**`), so it must
/// never import SwiftUI/VisionKit or anything UIKit-adjacent.
nonisolated enum PaymentCard {
    /// Strips everything but digits — tolerant of spaces/dashes from typing or scanning.
    static func digitsOnly(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// Detects the card network from a PAN's leading digits. Returns `nil` when no known
    /// BIN range matches (an unrecognized or foreign network — not an error, just no badge).
    static func brand(for rawNumber: String) -> CardBrand? {
        let digits = digitsOnly(rawNumber)
        guard !digits.isEmpty else { return nil }

        if digits.hasPrefix("4") { return .visa }
        if let p2 = prefixInt(digits, 2), p2 == 34 || p2 == 37 { return .amex }
        if let p2 = prefixInt(digits, 2), (51...55).contains(p2) { return .mastercard }
        if let p4 = prefixInt(digits, 4), (2221...2720).contains(p4) { return .mastercard }
        if let p4 = prefixInt(digits, 4), (3528...3589).contains(p4) { return .jcb }
        if digits.hasPrefix("6011") { return .discover }
        if let p2 = prefixInt(digits, 2), p2 == 65 { return .discover }
        if let p3 = prefixInt(digits, 3), (644...649).contains(p3) { return .discover }
        if let p2 = prefixInt(digits, 2), p2 == 62 { return .unionPay }
        return nil
    }

    /// Standard mod-10 (Luhn) checksum. Fewer than 2 digits is never "valid" — there's
    /// nothing to check yet, and this must not read as a false positive on an empty field.
    static func isLuhnValid(_ rawNumber: String) -> Bool {
        let digits = digitsOnly(rawNumber)
        guard digits.count >= 2 else { return false }
        var sum = 0
        var doubleNext = false
        for char in digits.reversed() {
            guard let value = char.wholeNumberValue else { return false }
            var v = value
            if doubleNext {
                v *= 2
                if v > 9 { v -= 9 }
            }
            sum += v
            doubleNext.toggle()
        }
        return sum % 10 == 0
    }

    /// Grouped, spaced representation for READ-ONLY display (item detail) — always groups
    /// the full stored value with no length cap (a legacy or foreign PAN longer than any
    /// known brand's cap still displays grouped-by-4, never truncated).
    static func formattedForDisplay(_ rawNumber: String) -> String {
        let digits = digitsOnly(rawNumber)
        return group(digits, brand: brand(for: digits))
    }

    /// Grouped, spaced, LENGTH-CAPPED representation for as-you-type editing — caps to the
    /// resolved brand's max digits (or 19 when unresolved) so typing can't run away past any
    /// real PAN length.
    static func formattedForInput(_ rawNumber: String) -> String {
        let resolvedBrand = brand(for: rawNumber)
        let cap = resolvedBrand?.maxDigits ?? 19
        let digits = String(digitsOnly(rawNumber).prefix(cap))
        return group(digits, brand: resolvedBrand)
    }

    /// Caps raw typed/pasted input to the resolved brand's max digits (or 19 when
    /// unresolved) and strips non-digits — the value actually persisted to storage.
    static func normalizedForStorage(_ rawNumber: String) -> String {
        let cap = brand(for: rawNumber)?.maxDigits ?? 19
        return String(digitsOnly(rawNumber).prefix(cap))
    }

    // MARK: - Grouping

    /// Amex groups 4-6-5; every other network (known or not) groups in 4s, which also
    /// degrades gracefully for a longer-than-typical or unrecognized PAN (the trailing
    /// group simply holds the remainder instead of the grouping breaking).
    private static func group(_ digits: String, brand: CardBrand?) -> String {
        guard !digits.isEmpty else { return "" }
        let sizes: [Int] = brand == .amex ? [4, 6, 5] : []
        guard !sizes.isEmpty else {
            // Group in 4s: chunk every 4 characters, last chunk holds the remainder.
            return stride(from: 0, to: digits.count, by: 4).map { start in
                let startIndex = digits.index(digits.startIndex, offsetBy: start)
                let endIndex = digits.index(startIndex, offsetBy: min(4, digits.count - start))
                return String(digits[startIndex..<endIndex])
            }.joined(separator: " ")
        }
        var result: [String] = []
        var remaining = Substring(digits)
        for size in sizes {
            guard !remaining.isEmpty else { break }
            let chunk = remaining.prefix(size)
            result.append(String(chunk))
            remaining = remaining.dropFirst(chunk.count)
        }
        if !remaining.isEmpty { result.append(String(remaining)) }
        return result.joined(separator: " ")
    }

    private static func prefixInt(_ digits: String, _ length: Int) -> Int? {
        guard digits.count >= length else { return nil }
        return Int(digits.prefix(length))
    }
}

/// Pure MM/YY auto-formatting for the card Expiry field (Stripe/Wallet-style typing):
/// digits-only input auto-inserts the slash once the month is complete and clamps the
/// month to 01-12. Extracted from `ExpiryFieldEditor` so the formatting itself is a plain,
/// unit-testable function with no SwiftUI dependency.
nonisolated enum CardExpiryFormat {
    /// Formats raw typed digits into "MM/YY", inserting the slash as soon as 2 digits are
    /// present and clamping the month once both its digits are known. Caps at 4 digits
    /// (2-digit month + 2-digit year) — 5 characters once the slash is included.
    /// Deletion-aware variant for as-you-type editing. The plain `autoFormat` re-inserts
    /// the slash immediately, so backspacing "12/" → "12" would bounce right back to
    /// "12/" and the user could never delete past it. When the edit is exactly "the
    /// slash was deleted", drop the month's trailing digit too ("12/" → "1").
    static func autoFormat(_ input: String, previous: String) -> String {
        if input.count < previous.count,
           previous.hasSuffix("/"),
           input == String(previous.dropLast()) {
            return autoFormat(String(input.dropLast()))
        }
        return autoFormat(input)
    }

    static func autoFormat(_ input: String) -> String {
        var digits = String(input.filter(\.isNumber).prefix(4))
        guard !digits.isEmpty else { return "" }

        if digits.count >= 2 {
            let monthValue = Int(digits.prefix(2)) ?? 0
            digits = clampedMonth(monthValue) + digits.dropFirst(2)
        }

        guard digits.count > 2 else {
            // Slash appears the moment the month's 2 digits are in, before any year digit.
            return digits.count == 2 ? "\(digits)/" : digits
        }
        let month = digits.prefix(2)
        let year = digits.dropFirst(2)
        return "\(month)/\(year)"
    }

    /// Whether `text` matches one of the common pre-existing freeform expiry shapes this
    /// app has ever stored (MM/YY, MM/YYYY, MM-YY) — used to decide whether an existing
    /// value round-trips through the new formatted editor or stays a plain text field.
    static func matchesKnownPattern(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let pattern = #"^(0[1-9]|1[0-2])[/-]\d{2}(\d{2})?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private static func clampedMonth(_ value: Int) -> String {
        let clamped = max(1, min(value, 12))
        return String(format: "%02d", clamped)
    }
}
