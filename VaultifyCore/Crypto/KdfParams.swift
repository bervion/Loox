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

    /// OWASP 2023 baseline: 64 MiB, t=3, p=4. Used for envelopes that are only
    /// ever opened inside the full app (backups, Level-2, Secret Guard custom
    /// passphrases) where the process has the whole app memory budget.
    static let standard = KdfParams(memoryCostKiB: 64 * 1024, timeCost: 3, parallelism: 4)

    /// Vault key-bundle password-wrap profile: 32 MiB, t=4, p=4. The AutoFill
    /// extension runs this exact derivation on its master-password fallback path
    /// (no Face ID / biometrics invalidated), and app extensions live under a
    /// tight jetsam memory budget where a 64 MiB Argon2 pass risks termination.
    /// 32 MiB stays well above the OWASP 2023 Argon2id memory floor (19 MiB);
    /// the extra iteration recovers part of the halved memory work factor.
    /// Argon2 memory is `m_cost` total — lanes divide it, they don't multiply.
    static let constrained = KdfParams(memoryCostKiB: 32 * 1024, timeCost: 4, parallelism: 4)
}
