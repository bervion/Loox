# Phase A2 — SharingStore identity + Space-share reconciler + safelist

## Executed Phase
- Phase: A2 (Family full-group sharing — store + pure reconciler + safelist + tests)
- Plan: `plans/260715-1848-family-devices-crypto/family-group-transport.md` (A0-4, A0-6, design items 6-7)
- Status: completed

## Files Modified

| File | Why |
|---|---|
| `Vaultify/Features/Sharing/SharingStore.swift` | Part 1. `ItemShareRecord.id` → composite `"\(zoneName)::\(itemId)"`; `upsert` matches on `(zoneName, itemId)` instead of wiping every sibling share in the zone; new `remove(zoneName:itemId:)` (per-item); `remove(zoneName:)` kept (whole-member revoke, doc updated); `updateStatus` now advances every item-share in the zone together (was: only the first match) since the fingerprint ceremony is per-zone/per-member, not per-item; new `shares(forRecipient:)`. |

## Files Created

| File | Why |
|---|---|
| `VaultifyCore/Sharing/SpaceShareSafelist.swift` | Part 2. `SpaceShareSafelist.shareableFields(for:)` — A0-6 field-instance safelist: `.login` items only, kind ∈ {username, password, url, email}, not `protected`, not `guard2`, plus a `SecretGuard.isProtected(value)` defense-in-depth check mirroring `WebExtensionReader.releasable`. |
| `VaultifyCore/Sharing/SpaceShareMembershipReconciler.swift` | Part 3. `desired`/`published`/`plan` — the pure desired−published diff engine (A0-4/DEC-FAM-01 live membership). Computes `Ops { creates, updates, revokes }`; no CloudKit, no execution (A3's job). |
| `VaultifyTests/SharingStoreIdentityTests.swift` | Part 1 tests: composite id, legacy JSON decode, flag-OFF behavioral parity, sibling upsert/remove/status-advance, `shares(forRecipient:)`. |
| `VaultifyTests/SpaceShareSafelistTests.swift` | Part 2 tests: each eligible/ineligible kind, protected, guard2, SecretGuard-tag defense-in-depth, fileRef, mixed item, every non-login category, empty item, field-id keying. |
| `VaultifyTests/SpaceShareMembershipReconcilerTests.swift` | Part 3 tests: create/update/revoke/no-op cases, cap-grows/shrinks (field added, field removed, field became protected), item→ineligible, empty Space, determinism across repeated calls, resumability (apply-then-replan → empty). |

## Tasks Completed
- [x] Part 1 — `ItemShareRecord` per-(zone,item) identity; `upsert`/`remove`/`updateStatus` reworked; `remove(zoneName:itemId:)` + `shares(forRecipient:)` added; back-compat pinned by test.
- [x] Part 2 — `SpaceShareSafelist.shareableFields(for:)`, pure, exhaustively tested.
- [x] Part 3 — `SpaceShareMembershipReconciler.desired/published/plan`, pure, idempotent + resumable, exhaustively tested.
- [x] No CloudKit execution, no UI, no crypto change.
- [x] `tuist generate` + full compile (app + VaultifyAutoFill + VaultifySafari, one scheme build).

## Tests Status
- Type check / compile: **PASS** (see log tail below)
- Unit tests (new, isolated run): **37/37 PASS** — `SharingStoreIdentityTests` (10), `SpaceShareMembershipReconcilerTests` (15), `SpaceShareSafelistTests` (12)
- Full `VaultifyTests` target (regression check, includes `ShareLifecycleStatusTests`, `FamilyShareTransportTests`, `ApprovalKernelTests`, `SharedGrantComposerTests`, `SharedItemsProjectionTests`, `WebExtensionReaderTests`, everything else): **765/765 PASS, 0 failures**

### Compile log tail
```
CreateUniversalBinary .../Vaultify.app/Vaultify normal arm64\ x86_64 ...
Copy .../Vaultify.app/PlugIns/VaultifyAutoFill.appex ...
Copy .../Vaultify.app/PlugIns/VaultifySafari.appex ...
CopySwiftLibs .../Vaultify.app ...
ProcessInfoPlistFile .../Vaultify.app/Info.plist ...
ExtractAppIntentsMetadata ...
ValidateEmbeddedBinary .../VaultifySafari.appex ...
ValidateEmbeddedBinary .../VaultifyAutoFill.appex ...
Validate .../Vaultify.app ...
** BUILD SUCCEEDED **
```
Zero warnings attributable to the new/changed files (`grep warning: ` against the log only surfaces two pre-existing, unrelated `appintentsmetadataprocessor` notices).

### Test totals
```
Test Suite 'SharingStoreIdentityTests' passed — Executed 10 tests, with 0 failures
Test Suite 'SpaceShareMembershipReconcilerTests' passed — Executed 15 tests, with 0 failures
Test Suite 'SpaceShareSafelistTests' passed — Executed 12 tests, with 0 failures
...
Test Suite 'VaultifyTests.xctest' passed — Executed 765 tests, with 0 failures (0 unexpected) in 24.495s
** TEST SUCCEEDED **
```

## How SharingStore back-compat is preserved
1. **`id` was never a `Codable` key.** `var id: String { zoneName }` was a *computed* property (no storage), so Swift's synthesized `Codable` never encoded it in the first place. Changing the formula to `"\(zoneName)::\(itemId)"` has zero effect on JSON encode/decode — a legacy blob (no `id` key, one record per zone) decodes exactly as before; `id` just recomputes fresh from the two stored fields. Pinned by `testLegacyJSONWithoutAnIdFieldStillDecodes`.
2. **Every existing call site keys off `zoneName`** (`ShareAccessSheet`, `ShareRecipientDetailSheet`, `ShareResumeStepperSheet`, `FamilyScreen`, `NotificationsScreen`, `VaultShellBehaviors`, `VaultItemRow`, `ItemDetailScreen`, `ItemEditorScreen`) — verified by grep, none construct or compare `ItemShareRecord.id` directly, so widening it to a composite string changes nothing observable there.
3. **`upsert`**: today's only caller pattern (`ShareAccessSheet`) always re-upserts the *same* `(zoneName, itemId)` pair across the pending → confirmed transition (one zone == one item, `FamilyShareTransport.perGrantEnabled == false`). Matching on the pair instead of `zoneName` alone is therefore byte-for-byte identical in that shape, while fixing the sibling-wipe bug for when a zone holds N item-shares (A1 flag ON). Pinned by `testFlagOffSingleItemPerZoneUpsertRemoveStatusBehaveAsBefore` and `testUpsertReplacesOnlyTheMatchingItemNotTheWholeZone`.
4. **`updateStatus`** was widened from "patch the first match" to "patch every match in the zone" — with exactly one record per zone (today's shape) the loop body runs once, so this is observably identical; it's the correct generalization for N item-shares per zone, since the fingerprint ceremony is one event per zone/member that every item-share in that zone must reflect. Pinned by the same back-compat test plus `testUpdateStatusAdvancesEverySiblingInTheZoneTogether` / `testUpdateStatusNeverRegressesAnAlreadyConfirmedSiblingEvenWhenOthersAdvance`.
5. **`remove(zoneName:)`** — logic untouched; doc comment updated to state its (always-true) "whole-zone" meaning explicitly now that it matters.

## Design decisions worth flagging

- **`updates`/`Ops` use named structs, not raw Swift tuples.** The task's pseudocode wrote `updates: [(itemId, DesiredGrant, existingGrantId)]`. A literal 3-tuple array can't conform to `Equatable` in Swift (tuples aren't nominal types), which would block the exact "idempotent" / "resumable" equality assertions the acceptance criteria require. Implemented as `UpdateOp: Equatable, Sendable { itemId, desired, existingGrantId }` — same three pieces of data, testable, self-documenting field names. `DesiredGrant`, `PublishedGrant`, `Ops` are nested types on `SpaceShareMembershipReconciler`, matching the codebase's existing pattern of nested types on a `nonisolated` namespace (e.g. `SharedGrantLiveCheck.Outcome`).
- **Deterministic ordering.** `plan`'s `creates`/`updates` are sorted by `itemId`, `revokes` by grant id — Swift `Dictionary` iteration order is not guaranteed stable, and the task's own idempotence/resumability requirement depends on `plan` being a pure, repeatable function of its inputs. Verified by `testPlanIsDeterministicAcrossRepeatedCallsAndOutputIsSorted`.
- **`published(grants:)` dedupes a duplicate itemId deterministically** (highest `epoch`, tied-broken by `createdAtUnixMs` then `id`) rather than by array/insertion order. This is defensive — two live grants for the same item should never happen — but `plan`'s determinism transitively depends on `published` being deterministic too, so an unresolved tie-break would have been a latent idempotence bug. Verified order-independently by `testPublishedResolvesDuplicateItemIdByHighestEpochDeterministically`.
- **Safelist excludes default-protected passwords by design, not by accident.** `.password`/`.totp` fields default to `protected: true` at creation (`FieldKind.defaultsProtected`). The frozen A0-6 contract says (stated three times) "AND not protected... any protected → .none" — so a freshly created login's password is **not** included in a blanket Space share until the owner explicitly un-masks that specific field. This is consistent with the codebase's existing convention for automatic/no-explicit-confirmation release paths: `WebExtensionReader.releasable` (`VaultifyCore/WebExtensionReader.swift:111-113`) applies the identical `!protected && guard2 != true` gate to the Safari-extension fill/read path, and its own test fixtures seed password fields as `protected: true`. The manual per-item share flow (`ShareAccessSheet`) is unaffected — it still lets an owner explicitly grant a protected field. Flagging this so the product-visible consequence ("blanket-shared passwords require the owner to unprotect that field first") is a known, verified trade-off rather than a silent surprise later. I did not alter the contract — implemented it exactly as frozen.
- **"Not derived/virtual" (A0-6) is satisfied by construction**: `VaultItem.fields` (`[DynamicField]`) never contains synthetic/virtual entries — those exist only as a separate type (`QuickViewApprovedField`) used by an unrelated flow — so there was nothing extra to filter here. Documented in the safelist's doc comment rather than added as dead code.

## Concerns
None blocking. One product-behavior note flagged above (protected-by-default passwords) for awareness before A3/UI copy is written — not a deviation from the frozen contract, just surfacing its consequence.

## Next Steps
- A3 can build its executor directly on `SpaceShareMembershipReconciler.plan(...)`: mint/publish for `.creates`, republish-with-bumped-epoch for `.updates` (using `existingGrantId`), revoke for `.revokes`.
- A3 will also need to decide the `desired × members` fan-out (call `plan` once per member zone, reusing the same `desired` map) and the batching/resumable-executor state machine (`PREPARING → PUBLISHING x/y → PARTIAL → ACTIVE → FAILED_RETRYABLE`) — out of scope here by design.

Status: DONE
Summary: SharingStore now keys shares per (zone, item) with sibling-safe upsert/remove/status and full back-compat; SpaceShareSafelist and SpaceShareMembershipReconciler are pure, deterministic, idempotent, and exhaustively tested (37 new tests); full suite (765 tests) is green; no crypto files touched.
Files changed: Vaultify/Features/Sharing/SharingStore.swift (modified); VaultifyCore/Sharing/SpaceShareSafelist.swift, VaultifyCore/Sharing/SpaceShareMembershipReconciler.swift, VaultifyTests/SharingStoreIdentityTests.swift, VaultifyTests/SpaceShareSafelistTests.swift, VaultifyTests/SpaceShareMembershipReconcilerTests.swift (new)
Compile: PASS
Tests: 37/37 new (765/765 full suite)
Concerns: protected-by-default passwords are excluded from blanket Space shares by design (frozen A0-6 contract) — flagged for product-copy awareness, not a blocker
