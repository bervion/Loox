# Phase 01 — SignedControlPlaneRefresher coordinator

Priority: P0 · Status: pending

## Overview
One orchestrator over the 3 signed-document clients; replaces ad-hoc per-screen
`Task { await X.refresh() }`. Owns freshness, in-flight dedupe, jitter/backoff,
independent per-document failure, cancellation safety.

## Create
- `Vaultify/Services/Capabilities/SignedControlPlaneRefresher.swift` (~140 LOC)

## Design
```
@MainActor @Observable final class SignedControlPlaneRefresher {
    enum Trigger { case launchAfterUnlock, foreground, manual }
    // deps: capabilityManifest, domainRegistry, quickViewSignerKeyset (weak-safe refs)
    // state: inFlight: Task<Void, Never>?  ; lastSuccess: [Family: Date] (persisted, env-scoped key)
    func refreshIfNeeded(trigger: Trigger) async
    func refreshNow() async   // manual/QA
}
```
Freshness key = `lastSuccessfulRemoteRefresh` (NOT lastApplied). **INV-CP-REFRESH-01:
applying cached state MUST NOT reset network-refresh freshness.** Per-family, persisted.
- missing cache → immediate (no jitter)
- stale (age > threshold) → background refresh
- fresh → no network
Dedupe: if a family's `inFlight != nil`, join it — one request per family even under
launch+foreground race (INV-CP-05).
Independent failure: per-family independent `try?`, timestamp, and backoff; one failing
never aborts others; a network failure NEVER clears verified cache (INV-CP-03).
Cancellation-safe `Task`; superseded refresh dropped cleanly.
API MUST support per-family policy (v1 shares numbers; keyset rotation may need faster later).

## LOCKED thresholds (owner, DEC-CP-REFRESH-01)
- missing cache → immediate (no jitter)
- launchAfterUnlock → refresh if age > **1h** (no jitter)
- foreground → refresh if age > **6h**, + random **0–60s jitter**
- age = last SUCCESSFUL remote refresh; applyCached does not touch it
Backoff on failure (per family):
- LKG cache exists → 1m, 5m, 15m, 1h (max 6h) + jitter
- no cache → more aggressive 30s, 2m, 10m
Note: stale threshold ≠ document cryptographic expiry (distinct concerns).

## Todo
- [ ] Coordinator with Trigger + freshness + dedupe + jitter
- [ ] Persist per-family lastSuccess (env-scoped key)
- [ ] Wire into AppEnvironment (owns the instance)

## Success
- refreshIfNeeded dedupes; missing→immediate; fresh→skip; failures independent.
