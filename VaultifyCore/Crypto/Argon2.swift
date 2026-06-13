import Foundation

/// Argon2id key derivation backed by the vendored phc-winner-argon2 reference C
/// (`Security/CArgon2`, portable `ref.c` build). Exposed to Swift via the
/// bridging header's `argon2id_hash_raw`.
nonisolated enum Argon2 {
    enum Failure: Error, LocalizedError {
        case hashFailed(code: Int32, message: String)
        var errorDescription: String? {
            switch self {
            case let .hashFailed(_, message): return "Argon2id failed: \(message)"
            }
        }
    }

    /// Derive `length` raw bytes from `password` + `salt`.
    ///
    /// CPU- and memory-heavy by design — always call from a background task,
    /// never the main actor.
    static func deriveRaw(password: [UInt8],
                          salt: [UInt8],
                          params: KdfParams,
                          length: Int = 32) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: length)
        let code: Int32 = output.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pwd in
                salt.withUnsafeBytes { slt in
                    argon2id_hash_raw(params.timeCost,
                                      params.memoryCostKiB,
                                      params.parallelism,
                                      pwd.baseAddress, pwd.count,
                                      slt.baseAddress, slt.count,
                                      out.baseAddress, out.count)
                }
            }
        }
        guard code == 0 else {
            throw Failure.hashFailed(code: code,
                                     message: String(cString: argon2_error_message(code)))
        }
        return output
    }

    static func deriveRaw(password: String,
                          salt: [UInt8],
                          params: KdfParams,
                          length: Int = 32) throws -> [UInt8] {
        try deriveRaw(password: Array(password.utf8), salt: salt, params: params, length: length)
    }

    #if DEBUG
    /// Known-answer test against the canonical Argon2id v1.3 vector
    /// (password="password", salt="somesalt", t=2, m=65536 KiB, p=1, len=32).
    static func selfTestPasses() -> Bool {
        let expected = "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7"
        let params = KdfParams(memoryCostKiB: 65536, timeCost: 2, parallelism: 1)
        guard let hash = try? deriveRaw(password: Array("password".utf8),
                                        salt: Array("somesalt".utf8),
                                        params: params) else { return false }
        return hash.map { String(format: "%02x", $0) }.joined() == expected
    }
    #endif
}
