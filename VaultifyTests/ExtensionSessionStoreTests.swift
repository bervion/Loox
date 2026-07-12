import XCTest
@testable import Vaultify

/// TTL and lifecycle coverage for the Safari extension's unlocked session,
/// exercised against an in-memory backend (the keychain seam is injected, so
/// no test host entitlements are involved): sliding refresh, hard cap,
/// expired self-delete, immediate-policy suppression, live-policy clamping,
/// the revocation race, and the mirrored auto-lock → TTL policy.
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
            update: { data in
                // Keychain SecItemUpdate semantics: never creates a missing item.
                guard slot.data != nil else { return false }
                slot.data = data
                return true
            },
            delete: { slot.data = nil })
        return (backend, slot)
    }

    private let key: [UInt8] = Array(0..<32)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// A policy wide enough to never be the binding constraint in tests that
    /// exercise the stored ttl (tests pass the policy explicitly so the shared
    /// App Group defaults of the test host can't influence outcomes).
    private let openPolicy = ExtensionSessionStore.maxTTL

    // MARK: - Save / retrieve

    func testRoundtripWithinWindowReturnsKey() {
        let (backend, _) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        let hit = ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(299),
                                                 policy: openPolicy, backend: backend)
        XCTAssertEqual(hit, key)
    }

    func testImmediatePolicyNeverCreatesASessionAndRevokesAnExistingOne() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        XCTAssertNotNil(slot.data)
        // Re-saving under the "immediate" policy (ttl 0) must clear, not store.
        ExtensionSessionStore.save(vaultKey: key, ttl: 0, now: t0, backend: backend)
        XCTAssertNil(slot.data)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, policy: openPolicy, backend: backend))
    }

    // MARK: - Expiry

    func testExpiredSessionReturnsNilAndSelfDeletes() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 60, now: t0, backend: backend)
        let miss = ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(60),
                                                  policy: openPolicy, backend: backend)
        XCTAssertNil(miss)
        XCTAssertNil(slot.data, "an expired item must be removed on read")
    }

    func testSlidingRefreshExtendsTheWindowOnEachHit() {
        let (backend, _) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 60, now: t0, backend: backend)
        // A hit at +50 slides lastActivity, so +100 (past the original window)
        // is still inside the refreshed one; +200 is not.
        XCTAssertNotNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(50),
                                                       policy: openPolicy, backend: backend))
        XCTAssertNotNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(100),
                                                       policy: openPolicy, backend: backend))
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(200),
                                                    policy: openPolicy, backend: backend))
    }

    func testHardCapBoundsAnyRequestedTTL() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 3600, now: t0, backend: backend)
        let pastCap = t0.addingTimeInterval(ExtensionSessionStore.maxTTL)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: pastCap,
                                                    policy: 3600, backend: backend))
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
        XCTAssertNil(ExtensionSessionStore.retrieve(now: pastCap,
                                                    policy: 86_400, backend: backend))
    }

    // MARK: - Live policy clamping on read

    func testTighterLivePolicyShrinksAnExistingSessionOnRead() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 900, now: t0, backend: backend)
        // Auto-lock tightened to 60 s after the session was minted: a read at
        // +120 is inside the stored 900 s window but outside the live policy.
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(120),
                                                    policy: 60, backend: backend))
        XCTAssertNil(slot.data, "a session past the live policy self-deletes")
    }

    func testHitUnderTighterPolicyPersistsTheSmallerWindow() {
        let (backend, _) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 900, now: t0, backend: backend)
        XCTAssertNotNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(30),
                                                       policy: 60, backend: backend))
        // The slide persisted the clamped 60 s window, so a later read is
        // bounded by it even if the policy has been relaxed again since.
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(100),
                                                    policy: 900, backend: backend))
    }

    func testImmediateLivePolicyRevokesOnRead() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, policy: 0, backend: backend))
        XCTAssertNil(slot.data)
    }

    // MARK: - Invalidation

    func testClearRemovesTheSession() {
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        ExtensionSessionStore.clear(backend: backend)
        XCTAssertNil(slot.data)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, policy: openPolicy, backend: backend))
    }

    func testSlideAfterConcurrentClearDoesNotResurrectTheSession() {
        // The revocation race: a reader gets a valid payload, then the app
        // clears the session (lock / biometric change) BEFORE the sliding
        // rewrite lands. The update-only slide must not re-create the item,
        // and the read must report the session as revoked.
        let (backend, slot) = makeBackend()
        ExtensionSessionStore.save(vaultKey: key, ttl: 300, now: t0, backend: backend)
        let payload = slot.data
        let racing = ExtensionSessionStore.Backend(
            read: { slot.data = nil; return payload },  // clear() wins the race
            write: backend.write,
            update: backend.update,
            delete: backend.delete)
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(10),
                                                    policy: openPolicy, backend: racing),
                     "a concurrently revoked session must not be returned")
        XCTAssertNil(slot.data, "the slide must never re-create a revoked session")
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0.addingTimeInterval(10),
                                                    policy: openPolicy, backend: backend))
    }

    func testMalformedPayloadSelfDeletes() {
        let (backend, slot) = makeBackend()
        slot.data = Data([0xFF, 0x01, 0x02])
        XCTAssertNil(ExtensionSessionStore.retrieve(now: t0, policy: openPolicy, backend: backend))
        XCTAssertNil(slot.data)
    }

    // MARK: - Mirrored auto-lock policy

    func testConfiguredTTLFollowsTheMirroredAutoLockPolicy() throws {
        let suiteName = "extension-session-ttl-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removeObject(forKey: SharedConfig.autoLockSecondsKey)
        XCTAssertEqual(ExtensionSessionStore.configuredTTL(defaults: defaults), 0,
                       "a missing mirror fails closed: no policy, no session")

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
