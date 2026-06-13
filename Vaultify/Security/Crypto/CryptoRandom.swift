import Foundation
import Security

/// Cryptographically secure random bytes from the system CSPRNG.
nonisolated enum CryptoRandom {
    static func bytes(_ count: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        let status = buffer.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return buffer
    }

    static func data(_ count: Int) -> Data { Data(bytes(count)) }

    /// Unbiased integer in `0..<upperBound` via rejection sampling.
    static func int(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let limit = UInt64.max - (UInt64.max % UInt64(upperBound))
        while true {
            let raw = bytes(8).withUnsafeBytes { $0.load(as: UInt64.self) }
            if raw < limit { return Int(raw % UInt64(upperBound)) }
        }
    }
}
