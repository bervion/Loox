import Foundation

/// Minimal bounded DER TLV reader: definite lengths only, single-byte tags,
/// hard element and depth budgets so hostile input cannot make parsing
/// unbounded. Enough to locate an AlgorithmIdentifier or an X.509 Validity
/// sequence — deliberately not a general ASN.1 parser.
nonisolated final class BoundedDERScanner {
    struct Element {
        let tag: UInt8
        let contentRange: Range<Int>
        var isConstructed: Bool { tag & 0x20 != 0 }
    }

    private let bytes: [UInt8]
    private let maxDepth: Int
    private var elementBudget: Int

    init?(der: Data, maxBytes: Int, maxDepth: Int, maxElements: Int) {
        guard !der.isEmpty, der.count <= maxBytes else { return nil }
        bytes = [UInt8](der)
        self.maxDepth = maxDepth
        elementBudget = maxElements
    }

    /// The single top-level element (a certificate or key is one SEQUENCE).
    func topLevel() -> Element? {
        parse(at: 0, end: bytes.count, depth: 0)?.element
    }

    /// Direct children of a constructed element. `depth` is the PARENT's
    /// nesting depth; children live at `depth + 1`.
    func children(of element: Element, depth: Int) -> [Element]? {
        guard element.isConstructed, depth < maxDepth else { return nil }
        var offset = element.contentRange.lowerBound
        let end = element.contentRange.upperBound
        var out: [Element] = []
        while offset < end {
            guard let (child, next) = parse(at: offset, end: end, depth: depth + 1) else { return nil }
            out.append(child)
            offset = next
        }
        return out
    }

    func content(of element: Element) -> [UInt8] {
        Array(bytes[element.contentRange])
    }

    private func parse(at offset: Int, end: Int, depth: Int) -> (element: Element, next: Int)? {
        guard depth <= maxDepth, elementBudget > 0 else { return nil }
        elementBudget -= 1
        var i = offset
        guard i < end else { return nil }
        let tag = bytes[i]
        // High-tag-number form never appears in the structures we read.
        guard tag & 0x1F != 0x1F else { return nil }
        i += 1
        guard i < end else { return nil }
        let first = bytes[i]
        i += 1
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            // Long form; count 0 would be BER indefinite length — not DER.
            let count = Int(first & 0x7F)
            guard count >= 1, count <= 4 else { return nil }
            for _ in 0..<count {
                guard i < end else { return nil }
                length = (length << 8) | Int(bytes[i])
                i += 1
            }
        }
        guard i + length <= end else { return nil }
        return (Element(tag: tag, contentRange: i..<(i + length)), i + length)
    }
}

nonisolated enum DEREncoding {
    /// Decodes OBJECT IDENTIFIER content bytes to dotted-decimal form.
    static func oidString(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        var subidentifiers: [UInt64] = []
        var value: UInt64 = 0
        var pending = false
        for byte in bytes {
            guard value <= (UInt64.max >> 7) else { return nil }
            value = (value << 7) | UInt64(byte & 0x7F)
            pending = true
            if byte & 0x80 == 0 {
                subidentifiers.append(value)
                value = 0
                pending = false
            }
        }
        guard !pending, let first = subidentifiers.first else { return nil }
        var components: [UInt64]
        if first < 40 {
            components = [0, first]
        } else if first < 80 {
            components = [1, first - 40]
        } else {
            components = [2, first - 80]
        }
        components.append(contentsOf: subidentifiers.dropFirst())
        return components.map(String.init).joined(separator: ".")
    }

    private static let utcTimeTag: UInt8 = 0x17
    private static let generalizedTimeTag: UInt8 = 0x18

    /// Parses a DER UTCTime ("YYMMDDHHMMSSZ") or GeneralizedTime
    /// ("YYYYMMDDHHMMSSZ") element into a UTC date. DER requires the seconds
    /// field and the trailing Z, so anything else is rejected.
    static func date(tag: UInt8, content: [UInt8]) -> Date? {
        guard let raw = String(bytes: content, encoding: .ascii), raw.hasSuffix("Z") else { return nil }
        let digits = Array(raw.dropLast().utf8)
        let zero = UInt8(ascii: "0")
        let nine = UInt8(ascii: "9")
        guard digits.allSatisfy({ $0 >= zero && $0 <= nine }) else { return nil }
        func value(_ range: Range<Int>) -> Int {
            digits[range].reduce(0) { $0 * 10 + Int($1 - zero) }
        }
        var components = DateComponents()
        let cursor: Int
        switch (tag, digits.count) {
        case (utcTimeTag, 12):
            let shortYear = value(0..<2)
            components.year = shortYear >= 50 ? 1900 + shortYear : 2000 + shortYear
            cursor = 2
        case (generalizedTimeTag, 14):
            components.year = value(0..<4)
            cursor = 4
        default:
            return nil
        }
        components.month = value(cursor..<(cursor + 2))
        components.day = value((cursor + 2)..<(cursor + 4))
        components.hour = value((cursor + 4)..<(cursor + 6))
        components.minute = value((cursor + 6)..<(cursor + 8))
        components.second = value((cursor + 8)..<(cursor + 10))
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        calendar.timeZone = utc
        return calendar.date(from: components)
    }
}
