import Foundation

/// One orchestrator over every signed control-plane document (capability manifest,
/// auxiliary-domain registry, Quick View signer keyset). Freshness of these signed
/// documents MUST NOT depend on visiting any feature screen (INV-CP-01) — the app
/// drives refresh from lifecycle triggers through here, off the startup critical
/// path (INV-CP-02, refresh work is always a detached Task the caller does not await
/// on the unlock/render path).
///
/// Per document family it owns: freshness (last SUCCESSFUL remote refresh, never the
/// cache re-verify — INV-CP-REFRESH-01), in-flight dedupe (one network request per
/// family even under a launch+foreground race — INV-CP-05), failure backoff, and
/// foreground jitter. A transient failure never clears verified cache (the clients
/// only drop cache on a VERIFY failure) — INV-CP-03.
@MainActor final class SignedControlPlaneRefresher {

    enum Trigger { case launchAfterUnlock, foreground, manual }

    struct Policy {
        /// Refresh at launch-after-unlock when the last success is older than this.
        var launchStale: TimeInterval = 3600            // 1h
        /// Refresh on foreground when the last success is older than this.
        var foregroundStale: TimeInterval = 6 * 3600    // 6h
        /// Upper bound of the random foreground delay (thundering-herd guard).
        var foregroundJitter: TimeInterval = 60
    }

    private let documents: [RefreshableControlPlaneDocument]
    private let policy: Policy

    private var launchDone = false
    private var inFlight: [SignedControlPlaneStore.Family: Task<Void, Never>] = [:]
    private var backoffUntil: [SignedControlPlaneStore.Family: Date] = [:]
    private var failureStreak: [SignedControlPlaneStore.Family: Int] = [:]

    init(documents: [RefreshableControlPlaneDocument], policy: Policy = .init()) {
        self.documents = documents
        self.policy = policy
    }

    /// Refresh every family whose freshness/backoff admits it for this trigger.
    /// Non-blocking by construction (each family's fetch is its own Task); callers
    /// on the unlock/foreground path spawn this in a detached Task and never await.
    func refreshIfNeeded(trigger: Trigger, now: Date = .now) async {
        if trigger == .launchAfterUnlock {
            guard !launchDone else { return }
            launchDone = true
        }
        let tasks = documents.compactMap { start(refreshOf: $0, trigger: trigger, now: now) }
        for task in tasks { await task.value }
    }

    /// QA / explicit user action — bypasses freshness (still deduped + backoff-aware).
    func refreshNow(now: Date = .now) async {
        await refreshIfNeeded(trigger: .manual, now: now)
    }

    // MARK: Internals

    private func start(refreshOf doc: RefreshableControlPlaneDocument,
                       trigger: Trigger, now: Date) -> Task<Void, Never>? {
        let family = doc.controlPlaneFamily
        if let existing = inFlight[family] { return existing }          // dedupe/join
        if let until = backoffUntil[family], now < until { return nil }
        guard shouldRefresh(doc, trigger: trigger, now: now) else { return nil }

        let jitter = (trigger == .foreground) ? policy.foregroundJitter : 0
        let task = Task { @MainActor [weak self] in
            if jitter > 0 {
                let seconds = Double.random(in: 0...jitter)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            let ok = await doc.refresh(now: .now)
            self?.recordOutcome(family, ok: ok, hasCache: doc.hasVerifiedCache, now: .now)
            self?.inFlight[family] = nil
        }
        inFlight[family] = task
        return task
    }

    private func shouldRefresh(_ doc: RefreshableControlPlaneDocument,
                               trigger: Trigger, now: Date) -> Bool {
        if trigger == .manual { return true }
        if !doc.hasVerifiedCache { return true }                        // missing cache → immediate
        guard let lastMs = doc.lastRefreshMs else { return true }
        let ageSeconds = now.timeIntervalSince1970 - Double(lastMs) / 1000
        let threshold = (trigger == .launchAfterUnlock) ? policy.launchStale : policy.foregroundStale
        return ageSeconds > threshold
    }

    private func recordOutcome(_ family: SignedControlPlaneStore.Family,
                               ok: Bool, hasCache: Bool, now: Date) {
        if ok {
            failureStreak[family] = 0
            backoffUntil[family] = nil
            return
        }
        let attempt = (failureStreak[family] ?? 0) + 1
        failureStreak[family] = attempt
        // With last-known-good cache we can wait; a device with no cache retries sooner.
        let delays: [TimeInterval] = hasCache ? [60, 300, 900, 3600] : [30, 120, 600]
        let base = delays[min(attempt - 1, delays.count - 1)]
        let jitter = Double.random(in: 0...min(base * 0.1, 30))
        backoffUntil[family] = now.addingTimeInterval(base + jitter)
    }
}
