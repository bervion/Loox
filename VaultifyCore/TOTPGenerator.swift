import Foundation
import CryptoKit

/// RFC 6238 time-based one-time passwords. Accepts a raw base32 secret or an
/// `otpauth://` URI.
nonisolated enum TOTPGenerator {
    enum HashAlgorithm: String { case sha1, sha256, sha512 }

    struct Config: Sendable {
        var secret: Data
        var digits: Int = 6
        var period: Int = 30
        var algorithm: String = "sha1"
    }

    /// Current code for a base32 secret, or `nil` if the secret is invalid.
    static func code(secretBase32: String, digits: Int = 6, period: Int = 30,
                     algorithm: HashAlgorithm = .sha1, date: Date = .now) -> String? {
        guard let key = base32Decode(secretBase32), !key.isEmpty else { return nil }
        let counter = UInt64(max(date.timeIntervalSince1970, 0)) / UInt64(period)
        return code(key: key, counter: counter, digits: digits, algorithm: algorithm)
    }

    /// Current code for a stored value that may be a bare secret or an otpauth URI.
    static func code(forStoredValue value: String, date: Date = .now) -> String? {
        if value.lowercased().hasPrefix("otpauth://"), let cfg = parse(uri: value) {
            let algo = HashAlgorithm(rawValue: cfg.algorithm.lowercased()) ?? .sha1
            let counter = UInt64(max(date.timeIntervalSince1970, 0)) / UInt64(cfg.period)
            return code(key: cfg.secret, counter: counter, digits: cfg.digits, algorithm: algo)
        }
        return code(secretBase32: value, date: date)
    }

    static func secondsRemaining(period: Int = 30, date: Date = .now) -> Int {
        period - Int(date.timeIntervalSince1970.truncatingRemainder(dividingBy: Double(period)))
    }

    /// Period (seconds) for a stored value — the otpauth `period=` parameter
    /// when present, else the RFC 6238 default of 30. Countdown UIs must pair
    /// this with `secondsRemaining(period:date:)` so a custom-period code and
    /// its ring/expiry warning stay in step (a hardcoded 30 makes a 60s code
    /// look expired mid-validity).
    static func period(forStoredValue value: String) -> Int {
        if value.lowercased().hasPrefix("otpauth://"), let cfg = parse(uri: value) {
            return cfg.period
        }
        return 30
    }

    private static func code(key: Data, counter: UInt64, digits: Int, algorithm: HashAlgorithm) -> String {
        var bigEndianCounter = counter.bigEndian
        let message = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }
        let symmetricKey = SymmetricKey(data: key)
        let mac: [UInt8]
        switch algorithm {
        case .sha1: mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        case .sha256: mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case .sha512: mac = Array(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        }
        let offset = Int(mac[mac.count - 1] & 0x0F)
        let binary = (UInt32(mac[offset] & 0x7F) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        let modulus = UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", binary % modulus)
    }

    static func parse(uri: String) -> Config? {
        guard let components = URLComponents(string: uri),
              components.scheme?.lowercased() == "otpauth" else { return nil }
        let query = components.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        guard let secretBase32 = value("secret"), let secret = base32Decode(secretBase32) else { return nil }
        // Malformed query values degrade instead of trapping: period ≤ 0 would
        // divide by zero in the counter math (a scanned QR is untrusted input),
        // so it falls back to the RFC default; digits outside 1…9 would
        // overflow the UInt32 modulus — clamp (RFC codes are 6–8; 9 is the
        // UInt32-safe ceiling).
        let rawDigits = Int(value("digits") ?? "") ?? 6
        let rawPeriod = Int(value("period") ?? "") ?? 30
        return Config(secret: secret,
                      digits: min(max(rawDigits, 1), 9),
                      period: rawPeriod > 0 ? rawPeriod : 30,
                      algorithm: value("algorithm") ?? "sha1")
    }

    /// RFC 4648 base32 decode (uppercase A–Z, 2–7), ignoring spaces/padding.
    static func base32Decode(_ input: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let cleaned = input.uppercased().filter { $0 != "=" && !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        var lookup = [Character: Int]()
        for (i, c) in alphabet.enumerated() { lookup[c] = i }
        var bytes = [UInt8]()
        var buffer = 0
        var bits = 0
        for character in cleaned {
            guard let value = lookup[character] else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return Data(bytes)
    }
}
