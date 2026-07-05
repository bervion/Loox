# Code Review — Phase 6: Recipient UX & Request State Machine

Branch: feat/approval-mode-sharing (uncommitted). Compile iOS+macOS green, 161/161 tests (per lead).
Scope: RequestCodeView.swift, SharedItemView.swift, SharedWithMeScreen.swift (new); VaultShellBehaviors,
AppPushDelegate, SharedConfig, ApprovalRecipientService, AppEnvironment, HomeScreen, Localizable.xcstrings (modified).
Spec: phase-06-recipient-ux.md, plan.md ADR-3/4/6/7.

## Overall Assessment

State-machine design is fundamentally sound: supersede-by-key-drop + poll-only-current-id is the right
construction, stale fail-closed gate exists, pre-pin decrypt is double-guarded (view + service), fingerprint
is a proper domain-separated SAS. But there is one likely feature-killing CloudKit zone-ID bug, a navigation
route-type collision that makes the detail screen unreachable, and two async holes in the tick loop that
undermine the ADR-6 supersede argument in race windows.

## Critical

### C1. Shared-DB zone ID reconstructed WITHOUT ownerName — recipient screens likely dead on real cross-account shares
- `SharedItemView.swift:25` — `CKRecordZone.ID(zoneName: zoneName)` defaults `ownerName` to
  `CKCurrentUserDefaultName` (`__defaultOwner__`). In the **shared** database, zones are namespaced by the
  SHARING OWNER's user record name; `acceptedApprovalZones()` (ApprovalRecipientService.swift:24) returns
  correct full IDs, but navigation passes only `zoneID.zoneName` as a `String`
  (SharedWithMeScreen.swift:56) and the detail view rebuilds a default-owner ID.
- Consequence: `fetchGrant` / `recordZoneChanges` target a nonexistent zone → `grantMissing` /
  `.zoneNotFound` → user sees "The owner stopped sharing this item." for a live share. Every downstream
  call (fingerprint, shared values, sendRequest, fetchResponse) inherits the bad `zoneID`
  (RequestCodeModel init, RequestCodeView.swift:39).
- Secondary: two shares from different owners can collide on bare `zoneName`; the TOFU pin key
  (`pinAccount(zoneName:)`, ApprovalRecipientService.swift:59) is also zoneName-only — cross-owner pin
  collision if names ever repeat.
- Fix: navigate with a dedicated Hashable route carrying the full `CKRecordZone.ID` (zoneName + ownerName);
  key the pin on `ownerName + zoneName`. **Verify on 2-device QA** — compile/tests cannot catch this
  (confidence ~90% from CloudKit shared-DB semantics; unit tests never hit sharedCloudDatabase).

## High

### H1. `navigationDestination(for: String.self)` collision — SharedItemView unreachable from Home stack
- HomeScreen applies `vaultNavigationDestinations()` which already registers
  `String → ItemDetailScreen` at the stack root (VaultRoutes.swift:33). SharedWithMeScreen adds a second
  `String` destination on a pushed view (SharedWithMeScreen.swift:70). SwiftUI uses the destination
  **closest to the root**: tapping a zone row pushes `ItemDetailScreen(itemID: "apz-…")` (blank detail),
  never `SharedItemView`, plus a runtime warning.
- Fix folds into C1: a dedicated `SharedZoneRoute` value type resolves both defects.

### H2. ADR-6 supersede hole: stale `pending` held across the fetch await; `handle()` never re-validates currency
- `tickWhileWaiting` (RequestCodeView.swift:74-95): `guard let pending` makes a **local copy** of
  `PendingRequest` — including the old ephemeral private key — then suspends in
  `await service.fetchResponse(...)`. If the user taps "Request Again" during that suspension,
  `sendRequest` sets `self.pending = nil` (RequestCodeView.swift:59), but the local copy keeps the old key
  alive. If the owner's approval of the OLD request is returned by the in-flight pull, `handle(response,
  pending: localOld)` (line 84-86 → 97-124) runs with no check that (a) the task is cancelled, (b)
  `self.pending` still matches:
  - old approval within its window → `phase = .approved(oldCode)` — a **superseded response renders**,
    violating gate condition 4 ("rejected fail-closed, never shown"; the `periodEndUnixMs > now` gate at
    line 106 only stops window-expired codes, not fresh approvals of a superseded request);
  - `handle` also does `self.pending = nil` (lines 111/114/118/121) — this **destroys the NEW request's
    key**, so the new tick loop's `guard let pending else { return }` exits and the new request strands
    in `.waiting` until the 120s TTL.
- The doc-comment claim "old response is both undecryptable (key gone) and never fetched (wrong id)"
  (lines 11-14) is false across this await gap — same bug class as the Phase-5 "await-gap conditions
  checks" finding.
- Fix: at the top of `handle` (and after every await in the loop):
  `guard !Task.isCancelled, self.pending?.request.requestId == pending.request.requestId else { return }`.
- Narrow race (needs owner approving the old request while the superseding pull is in flight), but it is
  exactly the ADR-6 gate scenario — blocking for the gate.

### H3. Cancellation swallowed → cancelled tick task hot-loops on MainActor up to 120s
- RequestCodeView.swift:84 (`try? await service.fetchResponse`) and :93 (`try? await Task.sleep`) both
  swallow `CancellationError`. When `.task(id:)` cancels the loop **while phase stays `.waiting`** —
  i.e., user navigates back from SharedItemView, or the view is otherwise torn down mid-wait — the loop
  keeps running: both awaits now throw immediately, so it degenerates into a tight MainActor spin (or, if
  CK ignores cancellation, a zero-backoff network poll) until the request TTL expires
  (`ApprovalConfig.requestTTLMs = 120_000`, ApprovalConfig.swift:70). It also retains the model (and the
  ephemeral key) past view teardown.
- Same root cause lets the cancelled OLD task, after "Request Again", re-enter the loop against the NEW
  `self.pending` (the guard re-reads it fresh) and double-poll concurrently with the new task.
- Fix: `while !Task.isCancelled, case .waiting ... `; replace `try? await Task.sleep` with
  `do { try await Task.sleep(...) } catch { return }`.

### H4. First-time recipient: acceptance resume + "Shared with Me" row strand until next lock/unlock
- Chain: accept CKShare → breadcrumb set + `.vaultShareAccepted` posted (AppPushDelegate.swift:109-113)
  → `ApprovalCoordinator.bumpRecipientCounter` is **gated on `settings.approvalModeEnabled`**
  (ApprovalCoordinator.swift:104-107) → false for a pure recipient → counter never bumps →
  `VaultShellBehaviors .task(id: recipientChangeCounter)` (line 73) already ran at shell appear and never
  re-fires. `resumePendingShareAcceptance` is what would set `approvalModeEnabled = true` — chicken-and-egg.
- Effect when the invite is accepted while the shell is already visible & unlocked (the common path:
  tap invite link → app foregrounds): escrow + profile publish + shared-DB subscription are deferred until
  the shell is recreated (next lock/unlock via RootView route swap; indefinitely if `lockOnBackground` is
  off). Owner meanwhile waits forever for B's participant profile. The Home "Shared with Me" row is also
  hidden (`approvalModeEnabled` gate, HomeScreen diff) so B cannot even navigate to the share.
- Onboarding path is OK: shell is created fresh after onboarding → initial `.task` fire runs resume with
  vaultKey present. Offline-failure retry shares the same latency (flag kept, no re-trigger until unlock).
- Fix: bump the recipient counter unconditionally for `.vaultShareAccepted` (it carries no payload and
  only fires on an explicit user accept — the `approvalModeEnabled` mute is meant for push noise), or have
  VaultShellBehaviors observe `.vaultShareAccepted` directly.
- Validation §3 otherwise holds: breadcrumb set only after CloudKit accept succeeds; cleared only after
  escrow → publish-all-zones → subscription all succeed; failure keeps the flag; `completeAcceptance` is
  idempotent (singleton profile record, `.allKeys` overwrite, covers all zones). Writer and reader both
  use `UserDefaults.standard` in the app process — consistent.

## Medium

### M1. `@State` mutated during body evaluation
- `SharedItemView.requestModel(grant:fieldId:)` writes `requestModels[fieldId] = model` while called from
  `fieldsCard` inside `body` (SharedItemView.swift:81, 95-101) — "Modifying state during view update"
  undefined behavior. Create the models in `load()` when `.ready` is assembled.

### M2. Cached RequestCodeModels hold a stale `grant` snapshot
- Models are keyed by `fieldId` only; after a `recipientChangeCounter` reload fetches a fresh grant,
  cached models keep the old `grant` (grantId, itemId, capabilities) — a re-issued/rotated grant makes
  every request sign against the stale grant → owner-side `verifyRequest` fails silently → B sits in
  WAITING to slow-hint/EXPIRED with no hint why. Rebuild (or key the cache by `grant.id` + `fieldId`)
  when the loaded grant's identity/epoch changes.

### M3. Crash window between CloudKit accept and breadcrumb set
- AppPushDelegate.swift:105-113 — if the process dies after `container.accept` returns but before
  `UserDefaults.set`, the acceptance exists server-side but no local completion ever runs (no publish, no
  subscription, row hidden). Comment says the accept "survives crashes on its own" — it survives, but
  nothing resumes it. Cheap hardening: set the flag BEFORE `accept` (resume is a no-op if accept failed
  and the zone never appears — `completeAcceptance` over zero zones succeeds and clears; consider only
  clearing when ≥1 zone was published, or tolerate the owner re-inviting).

## Low

- L1. `ApprovedCodeView` renders "About 0s remaining" for the first frame (`remainingSeconds = 0` until
  `onAppear`) — seed it from `periodEndUnixMs` at init (RequestCodeView.swift:233).
- L2. Raw `error.localizedDescription` shown in `.failed` states (RequestCodeView.swift:67,
  SharedItemView.swift:144, SharedWithMeScreen.swift:85) — unlocalized CKError prose; matches existing
  codebase pattern, no sensitive data.
- L3. `PolarisIcon(Icons.chevronRight, size: 14)` hardcoded in HomeScreen row — DS nit (use a Metric).
- L4. TrustFingerprintView copy is owner-phrased ("proves you're sharing with the right person") but reused
  recipient-side with `recipientLabel = appString("the owner")`; the interpolated VI fragment may read
  awkwardly. Copy nit.
- L5. `recipientDeviceId` writes UserDefaults from a computed property evaluated in body
  (SharedItemView.swift:104-110) — harmless, but belongs in `load()`.

## Verified Sound (critical checks that PASSED)

- **(a) Supersede + fail-closed (static path):** `fetchResponse` filters
  `record[requestName] == requestId` and re-verifies `expectedRequestId`
  (ApprovalRecipientService.swift:163-174); `sendRequest` nils `pending` BEFORE creating the new request
  (RequestCodeView.swift:59) so the old key is gone from the model; the only render path for a code is
  `phase = .approved`, set solely behind `payload.periodEndUnixMs > now` (line 106). The two-live-codes
  argument holds **except** for the H2 await-gap.
- **(c) ADR-3/4:** shared values decrypt only post-pin — view guards `pinnedOwnerKey != nil`
  (SharedItemView.swift:121) and the service independently asserts pin==grant key for both decrypt
  (ApprovalRecipientService.swift:102) and sendRequest (:133). Fingerprint: domain-separated SHA-256,
  length-prefixed CanonicalWriter, fixed owner-first ordering over `grant.ownerSigningPubKey` +
  participant key (ApprovalCrypto.swift:175-186) — a MITM-substituted key on either side changes the code
  on at least one screen; sound SAS given the out-of-band compare. Approved payload opens with the
  per-request ephemeral key + `info = requestId+nonce`, nonce echo checked (:180-193).
- **(d) `.task(id:)` liveness:** waiting→approved/terminal→"Request Again" transitions pass through
  `taskKey == "idle"` (`.requesting` and all terminals map to "idle"), so waiting→…→waiting re-fires the
  task; slow-hint Request Again flips phase to `.requesting` → old task cancelled, new task starts on the
  new `.waiting`. Correct by construction — but only once H3 makes cancellation actually terminate the loop.
- **(f) Lifecycle:** ephemeral private key lives only in `RequestCodeModel.pending` (+ the H2 local copy),
  nil'd on every terminal; approved code dropped at window end via timer → `expireDisplayedCode`;
  `Timer.publish(...).autoconnect()` as a view `let` with `onReceive` tears down with the view — no leak;
  lock-on-background destroys the shell → SharedItemView `@State` models (and any displayed code) die.
- **(g) Localization:** all 25 new keys byte-match, including `"About %llds remaining"` (Int → `%lld`) and
  `"Match code: %@"`; every key has a non-empty VI value (scripted check against Localizable.xcstrings).
- **(h)** MainActor-consistent (`@MainActor @Observable` model, MainActor service); iOS 17.6-safe APIs
  (`@Observable`, `ContentUnavailableView`, `.task(id:)` all 17.0+); DS tokens used throughout (Space /
  Radius / Metric / vaultType / themedForeground); `navigationTitle` literal matches codebase convention.
- `completeAcceptance` escrow-before-publish ordering per Validation §3; stateless nil-cursor pulls used
  for both state queries (no delta-cursor misuse — the Phase-3 bug class is absent).

## Recommended Actions (priority order)

1. C1+H1: introduce `SharedZoneRoute { zoneName, ownerName }`, thread the full `CKRecordZone.ID` from
   `acceptedApprovalZones()` through navigation; drop the `String` destination; include ownerName in the
   pin key. Then 2-device QA the full accept→fingerprint→request→approve loop.
2. H2+H3: in `tickWhileWaiting`/`handle`, re-check `Task.isCancelled` + `self.pending` currency after
   every await; stop swallowing sleep cancellation.
3. H4: un-gate the `.vaultShareAccepted` counter bump.
4. M1/M2: build models in `load()`, keyed by `grant.id + fieldId`.

## Metrics
- Compile: green (iOS + macOS, per lead). Tests: 161/161.
- New LOC reviewed: ~520 across 3 new files + 6 modified.
- Localization: 25/25 keys EN+VI verified.

## Unresolved Questions
1. C1 confidence is ~90% from CloudKit shared-DB semantics; only 2-device QA (or a shared-DB integration
   probe) can make it 100%. If it somehow resolves, the zoneName-collision + pin-key point still stands.
2. Should `.vaultShareAccepted` also force `approvalModeEnabled = true` at the coordinator level rather
   than inside the resume path? (Lead/product call — it changes when owner-side gates open for recipients.)
