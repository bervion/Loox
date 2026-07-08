import XCTest
@testable import Vaultify

/// Atomic control-plane store: monotonic advance, equal-version idempotent
/// recovery (the cache-loss trap fix), canonical-hash integrity gate, and the
/// env-scoped, non-lowering legacy migration (INV-CP-AR-01..06).
@MainActor
final class SignedControlPlaneStoreTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "cp-store-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func store(_ defaults: UserDefaults, env: String = "production") -> SignedControlPlaneStore {
        SignedControlPlaneStore(family: .capabilityManifest, env: env,
                                legacyVersionKey: "legacy_version", legacyCacheKey: "legacy_cache",
                                defaults: defaults)
    }

    func testMonotonicAdvanceThenEqualVersionIdempotentRecovery() {
        let s = store(freshDefaults())
        let canon = Data("canonical-v7".utf8)
        XCTAssertEqual(s.reconcile(incomingVersion: 7, canonicalBytes: canon, signedBytes: Data("bytes-a".utf8)), .accepted)
        XCTAssertEqual(s.highestVersion, 7)
        // Re-serve of the SAME version with the SAME canonical transcript but a
        // different signature blob → idempotent recovery, high-water unchanged.
        XCTAssertEqual(s.reconcile(incomingVersion: 7, canonicalBytes: canon, signedBytes: Data("bytes-b".utf8)), .accepted)
        XCTAssertEqual(s.highestVersion, 7)
        XCTAssertTrue(s.hasVerifiedCache)
    }

    func testEqualVersionCanonicalHashMismatchIsIntegrityRejected() {
        let s = store(freshDefaults())
        _ = s.reconcile(incomingVersion: 7, canonicalBytes: Data("canonical-v7".utf8), signedBytes: Data("a".utf8))
        // Same version, DIFFERENT canonical bytes → content mutation, not recovery.
        XCTAssertEqual(s.reconcile(incomingVersion: 7, canonicalBytes: Data("canonical-v7-EVIL".utf8),
                                   signedBytes: Data("b".utf8)), .rejectedIntegrity)
        XCTAssertEqual(s.highestVersion, 7)
    }

    /// The recovery trap: high-water known, cache bytes lost, server still serves
    /// the same version. Must re-accept (not stick until a version bump).
    func testCacheLossSameVersionReAccepts() {
        let s = store(freshDefaults())
        let canon = Data("canonical-v7".utf8)
        _ = s.reconcile(incomingVersion: 7, canonicalBytes: canon, signedBytes: Data("bytes".utf8))
        s.dropBytesKeepingHighWater()
        XCTAssertFalse(s.hasVerifiedCache)
        XCTAssertEqual(s.highestVersion, 7, "high-water survives cache loss")
        XCTAssertEqual(s.reconcile(incomingVersion: 7, canonicalBytes: canon, signedBytes: Data("bytes".utf8)), .accepted)
        XCTAssertTrue(s.hasVerifiedCache, "bytes restored by recovery")
        XCTAssertEqual(s.highestVersion, 7)
    }

    func testMigrationPreservesLegacyHighWaterAndBytesNeverResets() {
        let defaults = freshDefaults()
        defaults.set("7", forKey: "legacy_version")
        defaults.set(Data("legacy-bytes".utf8), forKey: "legacy_cache")
        let s = store(defaults)   // migration runs in init
        XCTAssertEqual(s.highestVersion, 7, "legacy high-water preserved, not reset to 0")
        XCTAssertEqual(s.currentBytes, Data("legacy-bytes".utf8))
    }

    func testMigrationNeverOverwritesNewerScopedValue() {
        let defaults = freshDefaults()
        let s1 = store(defaults)
        _ = s1.reconcile(incomingVersion: 9, canonicalBytes: Data("c".utf8), signedBytes: Data("b".utf8))
        // A stale legacy value appears afterwards; a re-init must not clobber v9.
        defaults.set("7", forKey: "legacy_version")
        let s2 = store(defaults)
        XCTAssertEqual(s2.highestVersion, 9)
    }

    func testEnvironmentScopingIsolatesHighWater() {
        let defaults = freshDefaults()
        let prod = store(defaults, env: "production")
        _ = prod.reconcile(incomingVersion: 9, canonicalBytes: Data("c".utf8), signedBytes: Data("b".utf8))
        let staging = store(defaults, env: "staging")
        XCTAssertEqual(staging.highestVersion, 0, "prod high-water must not leak into staging scope")
        XCTAssertEqual(prod.highestVersion, 9)
    }
}
