import CryptoKit
import Foundation

/// Parses the Quick View QR "variant B" payload: a compact locator (the same
/// human code the Enter-Code flow accepts) plus a signed-session digest the
/// app recomputes AFTER resolving, so a scanned QR is bound to the EXACT
/// session envelope the server hands back — a mismatch means the app
/// resolved a DIFFERENT session than the one on screen (hard fail, no
/// bypass, same discipline as the SAS mismatch abort).
///
/// Format: `LOOX-QV-QR-V1:{humanCodeNoDash}:{b64url(sha256(session_id‖enc_key_hash‖sig_key_hash)[:8])}`
///
/// NOT one of the byte-for-byte BE-frozen artifacts — the authoritative
/// contract doc (`quick-view-contracts.md` "Open (pre-freeze) items") lists
/// QR payload density/format as still open ("does not change SESSION-V1
/// bytes" either way). This is the format handed off for this increment; a
/// scanned string that doesn't match the prefix is treated as a plain human
/// code (manual-entry fallback), never an error.
nonisolated enum QuickViewQRCode {
    static let prefix = "LOOX-QV-QR-V1:"

    struct Parsed: Equatable {
        let humanCode: String
        /// First 8 bytes of SHA-256(session_id‖enc_key_hash‖sig_key_hash),
        /// base64url (no padding).
        let digest: Data
    }

    /// `nil` if `raw` isn't this QR format — callers fall back to treating
    /// `raw` as a plain typed/scanned human code.
    static func parse(_ raw: String) -> Parsed? {
        guard raw.hasPrefix(prefix) else { return nil }
        let rest = raw.dropFirst(prefix.count)
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty,
              let digest = Data(base64URLEncoded: String(parts[1])), digest.count == 8
        else { return nil }
        return Parsed(humanCode: String(parts[0]), digest: digest)
    }

    /// Recompute the binding digest from a RESOLVED session's own material —
    /// must equal the scanned QR's `digest`.
    static func digest(sessionIDBytes: Data, encKeyHash: Data, sigKeyHash: Data) -> Data {
        let full = Data(SHA256.hash(data: sessionIDBytes + encKeyHash + sigKeyHash))
        return full.prefix(8)
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
