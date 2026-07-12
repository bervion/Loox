import XCTest
@testable import Vaultify

/// TTL and lifecycle coverage for the Safari extension's unlocked session,
/// exercised against an in-memory backend (the keychain seam is injected, so
/// no test host entitlements are involved): sliding refresh, hard cap,
/// expired self-delete, immediate-policy suppression, and the mirrored
/// auto-lock → TTL policy.
final class ExtensionSessionStoreTests: XCTestCase {

    /// Single-slot in-memory stand-in for the keychain item.
    private final class MemorySlot: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        var data: Data? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }

    private func makeBackend() -> (ExtensionSessionStore.Backend, MemorySlot) {
        let slot = MemorySlot()
        let backend = ExtensionSessionStore.Backend(
            read: { slot.data },
            write: { data in slot.data = data; return true },
            delete: { slot.data = nil })
        return (backend, slot)
    }

    private let key: [UInt8] = Array(0..<32)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Save / retrieve

    func testRoundtripWithinWindowReturnsKey() {
        let (backend, _) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        let hit = ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(299), backend: backend)
        XCTAssertEqual(hit, key)
    }

    func testImmediatePolicyNeverCreatesASessionAndRevokesAnExistingOne() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        XCTAssertNotNil(slot.data)
        // Re-saving under the "immediate" policy (ttl 0) must clear, not store.
        ExtensionSessionStore.save(vaultKey: key, ttl: 0, now: t0, backend: backend)
        XCTAssertNil(slot.data)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, backend: backend))
    }

    // MARK: - Expiry

    func testExpiredSessionReturnsNilAndSelfDeletes() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 60, now: t0, backend: backend)
        let miss = ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(60), backend: backend)
        XCTAssertNil(miss)
        XCTAssertNil(slot.data, "an expired item must be removed on read")
    }

    func testSlidingRefreshExtendsTheWindowOnEachHit() {
        let (backend, _) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 60, now: t0, backend: backend)
        // A hit at +50 slides lastActivity, so +100 (past the original window)
        // is still inside the refreshed one; +200 is not.
        XCTAssertNotNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(50), backend: backend))
        XCTAssertNotNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(100), backend: backend))
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(200), backend: backend))
    }

    func testHardCapBoundsAnyRequestedTTL() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 3600, now: t0, backend: backend)
        let pastCap = t0.addingTimeInterval(ExtensionSessionStore.maxTTL)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: pastCap, backend: backend))
        XCTAssertNil(slot.data)
    }

    func testOversizedStoredTTLIsClampedOnRead() throws {
        // Simulate a payload persisted with a huge TTL (e.g. tampered/legacy):
        // the cap must be enforced by the reader, not only by the writer.
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        var blob = try XCTUnwrap(slot.data)
        withUnsafeBytes(of: UInt64(86_400).littleEndian) { bytes in
            blob.replaceSubrange(1..<9, with: bytes)
        }
        slot.data = blob
        let pastCap = t0.addingTimeInterval(ExtensionSessionStore.maxTTL)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: pastCap, backend: backend))
    }

    // MARK: - Invalidation

    func testClearRemovesTheSession() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        ExtensionSessionStore.clear(backend: backend)
        XCTAssertNil(slot.data)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, backend: backend))
    }

    func testMalformedPayloadSelfDeletes() {
        let (backend, slot) = makeBackend()
        slot.data = Data([0xFF, 0x01, 0x02])
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, backend: backend))
        XCTAssertNil(slot.data)
    }

    // MARK: - Mirrored auto-lock policy

    func testConfiguredTTLFollowsTheMirroredAutoLockPolicy() throws {
        let suiteName = "extension-session-ttl-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removeObject(forKey: SharedConfig.autoLockSecondsKey)
        XCTAssertEqual(ExtensionSessionStore.configuredTTL(defaults: defaults),
                       ExtensionSessionStore.defaultTTL, "missing mirror falls back to the default")

        defaults.set(0, forKey: SharedConfig.autoLockSecondsKey)
        XCTAssertEqual(ExtensionSessionStore.configuredTTL(defaults: defaults), 0,
                       "immediate means no session, ever")

        defaults.set(60, forKey: SharedConfig.autoLockSecondsKey)
        XCTAssertEqual(ExtensionSessionStore.configuredTTL(defaults: defaults), 60)

        defaults.set(3600, forKey: SharedConfig.autoLockSecondsKey)
        XCTAssertEqual(ExtensionSessionStore.configuredTTL(defaults: defaults),
                       ExtensionSessionStore.maxTTL, "a long auto-lock is capped")
    }
}
