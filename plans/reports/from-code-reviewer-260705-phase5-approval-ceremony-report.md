# Phase-5 Owner Approval Ceremony — Security Review

Scope: `ApprovalCeremonyService.swift` (new), `ApprovalRequestSheet.swift` (new), diffs in
`ApprovalCoordinator.swift`, `ApprovalVerifier.swift`, `ApprovalCrypto.swift`,
`VaultShellBehaviors.swift`, `AppEnvironment.swift`, `Localizable.xcstrings`.
Spec: plan.md ADR-1/3/6/7 (ADR-6 user-locked), phase-05 acceptance list. Compile green, 161/161 tests.

## Verdict

Core ADR-6 boundary machine is **safe-by-construction against the headline attack** (a counter-N+1
code can never be delivered while local time is in counter N — `issuedAtMs = nowUnixMs` is recomputed
at issue time, so even a late wake generates the then-current code). Nonce semantics are correct.
But there are 3 High findings: seed retained across the wait (ADR-6 letter violation), a missing
foreground re-check after the `verifyInbound` await, and a sheet-binding bug that silently drops the
next pending request.

## HIGH

### H1 — TOTP seed is captured BEFORE the wait and retained across it (ADR-6 letter, user-locked)
`ApprovalCeremonyService.swift:77-83` copies `field` (a `DynamicField` whose `.value` **is** the
otpauth URI containing the base32 secret) into the async frame at step 3, then `:102-104` reads
`field.value` at step 5 — **after** `Task.sleep`. ADR-6: "do NOT read the seed until the boundary, do
NOT cache the seed to survive backgrounding"; phase-05 acceptance: "no seed cached across the wait".
The comment at `:75` ("locate WITHOUT reading it yet") is not what the code does: the seed string
lives in task memory for the whole wait and survives backgrounding until the abort guard runs
(`repository.clear()` on lock clears the repo cache — verified `RootView.swift:43` +
`VaultRepository.swift:26` — but not this local copy).
- Use-after-lock is prevented (post-sleep `ceremonyConditionsHold` at `:95` aborts), so this is
  retention, not use — but it is a verbatim deviation from a user-locked decision.
- **Fix:** pre-wait, extract only `period` in a scoped block and discard the field; after the wait,
  re-run `repository.item(id:)`/field lookup. The re-lookup doubles as a lock check for free
  (locked ⇒ cache cleared ⇒ lookup fails ⇒ fail-closed).

### H2 — No foreground/lock re-check after the `verifyInbound` await (fast path) — ADR-1 gap
`ApprovalCeremonyService.swift:73` awaits CloudKit (seconds). `ceremonyConditionsHold` is checked
before it (`:69`) and after the sleep (`:95`), but **not between verifyInbound and ISSUE_NOW on the
fast path**. With `lockOnBackground = false` (real user setting, `SettingsStore.swift:51`, default
true but toggleable — `MacSettingsView.swift:208`), backgrounding during the verify await leaves the
session unlocked and the repo cache populated; the CloudKit continuation can resume in the background
grace window and generate + send the code while backgrounded — violating ADR-1 foreground-only
issuance. With the default setting the lock clears the cache and step 3 fails safe.
- **Fix:** `guard ceremonyConditionsHold` immediately after `verifyInbound` (and after any await).

### H3 — `pendingApprovalBinding.set(nil)` clears the WRONG request (silently drops the next one)
`VaultShellBehaviors.swift` (new `pendingApprovalBinding`): sequence with two pending requests A, B —
Done tapped → `onFinished()` → `clearPending(A)` → `.first` becomes **B** → `dismiss()` →
`.sheet(item:)` writes nil to the binding → `set(nil)` sees `newValue == nil, current = B` →
`clearPending(B)`. B — an already display-verified, live request — is silently dropped from the
inbox with no response sent; the requester waits until timeout. It only reappears on the next
`refreshOwnerRequests()` (next foreground/onAppear), which may be minutes away. Bonus chaos: because
`get` is computed from the array, after `clearPending(A)` the sheet content swaps to B *before*
dismissal, firing `onAppear → resetState()` mid-teardown.
- **Fix:** decouple presentation from the inbox: hold `@State private var presented:
  PendingOwnerRequest?`, seed it from `pendingOwnerRequests.first` via `onChange` only when nothing
  is presented; `set(nil)` just clears the presented state; `clearPending` only from `onFinished`.

## MEDIUM

### M1 — Inbox refresh while the sheet is open swaps the sheet's request mid-ceremony
`ApprovalCoordinator.refreshOwnerRequests()` (`:92`) wholesale-replaces `pendingOwnerRequests`
(sorted newest-first). A push arriving mid-ceremony re-sorts, `.first` changes identity, and
`.sheet(item:)` replaces the content with a *different* request while `ceremony.state` still belongs
to the old one (and `onAppear → resetState()` stomps a busy state). Same root cause / same fix as H3.

### M2 — "Close" toolbar button bypasses `interactiveDismissDisabled` while busy
`ApprovalRequestSheet.swift:28` — `SheetDismissButton("Close")` calls `dismiss()` unconditionally
(`VaultSheetScaffold.swift:126`); `interactiveDismissDisabled(isBusy)` only blocks the swipe.
Closing during `.waitingForFreshWindow` leaves the ceremony Task running headless (it holds env
service refs on MainActor): it will complete and send the code with no UI, while the dismissal also
routes through the H3 `set(nil)` path. Post-Face-ID consent makes silent completion arguable, but
UI state and inbox state diverge. **Fix:** hide/disable the Close button while `isBusy` (and decide
explicitly: dismissal-while-waiting = continue or abort — then implement that).

### M3 — Spurious abort risk right after Face ID (applicationState == .inactive)
`RootView.swift:58` documents that the Face ID prompt drives scenePhase `.inactive`. If
`BiometricAuth.authenticate` returns before the app is re-activated, `ceremonyConditionsHold`
(`ApprovalCeremonyService.swift:50`, requires `.active`) can false-negative → `abort()` sends a
signed `interrupted` for a ceremony the user just approved. Timing-dependent; needs device QA.
Consider rejecting only `.background` (ADR-1's threat is backgrounding — `.inactive` is on-screen),
or a short re-poll before aborting.

### M4 — Late wake can issue with remaining < freshness threshold (ADR-6 policy, narrow)
After the sleep there is no `canIssueNow` re-check (`:96-101`). `Task.sleep(for:)` runs on the
continuous clock; a suspension ≥ ~12s past the boundary (background + return, `lockOnBackground`
off) issues a now-current code with < 18s remaining — never a future code (safe), but below the
policy budget. **Fix:** make step 4 a `while !policy.canIssueNow(...) { wait; guard conditions }`
loop — also subsumes the tolerance edge.

### M5 — "Close" missing Vietnamese translation
`Localizable.xcstrings` key `"Close"` (pre-existing, auto-comment "Generator tab") has **no `vi`
value**; Phase 5 now renders it twice (`ApprovalRequestSheet.swift:28` and `:153`). VI users see
English "Close" on the failure screen of a security ceremony. Mandatory-rule violation per CLAUDE.md.
All 17 genuinely new keys verified byte-exact with VI, including the interpolated
`"Someone you shared with is asking for the current verification code for %@."`.

## LOW / INFORMATIONAL

- **L1** Post-burn failure paths (`:80`, `:105` — item deleted, generator nil) send **no response**:
  nonce already consumed, requester hangs until the 20s timeout and the request is permanently
  unapprovable. Consider sending a signed reject/interrupted so B stops waiting.
- **L2** `error.localizedDescription` (`:128`, `:141`) surfaces raw CloudKit error prose in the
  ceremony UI (unlocalized, internal detail). Map to a generic localized failure line.
- **L3** `reject()` has no re-entrancy guard/busy state: double-tap → duplicate response records
  (opaque record names, `ApprovalRecordMapping.swift:56`, so no collision) and a late error can
  overwrite `.finished(.rejected)` with `.failed`.
- **L4** `"ic_shield_none"` raw literal (`ApprovalRequestSheet.swift:120`) — use `Icons.shieldAlert`.
- **L5** `abort()`'s interrupted response is fire-and-forget from a possibly-suspending process —
  may never reach the server; B's 20s timeout is the real backstop. Acceptable V1; document.
- **L6** Wall-clock only (`nowUnixMs`); ADR-7/H8 asks monotonic for internal durations + jump
  detection. A backward clock jump mid-wait yields a stale-counter code the RP rejects
  (fail-closed). Fine for V1; keep on the Phase-8 skew-test list.
- **L7** Payload hygiene: JSON buffer zeroed (`:116-117`) but the `code` String is immutable/copied
  — consistent with the app's existing plaintext TOTP display; no regression. Seal binds
  `requestId + nonce` to the ephemeral key per ADR-3 (`:118-120`) — correct contract.

## Verified-correct (checked, not assumed)

- **ADR-6 headline invariant:** boundary = `periodEndUnixMs(now)`; `Task.sleep` is at-least; code
  generated from fresh `nowUnixMs` at issue → a future-period code is unreachable on every path.
  Window math (`ApprovalModels.swift:158-176`) is pure integer Unix arithmetic, period-0 fail-closed.
- **Nonce semantics:** `PreviewNonceStore` referenced ONLY in the coordinator display path (grep of
  all `verifyRequest` callers); approve path uses `verifyInbound` → `CloudKitNonceStore` with
  atomic create-if-not-exists and correct `partialFailure` unwrap (`ApprovalShareService.swift:237-273`)
  → two-device double-approve: second fails at nonce. Verify-before-show AND fresh authoritative
  verify at approve both present, per spec.
- **Repository-after-lock (the key question):** `session.lock()` → `RootView.onChange(session.state)`
  → `repository.clear()` empties `items/trashed/archived` → `item(id:)`
  (`VaultRepository+Folders.swift:224`) returns nil → a locked vault cannot yield the seed from the
  cache. Both writes are MainActor-serialized with the ceremony, so no read/clear race.
- Stateless nil-cursor refetch used for the inbox (Phase-3 delta-cursor lesson applied).
- Policy constants named (`TOTPIssuancePolicy.v1`, 18s = 5+10+3), no magic numbers.
- DS compliance otherwise clean (Space/Radius/Metric/vaultType/themedForeground/PolarisIcon,
  `.vaultCode` for the match code); iOS 17.6-safe APIs throughout; `@MainActor @Observable` correct.
- `TrustFingerprint.requestCode`: domain-separated SHA-256, canonical length-prefixed input, 5-digit
  derivation sound (modulo bias immaterial for a human match code).

## Recommended actions (priority order)

1. H3/M1: explicit presented-request state; `set(nil)` must never touch the inbox.
2. H1: scope the pre-wait lookup to period only; re-fetch item/field after the wait.
3. H2/M4: conditions guard after every await + `while !canIssueNow` loop.
4. M2: disable Close while busy; M5: add VI for "Close".
5. M3: device-QA the post-Face-ID `.inactive` window; relax check to `!= .background` if it flakes.

## Unresolved questions

- Intended semantics when the owner closes the sheet during `WAITING_FOR_FRESH_WINDOW`: continue
  headless (current behavior) or abort-with-interrupted? Needs a product call before fixing M2.
- Should a post-nonce-burn internal failure (L1) send `interrupted` so B stops waiting? Recommend
  yes; confirm against Phase-6 recipient state machine.
