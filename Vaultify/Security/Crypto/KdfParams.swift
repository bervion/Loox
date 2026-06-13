import Foundation

/// Argon2id cost parameters. Memory cost is expressed in KiB.
///
/// Defaults follow the OWASP 2023 password-storage guidance for Argon2id.
nonisolated struct KdfParams: Codable, Equatable, Sendable {
    /// Memory cost in KiB (e.g. 65536 == 64 MiB).
    var memoryCostKiB: UInt32
    /// Number of iterations (time cost).
    var timeCost: UInt32
    /// Degree of parallelism (lanes).
    var parallelism: UInt32

    /// OWASP 2023 baseline: 64 MiB, t=3, p=4.
    static let standard = KdfParams(memoryCostKiB: 64 * 1024, timeCost: 3, parallelism: 4)

    /// Lighter, still memory-hard profile for constrained devices: 32 MiB, t=4.
    static let constrained = KdfParams(memoryCostKiB: 32 * 1024, timeCost: 4, parallelism: 4)
}
