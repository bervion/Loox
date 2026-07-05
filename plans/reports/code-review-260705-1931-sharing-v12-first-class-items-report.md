# Code Review — Sharing V1.2: Shared Items First-Class UX

Branch: `feat/sharing-v12-shared-items-ux` (9 commits vs main)
Plan: `plans/260705-1921-shared-items-first-class-ux/plan.md` (V1–V7)
Compile: **BUILD SUCCEEDED** (tuist generate + xcodebuild, generic iOS Simulator; 0 warnings in changed files)
Localization audit: all 28 new/changed user-facing strings present with translated VI values (JSON-verified).

## Critical

### C1 — Shared projections CAN enter VaultStore via swipe/context actions (violates invariants 1, 2, 4)
- `Vaultify/Features/Sharing/SharedWithMeScreen.swift:25` and `Vaultify/Features/Search/SearchScreen.swift:56` render shared items with `VaultItemRowLink`.
- `VaultItemRowLink.swift:20-42` exposes swipe-trash (`repository.moveToTrash`), swipe-favorite (`repository.toggleFavorite`), context-menu pin/archive on EVERY row — including `shared::` projections.
- `Vaultify/Data/Repositories/VaultRepository.swift:207`: `update()` has an upsert fallback — `guard let record = try record(id: item.id) else { return try add(item) }`. `moveToTrash`/`toggleFavorite` on a projected item → no record found → **`add(item)` persists the shared item into the local vault store**.

Failure scenario: recipient swipes a shared row in Search (or Shared with Me) → the shared secret value is sealed under the recipient's Vault Key, inserted with id `shared::owner::zone`, marked `dirty` → **syncs to the recipient's iCloud**, survives revocation (defeats "revoke = disappears"), feeds AutoFill/Watchtower/export/Trash. Worse: the stored copy decodes with `sharedOrigin == nil` and `ItemDetailScreen.item` (line 23) resolves `repository` first → the item now presents the full **owner/editable UI** for someone else's data, and its id collides with the still-live projection (duplicate `ForEach` ids in Home `allItems`).

Fix (both layers):
1. UI: in `VaultItemRowLink`, gate swipe actions + context menu on `item.sharedOrigin == nil` (keep only the NavigationLink for shared rows; optionally offer "Leave Share" swipe).
2. Defense-in-depth: `VaultRepository.update/add/moveToTrash/toggleFavorite` early-return (or throw) when `item.sharedOrigin != nil || item.id.hasPrefix("shared::")`. `togglePin`/`archive`/`markUsed` are already safe no-ops (record-lookup guard, no add fallback).

## High

### H1 — Lock does not clear decrypted shared secrets from memory
- `Vaultify/App/RootView.swift:43` clears `repository` on lock; `SharedItemsProjection.wipe()` is only called from `AppEnvironment.eraseEverything()` (`AppEnvironment.swift:106`).
- Projected items hold **plaintext shared field values** (and grants) in `sharedItems.items` for the whole process lifetime across lock/unlock — deviating from the app's lock privacy model (repo cleared on background lock).
- Fix: wipe (or clear `items`/`grants`, optionally keeping `requestModels` is NOT needed — in-flight ephemeral keys are moot once locked) in the same `onChange` branch as `repository.clear()`. The shell `.task(id: recipientChangeCounter)` re-refreshes after unlock (`VaultShellBehaviors.swift:84`).

### H2 — Invite permanently burned BEFORE acceptance succeeds (lost-invite on transient failure)
- `Vaultify/Services/Sharing/InviteInboxCoordinator.swift:56-65`: `accept()` calls `dismiss(invite)` → `inbox.markSeen` (persistent, "never prompt again across relaunches", `InviteInboxService.swift:161-167`) **before** `links.acceptShare(...)`.
- Failure scenario: user taps Accept while offline / CK throttled → `acceptShare` throws → error alert, but the invite is gone from the queue AND the dedup id is burned → reconcile will never resurface it. Owner must re-create the share. This contradicts `InviteInboxService.reconcile`'s own contract comment (lines 125-127: discovery must not swallow invites; the burn is supposed to represent a *completed* response).
- Note: the ordering existed on main's `InviteInboxBehaviors.finish`, but this branch re-implements it in the new coordinator and adds a second surface (NotificationsScreen row Accept) — worth fixing now.
- Fix: remove from `pendingInvites` immediately (UI), but `markSeen` only after `acceptShare` returns; on throw, re-insert the envelope into the queue.

## Medium

### M1 — Shared items invisible on Home for the common single-Space user; stale alert copy
- `HomeScreen.swift:45`: shared items merge into `allItems` only when `selectedFolderId == nil`, but `autoSelectSingleSpace()` (lines 62-65) defaults single-Space vaults (the onboarding-seeded norm) to that Space → shared items never appear on Home unless the user manually picks "All Spaces".
- `HomeScreen.swift:73`: `repository.items.isEmpty` shows the empty-vault state even when shared items exist.
- `InviteInboxBehaviors.swift:35` alert copy: "Accept to see it in \"Shared with Me\" on Home" — the Shared-with-Me row now lives on the **Items** tab (`ItemsScreen.swift:98`), not Home.
- Fix: include shared items regardless of Space filter (they're Space-less; or exempt them from the filter), treat `!sharedItems.items.isEmpty` as non-empty vault, and update the alert copy (EN+VI).

### M2 — Invite alert/queue races (InviteInboxBehaviors + NotificationsScreen)
1. `finish(accept:)`: `coordinator.accept` removes the invite from the queue → `onChange(pendingInvites.first)` fires `presentNextIfIdle()` → the NEXT invite alert presents while the previous accept is still in flight. If that accept then fails, `acceptError` is set while the invite alert is up — two competing `.alert` modifiers on the same content; the error alert may silently fail to present, and `acceptError != nil` then blocks `presentNextIfIdle()` for the rest of the session (guard at `InviteInboxBehaviors.swift:54`).
2. Suppression (`alertsSuppressed`) only prevents NEW presentations — navigating to NotificationsScreen while the shell alert is already up shows the same invite twice (alert over the list). Double-response is benign (`markSeen` dedups) but `acceptShare` can run twice.
3. `NotificationsScreen.onDisappear` lifts suppression but nothing calls `presentNextIfIdle()` → remaining invites stay dormant until the next scene-phase/push/queue change.
- Fix: don't present the next invite until no accept is in flight (track it); on NotificationsScreen appear, also clear `presentedInvite`; call a coordinator-driven re-present on unsuppress.

### M3 — Every shared value renders as a password
- `SharedItemsProjection.buildItem` (lines 143-144): all shared values → `kind: .password, protected: true, label: "Shared value"`. A shared username/email gets a **password-strength badge** (`DetailFieldRow.swift:96-98` triggers on `kind == .password`) and spoiler concealment, plus all rows share one generic label. Misleading meter on non-password data.
- Fix: owner side knows the field kind — carry a display kind (or at least label) in the sealed shared-field blob or display envelope; short term, suppress the strength badge when `item.sharedOrigin != nil`.

### M4 — Dead "Protect…" affordance on shared read-only fields
- Shared branch uses `DetailFieldRow(field:)` with default no-op `onChange` (`ItemDetailScreen.swift:281`), but the row menu still offers "Protect…" (`DetailFieldRow.swift:132-135`) → user completes the ProtectFieldSheet ceremony and nothing happens. Hide it (and "Open Website" is fine) when handlers are no-ops — e.g. add a `readOnly` flag.

## Low

- **L1** Dead placeholder fields: `buildItem` appends empty `.totp` fields (SharedItemsProjection.swift:146-150) but `fieldsCard` filters `!$0.isEmpty` and derives Request rows from grant capabilities instead (ItemDetailScreen.swift:265, 272-275). Remove the placeholders or use them.
- **L2** Website field gets a fresh UUID each refresh → projected `VaultItem`s are never `Equatable`-equal across refreshes → needless row invalidation. Give it a stable id (e.g. `"website"`).
- **L3** Owner toolbar Share button + Sharing-section rows open `ShareAccessSheet` for **trashed** items (ItemDetailScreen.swift:63-69) — no `isTrashed` gate. Decide: acceptable per V5, or gate the button like Archive is gated.
- **L4** Bell badge shows "9" for counts >9 (`min(notificationCount, 9)`, HomeHeaderBar) — consider "9+".
- **L5** `recipientDeviceId` computed var writes UserDefaults during view body (SharedItemsProjection.swift:172-178) — make it a `let` resolved in init.
- **L6** `safetyCode` `.task(id: itemID)` doesn't re-run if the projection populates after first evaluation (ItemDetailScreen.swift:135-139) — key it on `item?.sharedOrigin` too.
- **L7** ShareAccessSheet GC deletes the stale drop before the replacement drop is known to succeed (ShareAccessSheet.swift:204-207) — offline re-drop loses the old auto-invite (pretty-link fallback remains). Documented best-effort; acceptable.

## Invariant verification (MUST-HOLD)

| # | Invariant | Verdict |
|---|-----------|---------|
| 1 | Projections never enter VaultStore | **VIOLATED via C1** (swipe path). All read surfaces clean: Watchtower `PasswordAudit.analyze(repository.items)` (HomeScreen.swift:55), TOTP scroller/favorites/attention = repository-only, AutoFill/export/sync read store, `totpField` requires non-empty value so placeholders can't leak. Only intended surfaces reference `env.sharedItems` (grep-verified). |
| 2 | `shared::` id never persisted/mutated | **VIOLATED via C1** (`update`→`add` fallback). Detail shared branch clean: `DetailFieldRow(field:)` defaults are no-ops (DetailFieldRow.swift:11-13); `togglePin/archive/markUsed` guard on record lookup (safe no-ops). Pin/favorite controls hidden for shared (ItemDetailScreen.swift:174-207). |
| 3 | RequestCodeModel identity across refresh | **HOLDS.** Keyed `"\(grant.id)\|\(fieldId)"`; `grant.id = ApprovalConfig.opaqueName()` = 20-byte hex (ApprovalConfig.swift:71-73), no `\|` possible; filter parse `split(separator:"\|")[0]` safe; models retained for live grant ids, dropped on rotation (SharedItemsProjection.swift:124-127). Transient-error branch preserves the old grant/model. |
| 4 | No edit affordance for shared items | **VIOLATED via C1** (swipe/context on VaultItemRowLink). Detail toolbar/trash-card/header correctly branch on `sharedOrigin`. Home rows are plain Buttons (safe). |
| 5 | Alert/queue lifecycle | H2 (lost invite) + M2 (races). No stuck-suppressed path found (onDisappear reliable for pop/teardown). |
| 6 | MainActor/Observable correctness | **HOLDS.** `appString` is `nonisolated` (VaultifyCore/Localization.swift:33); `buildItem` `nonisolated static`; `items` is observed `private(set)` on `@Observable` (re-render verified by reassignment on every refresh); `@ObservationIgnored` on caches is fine because `items` reassignment drives invalidation. `refreshing` lacks `@ObservationIgnored` — harmless (no view reads it). |
| 7 | Localization EN+VI | **HOLDS.** 28 strings audited via JSON — all `vi` state `translated` (incl. "Code approval requested", "Share Website Link", "Shared", chip/toggle strings, Notifications screen, leave dialog, safety code). |
| 8 | Owner single share button | Works; trashed-item gap = L3. Sharing-section tap → same sheet (consistent manage semantics per V5). |
| 9 | `sharedOrigin` Codable | **HOLDS.** Synthesized optional → `encodeIfPresent` omits nil (test `testOwnedItemEncodingUnchangedBySharedOriginAddition` asserts); `ItemSecret` excludes origin by construction (test asserts); sync/backup seal `ItemSecret` only; `SharingStore`/CK codecs untouched. |

## Positive observations

- Projection design is genuinely storage-free and single-flight; transient-error branch keeps per-zone previous state (no flicker-empty) while zoneNotFound/userDeletedZone correctly vanish revoked items.
- `republishDisplayEnvelope` correctly reseals only presentation metadata, leaves the signed grant untouched, and the recipient side gates on the pinned owner key + grantId match.
- Coordinator extraction (queue as single source for alert + inbox screen) is the right shape; `markSeen`-on-response (not discovery) contract is well documented.
- Codable/back-compat handled with tests, not hope.
- FieldCapabilityRow Toggle conversion is clean and adds the missing "what ON means" footnote.

## Recommended actions (priority order)

1. **C1**: gate `VaultItemRowLink` actions on `sharedOrigin == nil` + repository guard against `shared::`/origin items. Add a regression test: `repository.update(sharedItem)` must not insert.
2. **H1**: wipe projection on lock in `RootView.onChange(session.state)`.
3. **H2**: reorder burn-after-success in `InviteInboxCoordinator.accept`; re-enqueue on failure.
4. **M1**: Home merge irrespective of Space filter + empty-state + alert copy (EN+VI).
5. **M2/M3/M4**: alert race hardening; suppress strength badge on shared; hide Protect… for read-only rows.

## Metrics
- Compile: pass (0 warnings in changed files, 25 total pre-existing)
- New tests: 4 (SharedItemsProjectionTests) — cover mapping + Codable purity; no coverage for requestModel retention/rotation or coordinator queue semantics
- Localization: 28/28 strings VI-translated

## Unresolved questions
1. L3: is sharing a trashed item acceptable (V5), or should the share button be gated on `!isTrashed`?
2. M3: should the shared-field kind (username vs password) travel in the display envelope, or is generic "Shared value" the intended V1.2 scope?
3. Is the Home behavior for single-Space users (shared items hidden until "All Spaces" selected) intended per V2, or should Space-less shared items bypass the filter?
