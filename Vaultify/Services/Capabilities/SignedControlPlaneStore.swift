import CryptoKit
import Foundation
import os

/// Atomic per-(family, environment) storage for a verified signed control-plane
/// document. The signed bytes, its monotonic version (anti-rollback high-water),
/// and the SHA-256 of its canonical transcript are persisted as ONE record, so a
/// cache loss can never leave a high-water without its bytes — the recovery trap
/// that used to strand a device (highest = 7, cache gone, server still serving 7,
/// strict `> 7` rejects forever). Keys are scoped by document family AND build
/// environment so a staging container never contaminates a production install's
/// monotonic state.
///
/// This type is pure storage + monotonic reconcile + one-time legacy migration.
/// It NEVER runs crypto: the owning client verifies the document (family-specific
/// signature/schema/env/freshness) and hands the already-verified version +
/// canonical bytes here. The equal-version branch is an idempotent recovery, gated
/// on canonical-hash equality when a local hash exists.
@MainActor final class SignedControlPlaneStore {

    enum Family: String {
        case capabilityManifest = "capability_manifest"
        case domainRegistry = "domain_registry"
        case quickViewSignerKeyset = "quick_view_signer_keyset"
    }

    /// The single atomic record. Bytes/version/hash live together so they cannot
    /// desync. `signedDocumentBytes == nil` means the high-water is known but the
    /// bytes were dropped (verify-fail or legacy migration); `canonicalHashHex ==
    /// nil` means no local hash to compare an equal-version recovery against.
    nonisolated struct State: Codable, Sendable, Equatable {
        var version: UInt64
        var canonicalHashHex: String?
        var signedDocumentBytes: Data?
        var verifiedAtMs: Int64
    }

    enum Reconcile: Equatable { case accepted, rejectedIntegrity }

    private static let log = Logger(subsystem: "com.bervion.vaultify", category: "control-plane")

    let family: Family
    let env: String
    private let defaults: UserDefaults
    private let legacyVersionKey: String
    private let legacyCacheKey: String

    /// - Parameters:
    ///   - env: build-environment tag ("staging" | "production") — scopes keys so
    ///     staging never bumps prod's high-water (INV-CP-AR-06).
    ///   - legacyVersionKey/legacyCacheKey: the pre-scoping global UserDefaults keys,
    ///     migrated once into the scoped atomic record (preserving high-water).
    init(family: Family, env: String,
         legacyVersionKey: String, legacyCacheKey: String,
         defaults: UserDefaults = .standard) {
        self.family = family
        self.env = env
        self.legacyVersionKey = legacyVersionKey
        self.legacyCacheKey = legacyCacheKey
        self.defaults = defaults
        migrateLegacyIfNeeded()
    }

    private var stateKey: String { "control_plane_state.\(family.rawValue).\(env)" }
    private var lastRefreshKey: String { "control_plane_last_refresh.\(family.rawValue).\(env)" }
    private var migrationDoneKey: String { "control_plane_migration_v1.\(family.rawValue).\(env).done" }

    // MARK: Atomic record

    private(set) var state: State? {
        get { defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(State.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: stateKey)
            } else {
                defaults.removeObject(forKey: stateKey)
            }
        }
    }

    /// Anti-rollback high-water (0 = nothing accepted yet).
    var highestVersion: UInt64 { state?.version ?? 0 }
    /// The last verified signed bytes, or nil when only the high-water survives.
    var currentBytes: Data? { state?.signedDocumentBytes }
    var hasVerifiedCache: Bool { state?.signedDocumentBytes != nil }

    // MARK: Remote-refresh clock (INV-CP-REFRESH-01 — never advanced by a cache re-verify)

    var lastRefreshMs: Int64? {
        let v = defaults.double(forKey: lastRefreshKey)
        return v == 0 ? nil : Int64(v)
    }

    func markRefreshSuccess(now: Date = .now) {
        defaults.set(now.timeIntervalSince1970 * 1000, forKey: lastRefreshKey)
    }

    // MARK: Reconcile (caller guarantees incomingVersion >= highestVersion via its verifier)

    /// Persist a freshly VERIFIED document. `incomingVersion == highestVersion` is
    /// an idempotent recovery: it must NOT advance/lower the high-water and, when a
    /// local canonical hash exists, MUST match it exactly (INV-CP-AR-02/03/04). A
    /// greater version advances the high-water monotonically.
    func reconcile(incomingVersion: UInt64, canonicalBytes: Data,
                   signedBytes: Data, now: Date = .now) -> Reconcile {
        let hashHex = Self.sha256Hex(canonicalBytes)
        if incomingVersion == highestVersion, state != nil {
            if let stored = state?.canonicalHashHex {
                guard stored == hashHex else {
                    Self.log.error("integrity incident: \(self.family.rawValue, privacy: .public) same-version canonical hash mismatch")
                    return .rejectedIntegrity
                }
                // Hash matches — idempotent. Backfill only if the bytes were lost.
                if state?.signedDocumentBytes == nil {
                    writeState(version: highestVersion, hashHex: hashHex, bytes: signedBytes, now: now)
                }
            } else {
                // Recovery without a local hash (legacy migration / storage loss).
                Self.log.notice("control_plane_same_version_recovery_without_local_hash family=\(self.family.rawValue, privacy: .public)")
                writeState(version: highestVersion, hashHex: hashHex, bytes: signedBytes, now: now)
            }
        } else {
            writeState(version: incomingVersion, hashHex: hashHex, bytes: signedBytes, now: now)
        }
        return .accepted
    }

    /// Cached bytes no longer verify (expired / key retired): drop the bytes and
    /// their now-stale hash, but KEEP the high-water (rollback floor survives).
    func dropBytesKeepingHighWater() {
        guard var s = state else { return }
        s.signedDocumentBytes = nil
        s.canonicalHashHex = nil
        state = s
    }

    /// After a cache re-verify (`applyCached`), fill in the canonical hash for a
    /// record migrated/seeded without one — without touching version or bytes.
    func backfillCanonicalHashIfMissing(canonicalBytes: Data) {
        guard var s = state, s.canonicalHashHex == nil, s.signedDocumentBytes != nil else { return }
        s.canonicalHashHex = Self.sha256Hex(canonicalBytes)
        state = s
    }

    // MARK: Internals

    private func writeState(version: UInt64, hashHex: String, bytes: Data?, now: Date) {
        state = State(version: version, canonicalHashHex: hashHex,
                      signedDocumentBytes: bytes,
                      verifiedAtMs: Int64(now.timeIntervalSince1970 * 1000))
    }

    /// One-time seed of the scoped record from the legacy global keys. Preserves
    /// the legacy high-water (never resets to 0 — INV-CP-AR-05); the canonical hash
    /// is unknown under the old scheme and is backfilled on the next `applyCached`.
    /// Provenance rule: scope to THIS build's env only; never blind-copy across envs.
    private func migrateLegacyIfNeeded() {
        guard !defaults.bool(forKey: migrationDoneKey) else { return }
        defaults.set(true, forKey: migrationDoneKey)
        guard state == nil else { return }   // never overwrite a newer scoped value
        let legacyVersion = UInt64(defaults.string(forKey: legacyVersionKey) ?? "") ?? 0
        let legacyBytes = defaults.data(forKey: legacyCacheKey)
        guard legacyVersion > 0 || legacyBytes != nil else { return }
        state = State(version: legacyVersion, canonicalHashHex: nil,
                      signedDocumentBytes: legacyBytes, verifiedAtMs: 0)
    }

    nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A signed control-plane document that the centralized refresher can keep fresh,
/// independent of any feature screen (INV-CP-01). Freshness is read from the
/// document's own store clock; `refresh` performs one fetch→verify→apply and
/// returns whether a document was accepted.
@MainActor protocol RefreshableControlPlaneDocument: AnyObject {
    var controlPlaneFamily: SignedControlPlaneStore.Family { get }
    var lastRefreshMs: Int64? { get }
    var hasVerifiedCache: Bool { get }
    func refresh(now: Date) async -> Bool
}
