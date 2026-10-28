import XCTest
@testable import Vaultify

/// Complimentary Loox+ (owner decision 261021): the 750-day policy, the
/// add-only Keychain store, and how the entitlement store folds the grant into
/// the effective tier without ever making the user a subscriber.
final class LooxComplimentaryGrantTests: XCTestCase {
    private let anchor = Date(timeIntervalSinceReferenceDate: 0)
    private func date(days: Double) -> Date { anchor.addingTimeInterval(days * 86_400) }

    // MARK: Policy

    func testDurationIsPinnedTo750DaysOfLooxPlus() {
        XCTAssertEqual(LooxComplimentaryGrant.durationDays, 750)
        XCTAssertEqual(LooxComplimentaryGrant.duration, 750 * 86_400)
        XCTAssertEqual(LooxComplimentaryGrant.tier, .plus)
    }

    func testActiveThroughDay749AndEndsExactlyAtDay750() {
        let grant = LooxComplimentaryGrant(start: anchor)
        XCTAssertTrue(grant.isActive(at: anchor))
        XCTAssertTrue(grant.isActive(at: date(days: 749)))
        XCTAssertTrue(grant.isActive(at: date(days: 750).addingTimeInterval(-1)))
        XCTAssertFalse(grant.isActive(at: date(days: 750)))
        XCTAssertEqual(grant.endsAt, date(days: 750))
    }

    func testEffectiveTierTakesMaxOfStoreAndGrant() {
        let grant = LooxComplimentaryGrant(start: anchor)
        let now = date(days: 10)
        XCTAssertEqual(LooxComplimentaryGrant.effectiveTier(store: .free, grant: grant, now: now), .plus)
        XCTAssertEqual(LooxComplimentaryGrant.effectiveTier(store: .max, grant: grant, now: now), .max)
        XCTAssertEqual(LooxComplimentaryGrant.effectiveTier(store: .free, grant: nil, now: now), .free)
        XCTAssertEqual(LooxComplimentaryGrant.effectiveTier(store: .free, grant: grant, now: date(days: 750)), .free)
    }

    // MARK: Grant store

    func testAbsentItemMintsOnceAndPersists() {
        let backend = FakeBackend()
        let store = backend.store
        XCTAssertEqual(store.resolve(now: anchor)?.start, anchor)
        XCTAssertEqual(store.resolve(now: date(days: 5))?.start, anchor)
        XCTAssertEqual(backend.adds, 1)
        XCTAssertEqual(backend.updates, 0)
    }

    func testExistingStartIsNeverRewritten() {
        let backend = FakeBackend(stored: LooxComplimentaryGrantStore.encode(anchor))
        XCTAssertEqual(backend.store.resolve(now: date(days: 400))?.start, anchor)
        XCTAssertEqual(backend.adds + backend.updates, 0)
    }

    func testDuplicateOnAddRereadsInsteadOfOverwriting() {
        // A racing writer lands between our "absent" read and our add.
        let backend = FakeBackend()
        backend.racingStart = date(days: -3)
        XCTAssertEqual(backend.store.resolve(now: anchor)?.start, date(days: -3))
        XCTAssertEqual(backend.updates, 0)
        XCTAssertEqual(backend.stored, LooxComplimentaryGrantStore.encode(date(days: -3)))
    }

    func testFutureStartIsClampedToNow() {
        let ahead = FakeBackend(stored: LooxComplimentaryGrantStore.encode(date(days: 30)))
        XCTAssertEqual(ahead.store.resolve(now: anchor)?.start, anchor)
        XCTAssertEqual(ahead.stored, LooxComplimentaryGrantStore.encode(anchor))

        let withinTolerance = date(days: 0.5)
        let near = FakeBackend(stored: LooxComplimentaryGrantStore.encode(withinTolerance))
        XCTAssertEqual(near.store.resolve(now: anchor)?.start, withinTolerance)
        XCTAssertEqual(near.updates, 0)
    }

    func testThrowingReadWritesNothingAndReturnsNil() {
        let backend = FakeBackend()
        backend.readThrows = true
        XCTAssertNil(backend.store.resolve(now: anchor))
        XCTAssertEqual(backend.adds + backend.updates, 0)
        XCTAssertNil(backend.stored)
    }

    func testFailedWriteDoesNotClaimTheGrant() {
        let backend = FakeBackend()
        backend.writeThrows = true
        XCTAssertNil(backend.store.resolve(now: anchor))
        XCTAssertNil(backend.stored)
    }

    func testMalformedPayloadIsReminted() {
        let backend = FakeBackend(stored: Data("not-a-date".utf8))
        XCTAssertEqual(backend.store.resolve(now: anchor)?.start, anchor)
        XCTAssertEqual(backend.stored, LooxComplimentaryGrantStore.encode(anchor))
    }

    func testPayloadRoundTripsUnixSeconds() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let data = LooxComplimentaryGrantStore.encode(start)
        XCTAssertEqual(String(data: data, encoding: .utf8), "1790000000")
        XCTAssertEqual(LooxComplimentaryGrantStore.decode(data), start)
        XCTAssertNil(LooxComplimentaryGrantStore.decode(Data("12.5".utf8)))
    }

    // MARK: Real Keychain (throwaway account, never the shipped grant item)

    /// The fake backend implements add-only itself, so these pin the
    /// production half: `KeychainStore.add` must refuse a duplicate.
    func testKeychainAddNeverOverwritesAnExistingItem() throws {
        let account = "loox-complimentary-test-\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }
        XCTAssertTrue(try KeychainStore.add(Data("first".utf8), account: account))
        XCTAssertFalse(try KeychainStore.add(Data("second".utf8), account: account))
        XCTAssertEqual(try KeychainStore.get(account: account), Data("first".utf8))
    }

    func testKeychainBackedStoreMintsOnceThenKeepsTheStart() throws {
        let account = "loox-complimentary-test-\(UUID().uuidString)"
        defer { KeychainStore.delete(account: account) }
        let store = LooxComplimentaryGrantStore(backend: .init(
            read: { try KeychainStore.get(account: account) },
            add: { try KeychainStore.add($0, account: account) },
            update: { try KeychainStore.update($0, account: account) },
            delete: { KeychainStore.delete(account: account) }
        ))
        let start = Date(timeIntervalSince1970: 1_789_992_000)
        XCTAssertEqual(store.resolve(now: start)?.start, start)
        XCTAssertEqual(store.resolve(now: start.addingTimeInterval(30 * 86_400))?.start, start)
    }
}

@MainActor
final class LooxComplimentaryEntitlementTests: XCTestCase {
    private let anchor = Date(timeIntervalSinceReferenceDate: 0)
    private func date(days: Double) -> Date { anchor.addingTimeInterval(days * 86_400) }

    private func makeStore(_ grantStore: LooxComplimentaryGrantStore?) -> LooxEntitlementStore {
        let suite = "loox-complimentary-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return LooxEntitlementStore(defaults: defaults, complimentaryStore: grantStore)
    }

    func testActiveGrantGivesPlusButNotSubscriber() {
        let store = makeStore(.inMemory(start: anchor))
        store.resolveComplimentary(now: date(days: 10))
        XCTAssertEqual(store.tier, .plus)
        XCTAssertEqual(store.storeTier, .free)
        XCTAssertEqual(store.paidTier, .free)
        XCTAssertFalse(store.isSubscriber)
        XCTAssertEqual(store.complimentaryEndsAt, date(days: 750))
    }

    func testExpiredGrantFallsBackToFree() {
        let store = makeStore(.inMemory(start: anchor))
        store.resolveComplimentary(now: date(days: 750))
        XCTAssertEqual(store.tier, .free)
        XCTAssertNil(store.complimentaryEndsAt)
        XCTAssertNotNil(store.complimentaryGrant)
    }

    func testUnavailableKeychainRechecksCachedGrantExpiry() {
        let backend = FakeBackend(stored: LooxComplimentaryGrantStore.encode(anchor))
        let store = makeStore(backend.store)
        store.resolveComplimentary(now: date(days: 10))
        XCTAssertTrue(store.complimentaryActive)

        backend.readThrows = true                     // locked device
        store.resolveComplimentary(now: date(days: 751))
        XCTAssertFalse(store.complimentaryActive)
        XCTAssertEqual(store.complimentaryGrant?.start, anchor)
        XCTAssertEqual(store.tier, .free)
    }

    func testNilStoreNeverResolves() {
        let store = makeStore(nil)
        store.resolveComplimentary(now: anchor)
        XCTAssertNil(store.complimentaryGrant)
        XCTAssertEqual(store.tier, .free)
    }

    // MARK: Paid tier refresh (owner report 261028: Max read back as Loox+)

    func testGroupStatusGrantsOnlyWhileSubscribedOrInGrace() {
        XCTAssertTrue(LooxEntitlementStore.statusGrantsAccess(.subscribed))
        XCTAssertTrue(LooxEntitlementStore.statusGrantsAccess(.inGracePeriod))
        XCTAssertFalse(LooxEntitlementStore.statusGrantsAccess(.inBillingRetryPeriod))
        XCTAssertFalse(LooxEntitlementStore.statusGrantsAccess(.expired))
        XCTAssertFalse(LooxEntitlementStore.statusGrantsAccess(.revoked))
    }

    func testMaxFromEitherSourceWinsOverAStalePlus() {
        // An upgraded Plus transaction can still sit in currentEntitlements
        // while the group status already reports Max.
        XCTAssertEqual(LooxProductID.resolveTier(from: [LooxProductID.plusMonthly, LooxProductID.maxAnnual]), .max)
    }

    func testForegroundRefreshIsANoOpBeforeStart() {
        // Isolated stores never start, so the foreground hook must not reach
        // StoreKit or move the tier.
        let store = makeStore(.inMemory(start: anchor))
        store.resolveComplimentary(now: date(days: 1))
        store.refreshOnForeground()
        XCTAssertEqual(store.storeTier, .free)
        XCTAssertEqual(store.tier, .plus)
    }

    func testTierInputsChangedFiresOnlyOnChange() {
        let store = makeStore(.inMemory(start: anchor))
        var fired = 0
        store.onTierInputsChanged = { fired += 1 }
        store.resolveComplimentary(now: date(days: 1))
        store.resolveComplimentary(now: date(days: 2))
        XCTAssertEqual(fired, 1)
        store.resolveComplimentary(now: date(days: 750))
        XCTAssertEqual(fired, 2)
    }

    #if DEBUG
    func testTierOverrideWinsAndHidesComplimentaryStatus() {
        let store = makeStore(.inMemory(start: anchor))
        store.resolveComplimentary(now: date(days: 1))
        store.debugTierOverride = .max
        XCTAssertEqual(store.tier, .max)
        XCTAssertTrue(store.isSubscriber)
        XCTAssertNil(store.complimentaryEndsAt)
        store.debugTierOverride = .free
        XCTAssertEqual(store.tier, .free)
        XCTAssertNil(store.complimentaryEndsAt)
    }

    func testDebugDeleteLeavesTheGrantAbsentUntilNextResolve() {
        let store = makeStore(.inMemory(start: anchor))
        store.resolveComplimentary(now: date(days: 1))
        store.debugSetComplimentaryStart(nil)
        XCTAssertNil(store.complimentaryGrant)
        XCTAssertFalse(store.complimentaryActive)
    }

    func testUITestComplimentaryFixtureStillActive() {
        // Fails loudly well before the fixed start expires: move the fixture.
        let grant = LooxComplimentaryGrant(start: UITestFixtures.complimentaryStart)
        XCTAssertTrue(grant.isActive(at: Date.now.addingTimeInterval(90 * 86_400)),
                      "UITestFixtures.complimentaryStart expires within 90 days; move it forward")
    }
    #endif
}

/// Scriptable backend: a racing writer, a locked read, a failing write.
nonisolated private final class FakeBackend: @unchecked Sendable {
    var stored: Data?
    var readThrows = false
    var writeThrows = false
    var racingStart: Date?
    private(set) var adds = 0
    private(set) var updates = 0

    struct Failure: Error {}

    init(stored: Data? = nil) { self.stored = stored }

    var store: LooxComplimentaryGrantStore {
        LooxComplimentaryGrantStore(backend: .init(
            read: { [self] in
                if readThrows { throw Failure() }
                return stored
            },
            add: { [self] data in
                if writeThrows { throw Failure() }
                if let racingStart {
                    stored = LooxComplimentaryGrantStore.encode(racingStart)
                    self.racingStart = nil
                }
                guard stored == nil else { return false }
                adds += 1
                stored = data
                return true
            },
            update: { [self] data in
                if writeThrows { throw Failure() }
                guard stored != nil else { return false }
                updates += 1
                stored = data
                return true
            },
            delete: { [self] in stored = nil }
        ))
    }
}
