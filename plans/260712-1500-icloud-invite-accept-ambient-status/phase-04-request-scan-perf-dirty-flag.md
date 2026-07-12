# Phase 04 — Stop full-zone scans for approval requests (dirty-flag refresh)

## Context links

- Audit §4-P1, §5-R5
- Scan site: `ApprovalCoordinator.refreshOwnerRequests` (`Vaultify/Services/Sharing/ApprovalCoordinator.swift:69-112`) → `fetchLiveRequests` (`ApprovalShareService.swift:322-330`)
- Triggers: foreground + shell appear (`VaultShellBehaviors.swift:77,90`), Notifications visit (`NotificationsScreen.swift:94`), request push (`ApprovalCoordinator.swift:47-51`)

## Overview

- **Priority:** P2
- **Status:** completed
- **Description:** `fetchLiveRequests` pages EVERY record in a zone (grant, display envelope, sealed blobs, nonce markers) per owned zone on every app activation, almost always finding zero requests (120s TTL). Gate the scan behind a dirty flag set by the request push, keeping one unconditional cold-launch pass as the missed-push safety net.

## Key insights

- **Why dirty-flag, not CKQuery:** a `CKQuery(recordType: requestRecordType)` fetch requires queryable indexes deployed on the production CloudKit schema; a missing index fails at runtime in prod only. The dirty-flag needs zero schema work and cuts steady-state scans to zero. (Query subscriptions — already used — do not need the fetch-side index.) Document this trade-off in code comments as the WHY.
- Requests are user-visible ALERT pushes (`ApprovalShareService.swift:107-124`), so the push is rarely missed silently; and a missed request self-expires in 120s (`fetchLiveRequests` TTL filter at `ApprovalShareService.swift:329`) — the stale-inbox cost of skipping a scan is bounded and small.
- A non-empty `pendingOwnerRequests` must still rescan: the pass is what expires TTL'd entries and drops zone-gone records (`ApprovalCoordinator.swift:100-106`).
- Single-flight already coalesces bursts (`ApprovalCoordinator.swift:73`); the flag sits in front of it.

## Requirements

**Functional**
1. `refreshOwnerRequests()` skips the zone loop when: not dirty AND `pendingOwnerRequests.isEmpty` AND the cold-launch pass already ran.
2. `.approvalRequestReceived` observer marks dirty before refreshing.
3. First call per process lifetime always scans (cold-launch safety pass).
4. Successful completed pass clears the dirty flag; a thrown/offline pass does NOT (retry on next trigger).

**Non-functional**
- No behavior change for the ceremony itself (verify-before-show untouched, `ApprovalCoordinator.swift:86-99`).
- ADR-2 gating untouched (`ApprovalCoordinator.swift:70`).

## Architecture

```
init:                requestsDirty = true          (cold-launch pass)
push observer:       requestsDirty = true → refreshOwnerRequests()
foreground/onAppear: refreshOwnerRequests()        (no-ops unless dirty or inbox non-empty)
pass completes OK:   requestsDirty = false
pass throws/offline: flag unchanged → next trigger retries
```

Note per-zone catch granularity: the existing loop catches per zone and continues (`ApprovalCoordinator.swift:100-106`) — treat "completed the loop" as success; a zone that threw offline keeps the flag set. Simplest correct rule: track `sawError` in the loop; clear flag only if `!sawError`.

## Related code files

**Modify**
- `Vaultify/Services/Sharing/ApprovalCoordinator.swift` — flag field, observer set-dirty (`:47-51`), guard + clear logic in `refreshOwnerRequests` (`:69-112`).

**Create / delete:** none. (No UI, no strings.)

## Implementation steps

1. Add `private var requestsDirty = true` with a doc comment explaining the contract (push marks dirty; foreground triggers are cheap no-ops when clean; cold launch always scans because pushes are best-effort).
2. `.approvalRequestReceived` observer: set `requestsDirty = true` before `refreshOwnerRequests()`.
3. `refreshOwnerRequests()`: after the `approvalModeEnabled` guard, `guard requestsDirty || !pendingOwnerRequests.isEmpty else { return }` (log skip via `ShareDiagnostics` for QA).
4. Inside the single-flight closure: `var sawError = false`; set it in the generic `catch` (NOT in the zone-gone catch — that is a successful determination). After the loop: `if !sawError { self.requestsDirty = false }` and assign `pendingOwnerRequests` as today.
5. Race note: flag reads/writes are all `@MainActor` (class is `@MainActor @Observable`) — no locking needed. A push arriving DURING a pass sets dirty=true; the pass then clears it — stale-clear race. Fix: snapshot `let wasDirtySnapshot` before the loop is not enough; instead re-check ordering — set `requestsDirty = false` BEFORE starting the loop and re-set on error (standard consume-then-restore), so a mid-pass push survives. Implement consume-then-restore, with a comment.
6. Compile check; verify via `ShareDiagnostics` logs: activation with clean flag produces zero `fetchLiveRequests` calls.

## Todo list

- [x] Dirty flag + doc comment (extracted as pure `RequestScanGate` struct in the same file for unit-testability)
- [x] Observer marks dirty
- [x] Skip guard + consume-then-restore semantics
- [x] Diagnostics log for skipped passes
- [x] Compile check + log-based verification (make check green; runtime log verification in device QA)

## Success criteria

- Foreground with no in-flight requests and clean flag: zero zone pulls (diagnostics log).
- Request push while foregrounded: request appears in inbox as today (no regression in `ApprovalRequestSheet` auto-present).
- Cold launch with a live request written while app was dead: request still surfaces (cold-launch pass).
- TTL expiry: an inbox entry disappears on the next trigger after expiry (non-empty inbox forces rescan).

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Missed push + no cold launch within TTL → request never shown | M×L | Request TTL is 120s; requester UX already treats no-answer as retry-with-new-request (`ApprovalCoordinator.swift:114-118` comment). Same failure mode exists today if the app is dead. |
| Consume-then-restore bug reintroduces phantom skips | L×M | Unit-test the flag state machine (phase 7) by extracting the decision into a small pure helper if inline logic proves untestable. |
| Notifications screen loses its "always fresh" feel | L×L | The screen's `.task` also calls `reconcile()` + `OwnerShareRefresher.refresh()` (`NotificationsScreen.swift:92-98`) — share statuses still refresh; only the request zone-scan is gated, and pending requests force it anyway. |

## Security considerations

- No trust-path change: verification still runs on every surfaced request. Skipping a scan can only delay display, never bypass verification.

## Next steps

Independent of phases 5-6. Feeds phase 7 tests.
