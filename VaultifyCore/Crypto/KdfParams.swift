import Foundation

/// Argon2id cost parameters. Memory cost is expressed in KiB.
///
/// Defaults follow the OWASP 2023 password-storage guidance for Argon2id.
///
/// These values are also read from FILES the app did not write — an imported
/// backup envelope, the Level-2 wrap that travels inside it, a per-field
/// custom-code payload — and they are fed straight to Argon2, which allocates
/// `memoryCostKiB` and iterates `timeCost` times. Unbounded values are a denial
/// of service the file's author chooses (jetsam kill on the memory band, a
/// permanent spinner with a pegged core on the time band), so decoding enforces
/// `isWithinPolicy` and rejects anything outside it as a malformed file.
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

    // MARK: - Policy

    /// 128 MiB — twice the heaviest profile this app has ever written
    /// (`standard`), so a future harder profile still round-trips, while one
    /// derivation stays far inside an app's memory budget.
    static let maxMemoryCostKiB: UInt32 = 128 * 1024

    /// 16 iterations. `standard` uses 3 and `constrained` 4; at the memory
    /// ceiling this still completes in seconds rather than never.
    static let maxTimeCost: UInt32 = 16

    /// 16 lanes. Shipped profiles use 4, and lanes beyond the core count only
    /// add synchronisation, so a larger value is never a legitimate one.
    static let maxParallelism: UInt32 = 16

    /// Argon2's own `ARGON2_MIN_SALT_LENGTH`. A shorter salt makes Argon2
    /// return `ARGON2_SALT_TOO_SHORT`, which reaches the user as "couldn't
    /// decrypt" and is indistinguishable from a wrong password. This app always
    /// writes 16 bytes (`KeyHierarchy.newSalt`).
    static let minSaltLength = 8

    /// Whether these parameters are safe to hand to Argon2 unattended.
    ///
    /// Both ends matter: the ceilings bound the work an untrusted file can ask
    /// for, and the floors are Argon2's own validity rules — below them the
    /// derivation fails with an error the UI cannot explain.
    var isWithinPolicy: Bool {
        // Ordered so the parallelism bound is proven before it is multiplied:
        // `8 * parallelism` would trap on overflow for a large lane count.
        guard parallelism >= 1, parallelism <= Self.maxParallelism else { return false }
        guard timeCost >= 1, timeCost <= Self.maxTimeCost else { return false }
        // Argon2 needs at least 8 blocks per lane, and 8 KiB overall.
        guard memoryCostKiB >= 8, memoryCostKiB >= 8 * parallelism else { return false }
        return memoryCostKiB <= Self.maxMemoryCostKiB
    }

    /// Whether a salt read from a file is long enough for Argon2 to accept it.
    static func isAcceptableSalt(_ salt: Data) -> Bool { salt.count >= minSaltLength }
}

// MARK: - Validating decoder

// Declared in an extension so the memberwise initialiser survives: callers that
// build parameters in code (profiles, tests, the Argon2 known-answer vector)
// are trusted and are not routed through this check.
extension KdfParams {
    enum CodingKeys: String, CodingKey {
        case memoryCostKiB, timeCost, parallelism
    }

    /// Rejects out-of-policy parameters at the wire, before any caller can pass
    /// them to Argon2 or persist them into this device's key bundle.
    ///
    /// `nonisolated` is load-bearing: the project builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without it this witness
    /// is main-actor isolated while `KdfParams` is not, and the `Decodable`
    /// conformance crosses an actor boundary. That is a warning today and an
    /// error under the Swift 6 language mode. Decoding also has to run wherever
    /// the backup is being read, which is deliberately off the main actor.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = KdfParams(
            memoryCostKiB: try container.decode(UInt32.self, forKey: .memoryCostKiB),
            timeCost: try container.decode(UInt32.self, forKey: .timeCost),
            parallelism: try container.decode(UInt32.self, forKey: .parallelism))
        guard decoded.isWithinPolicy else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath,
                                      debugDescription: "Argon2 parameters outside the accepted policy"))
        }
        self = decoded
    }
}
