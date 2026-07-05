# Code Review — Phase 4 Owner Share-Config UI (feat/approval-mode-sharing, uncommitted)

## Scope
- Files: ShareAccessSheet.swift (268), FieldCapabilityRow.swift (61), TrustFingerprintView.swift (41), SharingStore.swift (57), ItemDetailScreen.swift (+9), AppEnvironment.swift (+2), Localizable.xcstrings (+400)
- Compile: iOS+macOS green, 161/161 tests (given)
- Focus: plan compliance (phase-04), localization byte-match, DS, flow/state, concurrency, secret hygiene

## Overall Assessment
Security posture is solid: type-enforced capabilities, guard2/fileRef excluded from both UI and sharedValues, fingerprint strictly before publishGrant, fail-closed gates, no secret in SharingStore/logs, no bearer URL semantics. Localization is complete and byte-exact (script-verified). The weaknesses are all in flow *lifecycle*: interrupted flows leak zones + an unbounded poll task, and there is no in-flight persistence/resume despite the service supporting it.

## Critical Issues
None. No secret leakage path found; ADR-2/ADR-4 invariants hold.

## High Priority

### H1 — Orphan infinite poll task when sheet dismissed during `.creating`
`ShareAccessSheet.swift:44` (`.onDisappear { pollTask?.cancel() }`) fires at dismissal; if the user swipe-dismisses while `createShare()` is in flight (unstructured `Task` at :200), `startProfilePolling` (:106→:112-126) runs *after* onDisappear — pollTask is assigned on an uninstalled view and **nothing ever cancels it**. Result: a 3s CloudKit `record(for:)` loop runs until the profile appears or the app quits, plus @State writes to a removed view. Fix: guard a `didDisappear` flag (or `guard case .waiting = step`) before spawning, or drive polling with `.task(id: stepKey)` so SwiftUI owns cancellation.

### H2 — Interrupted flow leaves orphan zones; retry litters a new zone per attempt; no resume
- Any exit after `createShare` success (failure at publish, swipe-dismiss, or **lock-on-background** — `RootView.swift:79-83` swaps route to `.locked` and destroys the sheet; the waiting step explicitly asks the user to keep the screen open for minutes, so device sleep/app-switch is the *expected* path) leaves: zone + CKShare + subscription created, grant unpublished, **nothing in SharingStore**.
- Retry path: `.failed → "Try Again" → .config → createShare()` (:77, :100) never passes `existingZoneName` even though `ApprovalShareService.createShare(recipientEmail:existingZoneName:)` exists precisely for reuse (`ApprovalShareService.swift:52,58`). Each attempt mints a fresh opaque zone.
- Every littered zone is registered in `ownedZoneNames` (`ApprovalShareService.swift:75`) and scanned forever by `ApprovalCoordinator.swift:60`.
- Recipient can accept a dead invite and publish a profile into a zone that will never be granted → permanently stuck on their side with zero owner-side visibility.
Fix: persist in-flight record at createShare success (`SharingStore.upsert(fingerprintConfirmed: false)`), resume via `existingZoneName` on re-entry, surface/clean abandoned zones (or delete zone on explicit cancel).

## Medium Priority

### M1 — "Pending" state is dead code
`SharingStore.upsert` is only called with `fingerprintConfirmed: true` (`ShareAccessSheet.swift:146-149`), so the `Active/Pending` display (:187) can never show Pending. Symptom of H2 — the store never sees in-flight shares.

### M2 — Double-tap "Create Share" creates two zones
`createShare()` (:100) has no `guard case .config = step` re-entrancy guard; two rapid taps queue two Tasks before the first sets `.creating` → two zones, two shares. (`confirmFingerprintAndPublish` :129 IS correctly guarded — mirror that.)

### M3 — Raw `error.localizedDescription` shown to user, unlocalized
:108, :152. `ApprovalShareService.Failure` doesn't conform to `LocalizedError` → user sees "The operation couldn't be completed. (…Failure error 0.)"; CKError text is English/internal. Breaks the EN+VI mandate on the failure screen. Map Failure/CKError cases to catalog strings.

### M4 — Poll loop: no timeout/backoff; keychain read per iteration
:112-126. `try?` swallows `requestRateLimited` and re-hits CloudKit every 3s indefinitely; `DeviceSigningIdentity.loadOrCreate()` (:117) is a keychain fetch per tick — hoist it out of the loop; add backoff/timeout.

### M5 — `approvalModeEnabled = true` set before flow completes
:104. Abandoned flow leaves global approval listening enabled with zero completed shares (compounds H2 zone scanning). If intentionally early (to receive the accept push), it needs cleanup on abandonment; otherwise move after publish success.

## Low Priority
- L1 `.blocked` is a dead-end: `enter()` runs once via `.task`; after granting notifications in Settings and returning, no re-check and no "Open Settings" button (:255-267).
- L2 `confirmFingerprintAndPublish` silently no-ops if `item == nil` (:129) — button appears broken; show a failure state.
- L3 DS nits: hardcoded `spacing: 2` (`FieldCapabilityRow.swift:20` — use a Space token); raw `"ic_shield_check_mark"` in 3 places instead of existing `Icons.shield` (`PolarisIcon.swift:56`); bare `Button("Try Again")` (:77) unstyled, hit target likely <44pt; `.vaultCode(size: 28)` hardcoded (`TrustFingerprintView.swift:24`, precedent exists in LargeTypeView).
- L4 `recipientEmail` stored untrimmed as `recipientLabel` (:148) while the service trims; sharing the same item to the same email twice double-counts "Shared with N".
- L5 `epoch: 1` hardcoded (:145) — correct for fresh-zone V1, must become dynamic when Phase-7 revocation/capability edit lands.

## Verified Good (evidence)
- **Localization**: all 25 new keys + reused `Off`/`Try Again`/`Done` script-verified present with translated `vi`; byte-exact incl. curly `aren’t` vs straight `there's/can't/you'll/you're`; interpolation keys `Ask %@ to read…` and `Shared with %lld` match extraction exactly. `VaultSheetScaffold` applies `.inAppLocalized` internally (`VaultSheetScaffold.swift:88`). Ternary `Text(cond ? "A" : "B")` resolves to `LocalizedStringKey` (non-generic init preferred) and both branch literals are catalog keys.
- **Least exposure**: all fields default `.none` (`enter()` :91-96, binding fallback :215); "Create Share" disabled until ≥1 capability granted + `@` in email (:206).
- **Type-enforced constraints**: TOTP→Off/Ask each time, value→Off/Shared only (`FieldCapabilityRow.swift:39-59`; enums make invalid combos unrepresentable, `ApprovalModels.swift:15-32`).
- **guard2/fileRef**: picker hidden + row disabled (`FieldCapabilityRow.swift:12-13`); guard2 excluded from `sharedValues` (:133-137); service re-guards `isSharedValue` (`ApprovalShareService.swift:136`). guard2 `value` is ciphertext anyway (`DynamicField.swift:13`).
- **Fingerprint before grant**: step order waiting→fingerprint→publish; confirm handler guarded (:128-131).
- **Gates fail-closed**: on entry (:86-89) AND re-checked inside `createShare` (`ApprovalShareService.swift:55`).
- **Recipient by email lookup**: `shareParticipant(forEmailAddress:)` (iOS 15+, fine at 17.6); no `UICloudSharingController`.
- **Concurrency**: project-wide MainActor default; `Task {}` inherits isolation → @State mutations MainActor-safe; poll cancelled on disappear (modulo H1 race).
- **Field surface (check f)**: `VaultItem.fields` is the single real field list — login username/password live there (`ItemCategory.swift:49-59` template; websites/TOTP appended by editor), so the sheet iterates the true per-field surface. Passkeys live outside `fields` (`VaultifyCore/Passkey/`) → structurally unshareable; plan's "disabled passkey row" is moot (safer than planned).
- **No leakage**: zero print/Logger in new files; SharingStore holds itemId/zoneName/email/grantId only, device-local UserDefaults (M2-compliant).

## Recommended Actions (priority order)
1. Fix H1 poll-task leak (drive polling via `.task(id:)` or dismissal flag).
2. Fix H2: persist in-flight share at createShare success; reuse `existingZoneName` on retry; define abandonment cleanup. (M1 falls out of this.)
3. Add re-entrancy guard to `createShare` (M2).
4. Localized error mapping for the failed step (M3).
5. Backoff + hoisted identity in poll loop (M4); decide/document early `approvalModeEnabled` (M5).
6. L1-L5 as polish before PR.

## Unresolved Questions
- Is `approvalModeEnabled = true` at createShare intentional (needed to receive the recipient-accept push while waiting)? If yes, document + add abandonment cleanup.
- Phase-7 scope: does revocation/management own orphan-zone GC, or must Phase 4 avoid creating them at all?
