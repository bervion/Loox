import Foundation

/// Shared display-string hygiene for the developer-asset inspectors. Every
/// string extracted from an untrusted asset (certificate subject, profile
/// name, plist field) must pass through here before it is shown or stored:
/// control characters and bidirectional overrides can otherwise spoof what
/// the user reads.
nonisolated enum Sanitize {
    static let maxDisplayLength = 512

    /// Strips C0/C1 control characters plus Unicode bidi overrides and
    /// isolates (U+202A–U+202E, U+2066–U+2069), then caps the length.
    static func displayString(_ raw: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x202A...0x202E, 0x2066...0x2069:
                continue
            default:
                kept.append(scalar)
            }
        }
        return String(String(kept).prefix(maxDisplayLength))
    }
}

/// PEM armor handling: locates a `-----BEGIN <label>-----` block and decodes
/// its base64 body. Pure text processing over caller-supplied input.
nonisolated enum PEMArmor {
    static func derBody(of text: String, label: String) -> Data? {
        let begin = "-----BEGIN \(label)-----"
        let end = "-----END \(label)-----"
        guard let beginRange = text.range(of: begin),
              let endRange = text.range(of: end, range: beginRange.upperBound..<text.endIndex)
        else { return nil }
        let body = text[beginRange.upperBound..<endRange.lowerBound]
        let base64 = body.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        return Data(base64Encoded: String(String.UnicodeScalarView(base64)))
    }
}
