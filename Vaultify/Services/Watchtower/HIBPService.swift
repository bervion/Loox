import Foundation
import CryptoKit

/// Have I Been Pwned "Pwned Passwords" range API using k-anonymity: only the
/// first 5 hex chars of the SHA-1 are sent; the full hash never leaves the device.
nonisolated enum HIBPService {
    /// Returns how many times the password appears in known breaches (0 = none).
    static func pwnedCount(password: String) async -> Int {
        let digest = Insecure.SHA1.hash(data: Data(password.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let prefix = String(hex.prefix(5))
        let suffix = String(hex.dropFirst(5))

        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else { return 0 }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.addValue("true", forHTTPHeaderField: "Add-Padding")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return 0 }

        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 2, parts[0].uppercased() == suffix else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        }
        return 0
    }
}
