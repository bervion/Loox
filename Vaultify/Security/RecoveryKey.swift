import Foundation

/// Generates and normalises the Emergency Kit recovery key — a high-entropy,
/// human-transcribable code (Crockford base32, grouped) used as an independent
/// unlock path that wraps the same Vault Key.
nonisolated enum RecoveryKey {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a grouped recovery key (default 160 bits → e.g. `A1B2-C3D4-…`).
    static func generate(byteCount: Int = 20, groupSize: Int = 4) -> String {
        let encoded = base32(CryptoRandom.bytes(byteCount))
        let chars = Array(encoded)
        return stride(from: 0, to: chars.count, by: groupSize)
            .map { String(chars[$0..<min($0 + groupSize, chars.count)]) }
            .joined(separator: "-")
    }

    /// Strip separators/whitespace, upper-case, and map Crockford confusables
    /// (I/L→1, O→0) for comparison/derivation. Mapping instead of dropping:
    /// someone reading `1` off the printed kit as `I` typed the RIGHT character
    /// by Crockford's own rules — silently deleting it would shift every later
    /// character and reject a correctly transcribed key.
    static func normalize(_ input: String) -> String {
        String(input.uppercased().map { char -> Character in
            switch char {
            case "I", "L": "1"
            case "O": "0"
            default: char
            }
        }.filter { alphabet.contains($0) })
    }

    private static func base32(_ data: [UInt8]) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 0x1F])
                bits -= 5
            }
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 0x1F]) }
        return output
    }
}
