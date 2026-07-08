import XCTest
@testable import Vaultify

/// Centralized refresher: missing-cache immediacy, freshness skipping, stale
/// refresh, launch/foreground dedupe, and once-per-process launch trigger
/// (INV-CP-01/05). Uses a fake refreshable document — no network.
@MainActor
final class SignedControlPlaneRefresherTests: XCTestCase {

    private final class FakeDoc: RefreshableControlPlaneDocument {
        let controlPlaneFamily: SignedControlPlaneStore.Family
        var lastRefreshMs: Int64?
        var hasVerifiedCache: Bool
        var refreshCount = 0
        var refreshResult = true
        var blocking = false
        private(set) var releaseContinuation: CheckedContinuation<Void, Never>?

        init(family: SignedControlPlaneStore.Family, cached: Bool, lastRefreshMs: Int64? = nil) {
            self.controlPlaneFamily = family
            self.hasVerifiedCache = cached
            self.lastRefreshMs = lastRefreshMs
        }

        func refresh(now: Date) async -> Bool {
            refreshCount += 1
            if blocking { await withCheckedContinuation { releaseContinuation = $0 } }
            if refreshResult {
                lastRefreshMs = Int64(now.timeIntervalSince1970 * 1000)
                hasVerifiedCache = true
            }
            return refreshResult
        }

        var isBlocked: Bool { releaseContinuation != nil }
        func release() { releaseContinuation?.resume(); releaseContinuation = nil }
    }

    private func refresher(_ docs: [FakeDoc]) -> SignedControlPlaneRefresher {
        SignedControlPlaneRefresher(documents: docs,
            policy: .init(launchStale: 3600, foregroundStale: 6 * 3600, foregroundJitter: 0))
    }

    func testMissingCacheRefreshesImmediately() async {
        let doc = FakeDoc(family: .capabilityManifest, cached: false)
        await refresher([doc]).refreshIfNeeded(trigger: .foreground)
        XCTAssertEqual(doc.refreshCount, 1)
    }

    func testFreshCacheSkipsForeground() async {
        let doc = FakeDoc(family: .capabilityManifest, cached: true,
                          lastRefreshMs: Int64(Date.now.timeIntervalSince1970 * 1000))
        await refresher([doc]).refreshIfNeeded(trigger: .foreground)
        XCTAssertEqual(doc.refreshCount, 0)
    }

    func testStaleCacheRefreshesOnForeground() async {
        let stale = Int64((Date.now.timeIntervalSince1970 - 7 * 3600) * 1000)
        let doc = FakeDoc(family: .capabilityManifest, cached: true, lastRefreshMs: stale)
        await refresher([doc]).refreshIfNeeded(trigger: .foreground)
        XCTAssertEqual(doc.refreshCount, 1)
    }

    /// Real RootView path: launch-after-unlock then foreground in sequence — the
    /// launch refresh marks the family fresh so foreground skips (one request).
    func testSequentialLaunchThenForegroundRefreshesOnce() async {
        let doc = FakeDoc(family: .capabilityManifest, cached: false)
        let r = refresher([doc])
        await r.refreshIfNeeded(trigger: .launchAfterUnlock)
        await r.refreshIfNeeded(trigger: .foreground)
        XCTAssertEqual(doc.refreshCount, 1)
    }

    /// Genuine concurrent triggers collapse to one in-flight request per family.
    func testConcurrentTriggersDedupeToOneRefresh() async {
        let doc = FakeDoc(family: .capabilityManifest, cached: false)
        doc.blocking = true
        let r = refresher([doc])
        async let first: Void = r.refreshIfNeeded(trigger: .manual)
        while !doc.isBlocked { await Task.yield() }          // first refresh in-flight & blocked
        async let second: Void = r.refreshIfNeeded(trigger: .manual)
        await Task.yield(); await Task.yield()                // let second join the in-flight task
        doc.release()
        _ = await (first, second)
        XCTAssertEqual(doc.refreshCount, 1)
    }

    func testLaunchAfterUnlockFiresOncePerProcess() async {
        let doc = FakeDoc(family: .capabilityManifest, cached: false)
        let r = SignedControlPlaneRefresher(documents: [doc],
            policy: .init(launchStale: 0, foregroundStale: 0, foregroundJitter: 0))
        await r.refreshIfNeeded(trigger: .launchAfterUnlock)
        doc.hasVerifiedCache = false                          // pretend cache lost again
        await r.refreshIfNeeded(trigger: .launchAfterUnlock)  // must be a no-op
        XCTAssertEqual(doc.refreshCount, 1)
    }

    func testIndependentFamiliesRefreshIndependently() async {
        let a = FakeDoc(family: .capabilityManifest, cached: false)
        let b = FakeDoc(family: .domainRegistry, cached: true,
                        lastRefreshMs: Int64(Date.now.timeIntervalSince1970 * 1000))
        await refresher([a, b]).refreshIfNeeded(trigger: .foreground)
        XCTAssertEqual(a.refreshCount, 1, "missing-cache family refreshes")
        XCTAssertEqual(b.refreshCount, 0, "fresh family skips — independent freshness")
    }
}
