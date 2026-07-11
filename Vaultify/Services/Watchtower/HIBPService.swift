import Foundation
import CryptoKit

/// Have I Been Pwned "Pwned Passwords" range API using k-anonymity: only the
/// first 5 hex chars of the SHA-1 are sent; the full hash never leaves the device.
nonisolated enum HIBPService {
    /// Returns how many times the password appears in known breaches (0 = none).
    /// Single-password convenience over `PwnedPasswordChecker.range` — batch
    /// callers (the audit) go through `PwnedPasswordChecker` for dedupe,
    /// prefix grouping, and the device-local cache.
    static func pwnedCount(password: String) async -> Int {
        let hex = PwnedPasswordChecker.sha1Hex(password)
        guard let ranges = try? await PwnedPasswordChecker.range(prefix: String(hex.prefix(5)),
                                                                 session: .shared) else { return 0 }
        return ranges[String(hex.dropFirst(5))] ?? 0
    }
}
