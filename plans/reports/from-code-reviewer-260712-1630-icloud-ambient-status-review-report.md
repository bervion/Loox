# Code Review — iCloud Approval-Mode Ambient Status (feat/icloud-ambient-share-status)

**Scope:** 7 commits vs main (`1e53df7..35eb599`), 27 files, +1131/−49. Plan: `plans/260712-1500-icloud-invite-accept-ambient-status/`. Read-only review; no build re-run (plan phase-07 records local suites green minus the baseline environmental host crash, which is out of scope here).

## Verdict up front

**The Phase-6 safety-code verify gate is sound.** No path found that reveals shared plaintext, composes an askEachTime request, or feeds AutoFill for a zone still `pending`. One narrow reinstall-time hole in the legacy backfill (M1) weakens it as defense-in-depth but is not exploitable without a prior Keychain write failure or a kill between two writes. **No Critical findings. One High** (reliability of the feature's primary background path, not security).

### Verify-gate surfaces audited (all gated)

| Surface | Gate point | Verified |
|---|---|---|
| Detail value rows | `ItemDetailScreen.swift:93-106` — pending branch renders `verifyPromptCard` instead of `SharedAccessGateView{fieldsCard}` | ✓ |
| askEachTime request compose | `RequestCodeView.swift:230-236` `startRequest()` choke point covers BOTH buttons (idle + "Request Again"); view withheld while pending anyway; only 1 call site of `RequestCodeView` (`ItemDetailScreen.swift:487`) passes the flag | ✓ |
| AutoFill / QuickType | `SharedItemsProjection.swift:293-299` `buildCacheEntries()` filters `verification(forItem:).allowsUse`; all 3 cache-save sites (recordVerification :94, removeItem :116, refresh :281) route through it; extension reads only this cache | ✓ |
| Bottom "Copy Password" cluster | `ItemDetailScreen.swift:51-55` excludes `sharedOrigin != nil` outright | ✓ |
| List rows (swipe/context) | `VaultItemRowLink.swift:31-65` — no value actions for projections | ✓ |
| Passkeys section | `SharedItemPasskeysSection.swift` — metadata only, private key never in-app; use path = AutoFill (cache withheld) | ✓ |
| Toolbar (QuickView / ShareLink) | `ItemDetailScreen.swift:162` — entire menu hidden for shared items | ✓ |

**Trust-model invariants verified:**
- Pin remains the crypto anchor: `OwnerKeyVerification` never influences `pinOwnerKey`/`ApprovalVerifier`; it only governs USE (`OwnerKeyVerification.swift` doc + call graph).
- Fail closed: missing marker reads `pending` (`SharedItemsProjection.swift:151-155`, `ApprovalRecipientService.swift:937-940`); failed marker write = absent = pending.
- Terminal states stick: `recordVerification` refuses overwrite of a decided marker (`SharedItemsProjection.swift:96-98`); `.pending` is written only when `pinnedOwnerKey == nil` (fresh pin, `:207-211`) — the only way pending "overwrites" a decided marker is a pin lost from Keychain, and re-pinning → re-verify is the correct fail-closed direction.
- Lifecycle: `clearPin` deletes marker beside pin (`ApprovalRecipientService.swift`); `leave()` → `clearPin` ✓.
- Backfill never overwrites an existing marker (`OwnerKeyVerification.backfillState`, pinned by tests).

---

## High

### H1 — Background silent push: fetch completion handler returned before the refresh runs; banner delivery races app suspension
`Vaultify/App/AppPushDelegate.swift:38-49`

`didReceiveRemoteNotification` posts `.shareAcceptanceHint` and immediately calls `completionHandler(.newData)`. The actual work — `OwnerShareRefresher.refreshAll()` (one-shot subscription backfill + up to N×2 CloudKit round-trips + `UNUserNotificationCenter.add`) — runs in a fire-and-forget `Task` after the delegate returns. Calling the fetch completion handler tells iOS it may suspend the app; the multi-second CloudKit fetches race that suspension.

**Failure scenario:** owner backgrounded; silent push wakes the app; iOS suspends it 1–2s later (low power, thermal, or just aggressive scheduling); `resolveStatus` never completes; **no local banner is posted and nothing retries** — the crossing is only detected on the next manual foreground. This silently defeats plan success criterion #1 ("A gets a banner without opening the app") intermittently in the field while passing QA.

This handler shape is pre-existing for sync pulls (harmless — pulls re-run on foreground), but the banner is the one consumer where the background wake IS the feature.

**Fix direction:** for `.shareAcceptance`, hold the completion handler until the refresh completes (bounded, e.g. `withTimeout(~20s)` → `.newData`/`.failed`), or wrap the refresh in `UIApplication.beginBackgroundTask`/`endBackgroundTask`. Either keeps the process alive for the seconds the CloudKit fetch needs.

## Medium

### M1 — Pin-before-marker write ordering lets a reinstall grandfather an undecided zone to `confirmed`
`Vaultify/Services/Sharing/SharedItemsProjection.swift:206-212` (pin loop), `:449-460` (backfill)

Fresh-pin sequence is two non-atomic Keychain writes: `pinOwnerKey(...)` (throws) then `setOwnerKeyVerification(.pending)` (**`try?` best-effort**). If the marker write fails or the process dies between the two, the zone has a pin and no marker. Within that install this reads as `pending` — fail closed, fine. But the backfill one-shot flag lives in **UserDefaults** while pins live in **Keychain**: after app deletion + reinstall, Keychain (pin, no marker) survives and the flag resets, so `backfillVerificationMarkers` sees `hasPin: true, existing: nil` → writes **`.confirmed`** — the verify gate is silently skipped for a share the user never decided. This is exactly the "attacker zone confirmed without a human decision" class the gate exists to close, though it needs the improbable precondition (marker write failure/kill in the write gap, then reinstall).

**Fix direction (either closes it):**
1. Write `.pending` marker **before** `pinOwnerKey` — makes "post-gate pin without marker" impossible by construction, so backfill's `hasPin && existing == nil` truly means pre-gate; or
2. Persist the backfill-done flag in the Keychain beside the pins so it shares their lifecycle.

### M2 — `checkProfileNow` performs the public-DB auto-invite retry before its step guard, now push-triggered
`Vaultify/Features/Sharing/ShareAccessSheet.swift:387-395` + new `.onReceive(.shareAcceptanceHint)` at `:707-711`

`checkProfileNow()` runs `await retryAutoInviteIfNeeded()` (a public-DB **write** path) unconditionally, before the `case .waiting` guard. The new hint hook invokes it on every acceptance push while the sheet is open, including when `step` already moved to `.fingerprint`/`.done`. The poll loop was deliberately restructured this branch to separate the cheap read (every tick) from this write (every 6th tick) — the hint hook undoes that separation. `IfNeeded` guards make it a steady-state no-op, so impact is wasted writes/rate-limit budget, not correctness. Fix: move `retryAutoInviteIfNeeded()` below the `guard case .waiting` (or drop it from the push-triggered path — the push means the recipient already has the invite).

## Low

### L1 — `needsVerification` does a Keychain round-trip per body evaluation
`Vaultify/Features/ItemDetail/ItemDetailScreen.swift:203-206` — called 3× per `body` render (branch, safetyCodeCard, RequestCodeView param); `SecItemCopyMatching` per call during scroll/timer re-renders. Works, but caching in `@State` (load on appear, update in `onDecision`) is cheaper. Perf only.

### L2 — Erase Vault leaves recipient-side pins and verification markers behind
`Vaultify/App/AppEnvironment.swift:161-196` clears the projection snapshot + AutoFill cache but not `approval_owner_key_pin_*` / `approval_owner_key_verification_*` Keychain entries (there's no zone enumeration to drive it). Pre-existing for pins; the marker just inherits the pin's lifecycle, and zone names are opaque-random so cross-vault collision is impossible. Note only — but if a pin wipe is ever added, the markers must go with it (and the `shared_owner_key_verification_backfilled` UserDefaults flag should be reset there too).

### L3 — Notifier observers never removed
`OwnerShareRefresher.swift:24,38-42` — no `deinit` removing the block observer. Object is app-lifetime (owned by `AppEnvironment`), matches `ApprovalCoordinator`'s pre-existing pattern. Style.

### L4 — Banner body shows the recipient email on the lock screen
`ShareStatusNotifier.swift:55`. Device-local data on the owner's own device, no secrets/item titles — acceptable, and the code comments the boundary correctly. Note for the privacy docs only.

## CloudKit / concurrency — checked, no findings

- **Subscription idempotence:** `saveAcceptanceSubscription` saves under a stable per-zone ID (upsert); `revoke` deletes both request + accept IDs (`ApprovalShareService.swift:997-1001`). CK subscriptions are per-user-per-database, so one delete covers all owner devices.
- **`createShare` now also blocks on the acceptance-subscription save** — consistent with the pre-existing `saveOwnerAlertSubscription` behavior; not flagged per review scope.
- **`.firesOnRecordCreation` only:** correct — the status transition cares about profile *existence*; second-device re-publishes are updates and the owner is already `readyForCeremony`.
- **Backfill one-shot** (`OwnerShareRefresher.swift:59-65`): flag set before awaits on MainActor under SingleFlight — no double-run; failures retry next launch as documented.
- **Conflict-merge loop** (`ApprovalRecipientService.swift:830-860`): bounded at 3; the where-clause `attempt < maxAttempts - 1` means the final conflict **propagates** (no silent drop; caller's resume backoff retries later). Per-record error surfaced via `result.get()` — correct shape for the async `modifyRecords` API. `error.serverRecord` fallback refetch handled. Merge convergence + idempotence pinned by `ParticipantProfileMergeConflictTests`. Keeping an undecodable server record as base (recover-by-overwrite, preserves change tag) is the right call.
- **Dirty-flag gate:** consume-then-restore verified incl. mid-pass push (`ApprovalRefreshGateTests`); `zoneNotFound` correctly treated as success (doesn't restore flag); MainActor-confined so no locking; the shouldScan→beginScan gap is closed by the scan reading the server after the push's record landed. Non-empty inbox forcing the TTL pass preserves expiry behavior.
- **`MainActor.assumeIsolated`** in `queue: .main` observers — safe (main queue ≡ MainActor executor).
- **Notification dedup:** monotonic rank guard confirmed at `SharingStore.swift:109`; `shouldNotify` requires a strict rank crossing AND app-inactive; SingleFlight's follow-up rerun re-reads the already-advanced store, so a hint burst can't double-fire. Foreground poll races are masked by `appActive == true`. `willPresent` returns `[]` for the local banner, so it never surfaces while frontmost.
- **Offline downgrade** (`resolveStatus` → `.inviteSent`) dropped by the same rank guard.
- **Tap mailbox:** buffer-before-post ordering correct for cold launch; drain order (before `presentNextApprovalIfIdle`) gives the explicit tap priority; mailbox retained when a ceremony sheet is up, retried on next foreground; consumed-then-nil for revoked shares is intentional.
- **ADR-2:** no new code gates on `iCloudSyncEnabled` (grep-verified across the diff).
- **Background refresh needs no Vault Key** — SharingStore (UserDefaults) + CloudKit metadata only. Correct for the locked-in-background wake.

## Localization — pass

All 8 new user-facing strings have VI translations in `Localizable.xcstrings`; no `!`, `—`, or `·`. The interpolated notification body uses `appString(_: String.LocalizationValue)` (`VaultifyCore/Localization.swift:33`), so `\(record.recipientLabel)` correctly resolves against the `%@ accepted. Tap to finish setting up the share.` catalog key. "The codes match" stale flag correctly cleared. Rewritten invite-sent copy updated in both EN + VI.

## Positive observations

- Pure-logic test targeting is excellent: `RequestScanGate`, `shouldNotify`, `backfillState`, merge convergence, push routing — all unit-tested without CloudKit fakes.
- `startRequest()` as an independent enforcement layer under the layout-level withhold is exactly the right belt-and-braces shape.
- The `classify(subscriptionID:)` split for testability, and defaulting unknown IDs to the harmless `vaultRemoteChange`, are both sound.
- Comments explain invariants (why), not plan codes — complies with the no-plan-refs rule throughout.

## Recommended actions (priority order)

1. **H1:** keep the process alive for the acceptance-push refresh (defer completion handler or background task assertion).
2. **M1:** write the `.pending` marker before `pinOwnerKey` (one-line reorder + make the marker write failure abort the pin), or move the backfill flag to Keychain.
3. **M2:** move `retryAutoInviteIfNeeded()` behind the `.waiting` guard in `checkProfileNow`.
4. L1 (cache verification state in the detail screen) — nice-to-have before merge; L2-L4 — backlog notes.
5. Confirm full suite green on CI stable Xcode before merge (plan's own caveat).

## Metrics

- New tests: 6 suites / 25 cases, all pure-logic. Coverage of new logic paths: gate, notifier decision, backfill, merge, routing, badge — good; no test for the H1 background-lifetime path (device QA gate).
- Lint/build: not re-run in this read-only pass (branch commits imply compile-clean; CI must confirm).

## Unresolved questions

1. H1: is there existing infra (e.g. a background-task wrapper used elsewhere) the fix should reuse, or is a local `beginBackgroundTask` acceptable?
2. M1: is "marker-first" ordering acceptable, or should the backfill flag move to Keychain instead (also survives the L2 erase interaction)?
3. `recipientLabel` appears to always be a normalized email in current flows — confirm link-invite shares can't produce an empty label (leading-space banner body).
