# Phase A3 stage 1 — Space-share transport core (executor) — Implementation Report

Plan: `plans/260715-1848-family-devices-crypto/family-group-transport.md` (A3 scope, items 3-8 subset: the
executor only — no ceremony UI, no `ShareSpaceSheet`)
Scout: `plans/reports/scout-260715-1955-crypto-surface-map.md`; prior stage reports
`plans/reports/fullstack-260715-1955-a1-per-grant-transport.md` (A1),
`plans/reports/fullstack-developer-260715-2119-a1-review-fixes.md` (A1 fixes),
`plans/reports/fullstack-260715-2128-a2-reconciler-store.md` (A2)
Date: 2026-07-16

## Status: DONE

## Executed Phase
- Phase: A3 stage 1 (transport core — Part 1 `publishGrant` supersede fix + Part 2
  `SpaceShareMembershipExecutor`)
- Plan: `plans/260715-1848-family-devices-crypto/family-group-transport.md`
- Status: completed, compile-only (no UI wiring, `FamilyShareTransport.perGrantEnabled` left `false`)

## Files Modified

| File | Why |
|---|---|
| `Vaultify/Services/Sharing/ApprovalShareService.swift` | Part 1: `publishGrant`'s flag-on path now finds and deletes any PRIOR grant for the same item before writing the new one. Part 2 support: new `fetchAllGrants(zoneID:nowUnixMs:)` (owner-side, verified), new `revokeGrant(_:zoneID:)` (per-grant scoped delete), and the shared pure/IO helpers backing both (`supersededRecordIDs`, `recordIDs`, `recordFootprint`, `allZoneRecords`). +133/-4 lines. |

## Files Created

| File | Why |
|---|---|
| `Vaultify/Services/Sharing/SpaceShareMembershipExecutor.swift` | Part 2: `SpaceShareRecipientContext` (input struct), `SpaceShareGrantPublishing` (protocol — fakeable boundary), `LiveSpaceShareGrantPublisher` (production adapter routing to `ApprovalShareService`/`SharedGrantComposer`), `SpaceShareMembershipExecutor` (the executor). |
| `VaultifyTests/ApprovalShareServiceSupersedeTests.swift` | Part 1 pure-function tests: `supersededRecordIDs(forItemId:in:)` and `recordIDs(forGrantId:in:)` — 11 tests. |
| `VaultifyTests/SpaceShareMembershipExecutorTests.swift` | Part 2 executor tests against a fake `SpaceShareGrantPublishing` — 10 tests. |

## (a) Part 1 — how the superseded same-item grant is found and removed

**Trigger.** In `publishGrant`, only when `FamilyShareTransport.perGrantEnabled` (stays `false` this
stage — inert in production). The existing `staleBlobIDs` computation (`sharedFieldRecordIDs(grantId:
grant.id, ...)`) is left completely untouched — it always matches zero records for a same-item re-share
because `grant.id` above it is freshly minted (`ApprovalConfig.opaqueName()`), which was the exact
documented A1 gap. A NEW, separate step supplements it.

**The query.** A full, stateless zone scan (`ZoneDeltaFetch.pull`, nil cursor — same pattern as
`sharedFieldRecordIDs`) collects every `CKRecord` currently in the zone. The pure reduction
(`ApprovalShareService.supersededRecordIDs(forItemId:in:)`, `nonisolated static`, unit-tested) then:
1. Decodes every candidate via `ApprovalRecordMapping.grant(from:)` (already gates on `recordType ==
   ApprovalGrant`) and keeps only records whose **decoded** `grant.itemId == thisGrant.itemId` — the
   AUTHENTICATED field inside the signed blob, never a record-name guess or prefix scan (INV-FAM-01).
2. For each match, computes its full **record footprint** (`recordFootprint(forGrant:record:allRecords:)`):
   - the grant record itself (`record.recordID`, from the scan — no name reconstruction),
   - its per-grant display record, named deterministically from the matched grant's OWN id
     (`ApprovalConfig.displayEnvelopeRecordName(grantId: grant.id)`),
   - **if** the matched grant record's name is the legacy singleton (`"grant"`) — i.e. it was published
     while the flag was off, or before Family sharing existed — the legacy display name
     (`"display-envelope"`) too. This is provably safe, not a guess: `ApprovalRecordMapping.grantRecord`/
     `displayEnvelopeRecord` both key off the SAME `FamilyShareTransport.perGrantEnabled` value at write
     time, so a legacy-named grant's display was ALWAYS written under the legacy name.
   - every `ApprovalSharedField` record in the SAME scan whose cleartext `grantId` field equals the
     matched grant's id.
3. Deduplicates the accumulated ids (a defensive case: the identical grant found under two names — legacy
   + per-grant — would otherwise compute the SAME per-grant display id twice, which is unsafe to submit
   twice in one CloudKit delete batch).

**The delete set.** `supersededGrantRecordIDs(itemId:zoneID:)` (private IO wrapper) runs that scan +
reduction and returns the id list. `publishGrant` unions it with the existing `staleBlobIDs` and passes
the union as the SAME `modifyRecords(saving: records, deleting: ..., savePolicy: .allKeys)` call that
writes the new grant/display/field records — so create-and-replace is one write, not two round trips.
Flag-off behavior is byte-for-byte unchanged (the new step is entirely gated behind the same `if
FamilyShareTransport.perGrantEnabled`).

## (b) Executor: create/update/revoke → `ApprovalShareService` mapping

`SpaceShareMembershipExecutor.reconcile(spaceItems:recipient:nowUnixMs:)`:
1. `desired = Reconciler.desired(spaceItems)` (pure, A2).
2. `liveGrants = publisher.fetchAllGrants(zoneID: recipient.zoneID, nowUnixMs:)` — ONE fresh CloudKit read.
3. `published = Reconciler.published(grants: liveGrants)`, `ops = Reconciler.plan(desired, published)` (pure, A2). Early-returns an empty `Summary` when `ops.isEmpty` (the common already-synced case).
4. **creates + updates → `publish`** (both go through the identical call — Part 1 makes a same-item
   republish REPLACE instead of duplicating, so the executor needs no separate "delete the old one first"
   step for updates):
   - creates: `epoch: 1` (matches `ShareAccessSheet`'s create ceremony).
   - updates: `epoch: existingEpoch + 1`, where `existingEpoch` is looked up from the RAW `liveGrants`
     array (`AccessGrant.epoch`, not carried by `Reconciler.PublishedGrant`) by `UpdateOp.existingGrantId`
     — mirrors `ShareRecipientDetailSheet`'s single-item edit path exactly (bumping the epoch invalidates
     any in-flight ask-each-time request signed against the OLD epoch). This is the one piece of executor
     logic that had to look past the reconciler's own output type; no reconciler change was needed or made
     (see "Design decisions" below).
   - the actual call is `SpaceShareGrantPublishing.publish(item:capabilities:epoch:recipient:nowUnixMs:)`,
     whose PRODUCTION implementation (`LiveSpaceShareGrantPublisher`) routes straight to
     `SharedGrantComposer.publish(service: ApprovalShareService, ..., itemPasskeys: [], vaultKey: nil,
     ...)` — the SAME composer the single-item create/edit sheets use, so passkey/device-scope handling
     can never drift. `itemPasskeys`/`vaultKey` are always empty/nil because `SpaceShareSafelist` never
     grants a passkey capability for a blanket Space share (INV-08), so that branch of the composer is
     simply never reached here — not a special case, a structural non-issue.
5. **revokes → `revokeGrant`**: `ops.revokes: [String]` (grant ids) each go through
   `SpaceShareGrantPublishing.revokeGrant(_:zoneID:)`, whose production implementation calls the NEW
   `ApprovalShareService.revokeGrant` (see (d)) — deletes that ONE grant's record + display + fields,
   never the zone (`revoke(zoneName:)` remains the separate whole-member revoke, untouched).
6. Every op runs **sequentially** in a plain `for` loop (not concurrent) — the simplest possible cap on
   in-flight CloudKit work, satisfying the "cap concurrency" requirement without adding a batching/chunking
   utility this stage doesn't need (YAGNI; every op is independently idempotent, so a future
   bounded-parallel executor can reorder this without changing observable behavior).
7. **Partial-failure isolation**: each op's `try`/`catch` is scoped to that ONE op — a failed create/update
   is recorded in `Summary.failures[itemId]` and every OTHER op still runs; same for revokes
   (`Summary.failures[grantId]`). A failed op's `SharingStore` entry is left untouched (not upserted /
   not removed), so a LATER `reconcile` call sees it as still needing that same op — this is what makes
   the executor resumable without any extra state machine: "re-run `reconcile`" IS the retry.

## (c) `SharingStore` updates

- **Create/update success** → `store.upsert(ItemShareRecord(itemId:, zoneName: recipient.zoneID.zoneName,
  recipientLabel: recipient.recipientLabel, grantId: <the returned grant's id>, createdAtUnixMs:,
  fingerprintConfirmed: true, inviteRecordName:, dropRecordName:, autoUpdate:))`, built by the private
  `shareRecord(itemId:grantId:recipient:nowUnixMs:)` helper. Every published item-share is `.active`
  immediately (`fingerprintConfirmed: true`) — the executor runs AFTER the trust ceremony, so there is no
  separate "ready for ceremony" wait state the way the single-item flow has.
  - `createdAtUnixMs` is preserved from the EXISTING `(zoneName, itemId)` record on an update (falls back
    to `nowUnixMs` only for a genuine create) — an update must not reset the "shared since" timestamp the
    owner sees in `ShareRecipientDetailSheet`/`ShareResumeStepperSheet`.
  - `autoUpdate` is preserved from the existing record (an explicit owner choice — never silently reset by
    a reconcile pass; per the "do not silently undo explicit user decisions" rule).
  - `inviteRecordName`/`dropRecordName` are carried forward from the existing `(zoneName, itemId)` record,
    or (for a brand-new item in an already-active zone) from ANY sibling record in the same zone — these
    are zone-level invite artifacts the single-item ceremony (`ShareAccessSheet.confirmFingerprintAndPublish`)
    already carries into the active record so `revoke`'s best-effort GC can retry a possibly-failed public-DB
    delete; the executor preserves that same safety net rather than silently dropping it to `nil`.
- **Revoke success** → `store.remove(zoneName: recipient.zoneID.zoneName, itemId:)` (A2's per-item
  removal — leaves every sibling item-share in the zone untouched). The `itemId` for a revoked `grantId`
  is resolved from `published` (built BEFORE execution, so it still has the mapping after the live grant
  is gone).
- **Failure (either kind)** → no `SharingStore` write at all for that op.

## (d) Additions to `ApprovalShareService`

1. **`fetchAllGrants(zoneID:nowUnixMs:) async throws -> [AccessGrant]`** — the owner-side analog of
   `ApprovalRecipientService.fetchAllGrants`, needed because the recipient's version reads
   `container.sharedCloudDatabase` (a view onto zones OTHERS shared to this account), which never contains
   a zone this device itself owns and shared out. Scans the owner's own PRIVATE DB zone instead. **Reuses
   `ApprovalRecipientService.dedupedLiveGrants` verbatim** (no new verify/dedupe logic) — a recipient holds
   `.readWrite` on a shared zone (`createShare`), so a compromised recipient device could otherwise inject
   a same-shaped `ApprovalGrant` record into the OWNER's own zone that would make the reconciler believe an
   item is already synced when it is not (fail-safe: under-share, never a leak — same threat
   `dedupedLiveGrants`'s verify-before-dedupe already defends against for the recipient side; reused here,
   not reinvented). No crypto change — `ApprovalVerifier.verifyGrant` is the same call the recipient path
   already makes.
2. **`revokeGrant(_ grantId: String, zoneID:) async throws`** — deletes one grant's record, display
   record, and field records (via the same `recordFootprint`/`recordIDs(forGrantId:in:)` reduction Part 1
   introduced), never the zone. `revoke(zoneName:)` (the existing whole-member revoke) is untouched.
3. **Private helpers**: `allZoneRecords(zoneID:)` (the one-scan IO primitive `fetchAllGrants`,
   `revokeGrant`, and `supersededGrantRecordIDs` all share), `supersededGrantRecordIDs(itemId:zoneID:)`
   (IO wrapper for Part 1), and the three `nonisolated static` pure functions
   (`supersededRecordIDs(forItemId:in:)`, `recordIDs(forGrantId:in:)`, `recordFootprint(forGrant:record:
   allRecords:)`) — all unit-tested in `ApprovalShareServiceSupersedeTests.swift`.

None of this touches `ApprovalCrypto`/HPKE sealing/signing — every new method either decodes existing
record shapes or calls the existing `ApprovalVerifier`/`ApprovalRecordMapping` functions.

## Tasks Completed
- [x] Part 1 — `publishGrant` flag-on path finds + deletes a prior same-item grant (grant + display +
      fields) before writing the new one; flag-off path byte-for-byte unchanged.
- [x] Part 2 — `SpaceShareMembershipExecutor` (new), `SpaceShareGrantPublishing` protocol +
      `LiveSpaceShareGrantPublisher` production adapter, `SpaceShareRecipientContext` input struct.
- [x] `ApprovalShareService.fetchAllGrants` + `revokeGrant` (owner-side, needed by the executor).
- [x] Unit tests for the pure record-footprint reduction (11) and the executor's Ops→calls mapping via a
      fake publisher (10).
- [x] `FamilyShareTransport.perGrantEnabled` left `false`.
- [x] No UI built (`ShareSpaceSheet`/`FamilyScreen` untouched).
- [x] No crypto changes (`ApprovalCrypto`/HPKE untouched — confirmed by diff scope below).
- [x] `tuist generate` + full compile (app + `VaultifyAutoFill` + `VaultifySafari`, one workspace build).

## Tests Status

- **Type check / compile: PASS** — see log tail below.
- **New unit tests: 21/21 PASS** — `ApprovalShareServiceSupersedeTests` (11), `SpaceShareMembershipExecutorTests` (10).
- **Sibling sharing-suite regression (targeted run): 75/75 PASS** — the 21 new tests plus
  `FamilyShareTransportTests` (12), `SharedGrantComposerTests` (5), `SharingStoreIdentityTests` (10),
  `SpaceShareMembershipReconcilerTests` (15), `SpaceShareSafelistTests` (12) — all still pass unmodified.
- **Full `VaultifyTests` target: 800/800 PASS, 0 failures** (18.4s). No regressions; the flaky
  `ShareLifecycleStatusTests` crash A1's report flagged as pre-existing/unrelated did not reproduce in
  this run (matches A2's own full-suite run, which also didn't hit it).

### Compile log tail (app + AutoFill + Safari)
```
PruneExplicitPrecompiledModules /tmp/vaultify-dd/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules
PruneExplicitPrecompiledModules /tmp/vaultify-dd/Build/Intermediates.noindex/ExplicitPrecompiledModules
PruneExplicitPrecompiledModules /tmp/vaultify-dd/SDKExplicitPrecompiledModules

** BUILD SUCCEEDED **
```
`grep -n "error:" /tmp/vaultify-xc.log` → zero matches. `SpaceShareMembershipExecutor.swift` confirmed
compiled into the `Vaultify` target for both simulator slices (arm64 + x86_64).

### Test log tail (full suite)
```
Test Suite 'VaultifyTests.xctest' passed at 2026-07-16 11:26:00.889.
	 Executed 800 tests, with 0 failures (0 unexpected) in 18.367 (18.559) seconds
Test Suite 'All tests' passed at 2026-07-16 11:26:00.889.
	 Executed 800 tests, with 0 failures (0 unexpected) in 18.367 (18.560) seconds
** TEST SUCCEEDED **
```

## Design decisions worth flagging

- **`fetchAllGrants` reuses `ApprovalRecipientService.dedupedLiveGrants` directly** rather than
  re-implementing verify+dedupe on the owner side. It's a pure, general-purpose reduction (verify against
  a trusted key, dedupe survivors by decoded id) that doesn't actually depend on being "recipient" or
  "owner" — reusing it avoids a second copy of security-sensitive logic and inherits its existing 7-test
  coverage for free.
- **The executor looks up `epoch` from the raw `fetchAllGrants` result, not from
  `Reconciler.PublishedGrant`** (which doesn't carry epoch — A2 didn't need it for the pure diff). I
  deliberately did NOT add an `epoch` field to `SpaceShareMembershipReconciler.PublishedGrant` to get
  this — that type is already-committed, already-tested (A2), and out of this task's file scope; building
  a local `[grantId: epoch]` dictionary from `liveGrants` inside the executor gets the same correctness
  with zero changes to A2's files.
- **`supersededRecordIDs`'s legacy-display fallback is derived, not guessed.** It only adds the legacy
  display name when the MATCHED grant record's own name is the legacy singleton — provable from
  `ApprovalRecordMapping`'s write-time behavior (grant and display are always named by the SAME flag
  value), not a heuristic. This closes the one realistic case A1's own report flagged as future risk: a
  zone with a pre-existing legacy single-item share, later re-shared after the flag flips on.
- **Sequential execution, no batching utility.** The task's spec offered "sequentially or in small
  batches" as alternatives for capping concurrency; sequential trivially satisfies that (concurrency = 1)
  without introducing a `chunked(into:)` utility this compile-only stage has no caller to justify (YAGNI).
  Revisit if/when stage 2's UI needs real progress reporting mid-fan-out.
- **`Summary`/`ItemOutcome` are new, executor-local types** (not reused from anywhere else) — they exist
  so a future progress UI can show partial fan-out state; nothing in this stage renders them (no UI built,
  per the hard constraint).

## Testability note (per the task's acceptance criteria)

The executor IS cleanly fakeable: `SpaceShareGrantPublishing` is a narrow protocol
(`fetchAllGrants`/`publish`/`revokeGrant`) the executor depends on; `SpaceShareMembershipExecutorTests`
injects a fake conformer that records the exact call sequence (itemId, capabilities, epoch for publishes;
grantId for revokes) with no CloudKit involved, and a REAL `SharingStore` (UserDefaults-backed, already
the established test convention per `SharingStoreIdentityTests` — wiped before/after each test). This
covers: create → publish@epoch1 + upsert; update → publish@bumpedEpoch + upsert preserving
createdAt/autoUpdate; revoke → revokeGrant + remove; no-op when already synced; mixed
create+update+revoke in one run; partial-failure isolation (one op fails, the rest still run, the failed
item's `SharingStore` entry is untouched); and re-running after a successful run converges to zero calls
(resumability, observed through the executor's actual call sequence, not just the reconciler's pure
`plan` — that half is already covered by `SpaceShareMembershipReconcilerTests`).

The production adapter (`LiveSpaceShareGrantPublisher`) itself has NO logic of its own to unit-test — it's
a 1:1 routing shim to `ApprovalShareService`/`SharedGrantComposer`. Its correctness (and
`ApprovalShareService.fetchAllGrants`/`revokeGrant`'s CloudKit-touching halves) is deferred to the
two-account device checklist, matching the established convention for every other CloudKit-touching method
in this transport (`ApprovalShareService`/`ApprovalRecipientService` have no direct IO-level unit tests
either — only their pure helpers do, e.g. `dedupedLiveGrants`).

## Issues Encountered
None blocking. Working tree had pre-existing, unrelated uncommitted changes at session start
(`.gitignore`, `AGENTS.md`, `.codex/`, `plans/reports/proposal-260714-2231-loox-subscription-strategy.md`,
`.claude/agent-memory/code-reviewer/*`) — verified via `git log` that all of them have their own prior
history and are untouched by this session; left exactly as found, not part of this diff.

## Next Steps (stage 2, not built here)
- A `ShareSpaceSheet` (or equivalent) UI: runs the SAME trust ceremony `ShareAccessSheet` already has
  (`createShare` → poll for participant profile → `TrustFingerprintView` → confirm), then constructs a
  `SpaceShareRecipientContext` from the resolved zone + profile and calls
  `SpaceShareMembershipExecutor.reconcile(spaceItems:recipient:nowUnixMs:)` via a
  `LiveSpaceShareGrantPublisher(service: env.approvalShare, store: env.store)`.
- Only after stage 2's UI + a per-member revoke surface land should `FamilyShareTransport.perGrantEnabled`
  flip to `true` (per A1's own gating note) and the 2-account device checklist run: publish 2+ grants in
  one zone → recipient projects all; add/remove a Space item → reconciles; re-share the same Space → no
  duplicate zone; kill mid-fan-out → resumes cleanly on next `reconcile` call.

## Unresolved questions
None blocking this stage. One judgment call, not a fork: whether `SpaceShareMembershipReconciler.
PublishedGrant` should eventually carry `epoch` directly (would let the executor drop its own
`[grantId: epoch]` lookup) — deferred since it works correctly as-is and avoids touching A2's committed
file; worth a look if stage 2 finds another consumer that also needs a published grant's epoch.

---

Status: DONE
Summary: Part 1 makes `publishGrant`'s flag-on path replace (not duplicate) a prior same-item grant via an
authenticated-itemId zone scan; Part 2 adds `SpaceShareMembershipExecutor`, a fakeable
`SpaceShareGrantPublishing` boundary, and the owner-side `fetchAllGrants`/`revokeGrant` helpers it needs —
all reusing the existing `SharedGrantComposer`/`ApprovalVerifier`/`ApprovalRecordMapping` crypto/transport
paths with zero crypto changes. `perGrantEnabled` stays false; no UI built.
Files changed: `Vaultify/Services/Sharing/ApprovalShareService.swift` (modified);
`Vaultify/Services/Sharing/SpaceShareMembershipExecutor.swift`,
`VaultifyTests/ApprovalShareServiceSupersedeTests.swift`,
`VaultifyTests/SpaceShareMembershipExecutorTests.swift` (new)
Compile: PASS (app + VaultifyAutoFill + VaultifySafari, 0 errors)
Concerns: none blocking — see "Design decisions" and "Unresolved questions" above for judgment calls made
along the way.
