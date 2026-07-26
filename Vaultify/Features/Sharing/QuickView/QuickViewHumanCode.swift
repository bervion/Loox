import Foundation

/// Client-side format + checksum pre-check for the Quick View human code —
/// mirrors the backend generator `loox-quick-view/src/human-code.ts` EXACTLY
/// (Crockford base32 with `0 O 1 I L U` removed = 30 symbols; 7 random data
/// chars + 1 Luhn-mod-N checksum char; displayed `XXXX-XXXX`). This is a
/// courtesy check ONLY — it catches fat-finger typos before a network round
/// trip; the server remains the authoritative validator (a code that passes
/// here can still be unknown/expired/claimed → the same generic error).
///
/// The alphabet + checksum are NOT a byte-frozen artifact, but they MUST match
/// the server or every real code is rejected locally before `resolve`. Kept in
/// lockstep with `human-code.ts`: alphabet string, Luhn-mod-N, and the
/// non-alphanumeric-stripping normalize.
nonisolated enum QuickViewHumanCode {
    /// 2–9 + A–Z minus `I L O U` — 30 symbols. MUST equal
    /// `HUMAN_CODE_ALPHABET` in `human-code.ts` (note: no `U`).
    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let dataLength = 7
    static let length = 8   // 7 data + 1 checksum

    /// Strip every non-alphanumeric char and uppercase (matches BE `parse`'s
    /// `replace(/[^A-Z0-9]/g, '')` after `toUpperCase()`).
    static func normalize(_ raw: String) -> String {
        String(raw.uppercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        })
    }

    /// `XXXX-XXXX` display form; returns the cleaned input unchanged until it
    /// reaches full length so partial typing doesn't make the dash jump.
    static func formatted(_ raw: String) -> String {
        let cleaned = normalize(raw)
        guard cleaned.count == length else { return cleaned }
        let mid = cleaned.index(cleaned.startIndex, offsetBy: 4)
        return "\(cleaned[..<mid])-\(cleaned[mid...])"
    }

    /// Display form for a field being typed into: uppercased, non-alphanumerics
    /// dropped, capped at `length`, and the dash placed as soon as a fifth
    /// symbol exists.
    ///
    /// `formatted` deliberately withholds the dash until the code is complete,
    /// which reads as "nothing is happening" for seven of the eight keystrokes
    /// and leaves the field looking nothing like the `XXXX-XXXX` printed on the
    /// computer — the user cannot tell a half-typed code from a wrong one. The
    /// cap matters too: `normalize` has no length limit, so a ninth character
    /// used to be accepted silently and only surfaced as a validation failure
    /// after Continue.
    static func liveFormatted(_ raw: String) -> String {
        let cleaned = String(normalize(raw).prefix(length))
        guard cleaned.count > 4 else { return cleaned }
        let mid = cleaned.index(cleaned.startIndex, offsetBy: 4)
        return "\(cleaned[..<mid])-\(cleaned[mid...])"
    }

    /// Charset + length + Luhn-mod-N checksum validity of a code (any dash/case).
    static func isValid(_ raw: String) -> Bool {
        let cleaned = Array(normalize(raw))
        guard cleaned.count == length else { return false }
        let indices = cleaned.prefix(dataLength).map { alphabet.firstIndex(of: $0) ?? -1 }
        guard !indices.contains(-1),
              let checkIdx = alphabet.firstIndex(of: cleaned[dataLength]) else { return false }
        return luhnModNCheckIndex(Array(indices)) == checkIdx
    }

    /// Luhn mod N over alphabet indices — identical to `luhnModNCheckIndex` in
    /// `human-code.ts` (right-to-left, alternating factor 2/1, digit-fold by n).
    private static func luhnModNCheckIndex(_ indices: [Int]) -> Int {
        let n = alphabet.count
        var factor = 2
        var sum = 0
        for i in stride(from: indices.count - 1, through: 0, by: -1) {
            var addend = factor * indices[i]
            addend = (addend / n) + (addend % n)
            sum += addend
            factor = factor == 2 ? 1 : 2
        }
        return (n - (sum % n)) % n
    }

    /// Appends a valid checksum char to exactly `dataLength` data characters —
    /// a test/QA convenience (production codes are always server-minted).
    /// `nil` if `dataChars` isn't the right length/charset.
    static func appendingChecksum(to dataChars: String) -> String? {
        let chars = Array(dataChars)
        guard chars.count == dataLength else { return nil }
        let indices = chars.map { alphabet.firstIndex(of: $0) ?? -1 }
        guard !indices.contains(-1) else { return nil }
        return dataChars + String(alphabet[luhnModNCheckIndex(indices)])
    }
}
