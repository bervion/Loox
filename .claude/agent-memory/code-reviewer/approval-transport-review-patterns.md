---
name: approval-transport-review-patterns
description: Phase-3 approval CKShare transport review — delta-cursor-as-state-query bug class, CloudKit error-shape gotchas, escrow first-writer-wins decision
metadata:
  type: project
---

Phase-3 approval transport review (2026-07-05) key facts:

- **Delta-cursor-as-state-query bug class**: `ZoneDeltaFetch.pull` with a persisted `ChangeTokenCursor` is delta-only — records consumed never reappear. Any caller wanting "current zone state" (inbox refresh, shared-field read, response poll) must use a stateless nil-cursor full refetch. Found 4 misuse sites in Phase 3 (H1 in report from-code-reviewer-260705-phase3-ckshare-transport-report.md). Re-check this pattern in every future ZoneDeltaFetch adopter.
- **CloudKit create-if-not-exists**: saving a tagless new record with `.ifServerRecordUnchanged` collides as `serverRecordChanged` (correct pattern), but async `modifyRecords` may surface it per-record, promoted top-level, OR as top-level `.partialFailure` — handlers must unwrap `partialErrorsByItemID` too. Empirical shape still unverified (2-device QA pending).
- **Escrow election**: ParticipantEscrowService uses FIRST-writer-wins (create-if-not-exists), deliberately deviating from plan's "last-writer by signed timestamp". Assessed justified: a key the owner already pinned must never be silently replaced. Plan text still says last-writer — lead to reconcile.
- **Why:** these three are the recurring failure modes of this CloudKit control-plane layer; Phase 5/6 UI work will call the same services.
- **How to apply:** when reviewing Phase 5/6 or any sync change, grep ZoneDeltaFetch callers for persisted cursors, and check modifyRecords catch blocks for `.partialFailure` handling. Related: [[vaultify-sync-merge-model]].

Phase-4 share-config UI review (2026-07-05) additions:

- **Sheet-flow lifecycle bug class** (report from-code-reviewer-260705-phase4-share-config-ui-report.md): multi-step CloudKit sheets in this app die on lock-on-background (RootView swaps route → sheet destroyed). Any flow that creates server state early (zone/share) but records locally only on full success leaves orphans: zones litter `ApprovalShareService.ownedZoneNames` and get scanned forever by ApprovalCoordinator. Check: (1) in-flight persistence + resume via `createShare(existingZoneName:)`, (2) manual `Task {}` spawned after `.onDisappear` cancel point → unbounded leaked poll loop (prefer `.task(id:)`), (3) re-entrancy guard on the "create" button.
- **Localization verification recipe**: parse `Vaultify/Localizable.xcstrings` with python, check exact Swift literal as dict key + `localizations.vi.stringUnit.value` non-empty. Interpolations extract to `%@`/`%lld` keys; apostrophe style (curly vs straight) must byte-match. `VaultSheetScaffold` applies `.inAppLocalized` internally, so literal titles are fine. `Text(cond ? "A" : "B")` infers LocalizedStringKey (non-generic init wins) — both branches localize.
- **Passkeys are NOT DynamicFields**: they live in `VaultifyCore/Passkey/`, never in `VaultItem.fields` — field-level share UI can't leak them structurally. guard2 fields carry ciphertext in `.value`, so even a hypothetical inclusion leaks nothing plaintext.

Phase-5 ceremony review (2026-07-05) additions (report from-code-reviewer-260705-phase5-approval-ceremony-report.md):

- **Computed-`.first` sheet binding bug class**: `.sheet(item:)` driven by a Binding whose `get` is `array.first` and whose `set(nil)` clears "the current first" double-clears: finish→clearPending(A)→first becomes B→dismiss writes nil→set clears B (a verified request silently dropped). Fix pattern: explicit `@State presented` decoupled from the inbox; `set(nil)` never mutates the inbox. Check every future item-sheet.
- **Await-gap conditions checks**: in foreground-only ceremonies, `ceremonyConditionsHold` (session unlocked + UIApplication .active) must be re-checked after EVERY await, not just at entry/post-sleep — `lockOnBackground` is a user setting (default true, toggleable), so "lock clears the cache" is not a guaranteed backstop.
- **Repository-after-lock verified**: `session.lock()` → RootView onChange → `repository.clear()` empties caches → `item(id:)` nil; MainActor-serialized so no race. Safe to cite in future reviews.
- **Face ID drives scenePhase .inactive** (RootView comment): any `applicationState == .active` check immediately after `BiometricAuth.authenticate` returns can spuriously fail — consider `!= .background` instead.

Phase-6 recipient UX review (2026-07-05) additions (report from-code-reviewer-260705-phase6-recipient-ux-report.md):

- **Shared-DB zoneID owner-name bug class**: `CKRecordZone.ID(zoneName:)` defaults ownerName to `__defaultOwner__`; in `sharedCloudDatabase` zones are namespaced by the SHARING OWNER's user record name — reconstructing an ID from a bare zoneName (e.g. through a String navigation route) yields zoneNotFound/grantMissing on real cross-account shares. Always thread the full zoneID from `allRecordZones()`. Grep any recipient-side view for `CKRecordZone.ID(zoneName:` with one arg.
- **Cancellation-swallow poll loop**: `while case .waiting = phase { try? await fetch; try? await Task.sleep }` — `try?` swallows CancellationError from BOTH awaits, so a `.task(id:)`-cancelled loop hot-spins on MainActor until an external timeout. Poll loops must check `Task.isCancelled` and must not `try?` the sleep.
- **Local-copy-across-await defeats key-drop supersede**: "drop the ephemeral key by nil'ing self.pending" is void if the poll loop did `guard let pending` (value copy incl. the key) before suspending — handle() after the await must re-validate `self.pending?.requestId == local.requestId && !Task.isCancelled` or a superseded response can render and clobber the new pending. Sibling of the Phase-5 await-gap class.
- **Gated-counter chicken-and-egg**: recipient invalidation counter bump is gated on `approvalModeEnabled`, but the resume path that sets that flag is itself driven by the counter — first-time recipients strand until shell recreation (lock/unlock). Check every "counter gated on setting X" where the observer is what enables X.
- **Duplicate `navigationDestination(for: String.self)`**: `vaultNavigationDestinations()` already registers String→ItemDetailScreen at each tab-stack root; any pushed screen adding its own String destination loses (root-closest wins). New push targets need dedicated route types.

V1.1 invite-link/display-envelope review (2026-07-05) additions (report from-code-reviewer-260705-v11-display-envelope-invite-links-report.md):

- **Public-DB rendezvous GC gap class**: CloudKit has no server TTL and public-DB records are deletable only by their CREATOR — so "recipient deletes after accept" is impossible; U9 delete-after-accept/expiry needs an owner-side sweep or delete-on-revoke. Client-side expiry check alone leaves records resolvable forever.
- **`try?` on deep-link handler**: `onContinueUserActivity { Task { try? accept } }` makes every LocalizedError string dead code — expired/invalid link = zero user feedback. Check any URL-entry path for swallowed errors.
- **User-locked numeric deviation**: reused `ApprovalConfig.opaqueName()` (160-bit) where plan U7 locked 192–256-bit tokens — grep locked numeric specs against the actual constant, don't assume reuse complies.
- **xcstrings key-casing duplicates**: `appString("Shared Item")` minted a new vi-less key beside existing "Shared item" (has vi). Always grep the catalog for case-variant near-duplicates of new literals.
- **Envelope revision is write-only so far**: `SharedDisplayEnvelope.revision` hardcoded 1 at the only publish site; no rename-republish path and recipient never compares revisions — doc comment promises out-of-order protection no code implements.

V1.1 rendezvous-batch review (2026-07-05, report code-review-260705-1716-sharing-v11-rendezvous-batch-report.md):

- **No-op-setter alert binding + async button action**: `.alert(isPresented:)` with computed get and `set { }` re-presents while the Accept Task is in flight (get still true after dismissal) → double-`advance()`/`removeFirst()` drops a queued item that's already in a persisted seen-set. Sibling of the Phase-5 computed-`.first` class; fix is the same explicit `@State presented` + remove-by-id.
- **Persist-dedup-before-surface**: writing the dedup/seen set BEFORE the user acts, while the surfacing queue is shell-`@State`, means lock-on-background (default ON) permanently loses the item. Dedup persistence must ride the user decision.
- **NotificationCenter post in `scene(_:willConnectTo:)`**: fires before SwiftUI `onReceive` subscribers exist → cold-launch deep links silently dropped. Cold-path handoffs need a buffered static + drain-on-`.task`, never fire-and-forget posts.
- **Doc-promised check unimplemented (recurring)**: InviteEnvelope's U7 owner/recipient participant cross-check documented but absent at accept — grep every envelope doc claim against the accept/verify call site (2nd instance after display-envelope revision).
- **Account-scoped CK subscription vs device-scoped state**: public-DB descriptor recordName + subscriptionID are per-Apple-ID; inboxID in UserDefaults is per-device → multi-device arm flaps and strands the other device. Matters once iPad/Mac plan lands.
- **Verified safe patterns to cite**: `.allKeys` save bypasses the oplock (idempotent re-publish); `shareParticipant(forEmailAddress:)` empty-email NSException guarded by button `.disabled(!email.contains("@"))`; xcstrings recipe re-confirmed (all 23 keys incl. `%@` interpolations had VI).

V1.2 first-class shared-items review (2026-07-05, report code-review-260705-1931-sharing-v12-first-class-items-report.md):

- **Repository upsert-fallback defeats projection isolation (CRITICAL class)**: `VaultRepository.update()` line ~207 falls back to `add(item)` when no record matches the id. Any generic row component (`VaultItemRowLink` swipe-trash/favorite) applied to a non-store item (shared projection, future virtual items) PERSISTS it — seals foreign secrets under the local Vault Key, dirty→syncs to iCloud, id collides with the live projection, stored copy decodes `sharedOrigin=nil` → owner UI on someone else's data. Rule: any "first-class in lists" projection must audit EVERY shared row component for repository mutations, and repository mutators need a `shared::`/origin guard. `togglePin/archive/markUsed` are safe (record-lookup guard, no add fallback) — only `update`-family upserts.
- **Lock-wipe checklist for new in-memory secret holders**: RootView lock path clears `repository` only. Any NEW @Observable holding plaintext (SharedItemsProjection.items) must be added to the lock `onChange` — grep for it when a new projection/cache lands. (Erase path had it; lock path didn't.)
- **Burn-before-success (3rd instance of the dedup-ordering class)**: `InviteInboxCoordinator.accept` = `dismiss()` (persistent markSeen) before `acceptShare` → transient CK failure permanently loses the invite. Same family as persist-dedup-before-surface; the burn must ride acceptance SUCCESS, not the tap.
- **Space-filter vs Space-less projections**: shared items merged into Home only when `selectedFolderId==nil`, but `autoSelectSingleSpace()` defaults single-Space users (the onboarding norm) to a folder → feature invisible in the common case; empty-vault gate `repository.items.isEmpty` also ignores projections. Check every default-filter interaction when adding Space-less item classes.
- **Verified safe this round**: grant.id = opaqueName() 20-byte hex → `"grantId|fieldId"` cache key unsplittable by '|'; synthesized Codable omits nil `sharedOrigin` (test-asserted) and `ItemSecret` excludes it; `appString` is nonisolated (Localization.swift:33) so nonisolated buildItem is fine; all 28 new strings VI-translated.
