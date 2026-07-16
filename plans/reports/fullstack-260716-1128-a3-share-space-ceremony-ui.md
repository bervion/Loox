# Phase A3 stage 2 — "Share a Space" ceremony UI — Implementation Report

Plan: `plans/260715-1848-family-devices-crypto/family-group-transport.md` (A3 scope: the
ceremony UI + flag flip — stage 1 already built the executor)
Prior stage report: `plans/reports/fullstack-260716-1057-a3-transport-core-executor.md` (A3
stage 1 — `SpaceShareMembershipExecutor`, `SpaceShareRecipientContext`,
`SpaceShareGrantPublishing` / `LiveSpaceShareGrantPublisher`, the `publishGrant` supersede fix)
Date: 2026-07-16

## Status: DONE

## Executed Phase
- Phase: A3 stage 2 (ceremony UI + flag flip)
- Status: completed. `ShareSpaceSheet` built, wired into `FamilyScreen`,
  `FamilyShareTransport.perGrantEnabled` flipped to `true`.

## Files Modified

| File | Why |
|---|---|
| `Vaultify/Features/Profile/FamilyScreen.swift` | Added the "Share a Space" primary action (presents `ShareSpaceSheet`), updated the stale empty-state copy that said group sharing was "coming soon," updated the file doc comment. |
| `Vaultify/Localizable.xcstrings` | +15 new EN/VI string pairs for `ShareSpaceSheet` + the `FamilyScreen` entry (see "Localization" below). |
| `VaultifyCore/Sharing/FamilyShareTransport.swift` | `perGrantEnabled` flipped `false → true` (the ONLY functional line changed); doc comment rewritten to describe the now-enabled state instead of "flip only for in-progress work." |
| `VaultifyTests/FamilyShareTransportTests.swift` | Two tests updated — see "Flag flip fallout" below, called out prominently per the task's instruction. |

## Files Created

| File | Why |
|---|---|
| `Vaultify/Features/Sharing/ShareSpaceSheet.swift` | The ceremony UI (546 lines). |
| `Vaultify/Services/Sharing/SpaceShareZoneDedupe.swift` | Pure, unit-tested zone-reuse rule the sheet uses to decide whether to reuse an existing recipient zone (persona-scoped, INV-R03). |
| `VaultifyTests/SpaceShareZoneDedupeTests.swift` | 6 tests for the above. |

Note: `Vaultify/Services/Sharing/ApprovalShareService.swift`, `SpaceShareMembershipExecutor.swift`,
`ApprovalShareServiceSupersedeTests.swift`, `SpaceShareMembershipExecutorTests.swift` show as
dirty/untracked in `git status` — these are **stage 1's** uncommitted work (per its report), not
touched by this session. Verified via `git status` before and after: my diff is exactly the 7
files/additions listed above.

## 1. Ceremony-reuse approach

**Scouted first, per the task's hard requirement.** Read `ShareAccessSheet.swift`,
`ShareInviteSentSheet.swift`, `TrustFingerprintView.swift`, `ShareStepperModel.swift`,
`ShareResumeStepperSheet.swift`, `ApprovalShareService.swift`, `SharedGrantComposer.swift`,
`SharingStore.swift`, `OwnerShareRefresher.swift`, `ApprovalPrerequisites.swift`, and the stage-1
executor + its own report, before writing any code.

**What is reused verbatim (zero duplication):**
- `ApprovalShareService.createShare` / `fetchParticipantProfile` / `participantAccepted` — the
  exact same CloudKit calls `ShareAccessSheet` makes.
- `DeviceSigningIdentity.loadOrCreate()` + `TrustFingerprint.code(...)` — the exact same
  fingerprint derivation.
- `TrustFingerprintView` — the SAME component is instantiated directly, not forked. The
  "ONE-TIME ceremony" the task requires IS this view; `ShareSpaceSheet` never re-implements it.
- `ShareInviteSentSheet` — the SAME "you don't have to wait here" card, reused for the waiting
  step (parametrized with the Space's name instead of an item's title).
- `SharedGrantComposer.RecipientProfile` — built from the polled profile exactly as
  `ShareAccessSheet.confirmFingerprintAndPublish` does; handed to `SpaceShareRecipientContext`,
  which stage 1 already documented as "reuses `SharedGrantComposer.RecipientProfile` so this can
  never drift from the single-item ceremony's shape."
- `SpaceShareMembershipExecutor.reconcile` / `LiveSpaceShareGrantPublisher` — called, not
  modified, not reimplemented (confirmed: `SpaceShareMembershipExecutor.swift` and
  `ApprovalShareService.swift` are untouched by this session — see the git-status note above).
- **No crypto changes.** `ApprovalCrypto`/HPKE untouched — confirmed by diff scope (only the 7
  files listed above changed).

**What is a genuine, judgment-call fork (not crypto/ceremony, orchestration only):**
I evaluated extracting a shared "ceremony engine" type (e.g. an observable controller
encapsulating createShare/poll/fingerprint) that both `ShareAccessSheet` and `ShareSpaceSheet`
would own, to get to zero duplication of the `Step` state machine's plumbing. I chose NOT to
refactor `ShareAccessSheet` to use it:
- It is a live, heavily-tested, already-shipped flow (per-field capability picker, hand-over
  confirmations, resume-by-email, auto-invite drop, QR card) with real regression risk from a
  structural refactor.
- It was not in this task's file ownership / deliverables list.
- The duplicated code is UI orchestration (a `Step` enum + `@State` + polling loop shape), not
  the security-sensitive implementation — every call the duplicated code makes routes through
  the SAME `ApprovalShareService`/`SharedGrantComposer`/`TrustFingerprint`/`TrustFingerprintView`,
  so there is no second crypto/ceremony implementation, only a second (smaller, Space-shaped)
  state machine driving the same calls.

**One deliberate BEHAVIOR change from the single-item ceremony (not a fork of it):** zone reuse.
`ShareAccessSheet.createShare()` only dedupes within `SharingStore.shares(forItem: itemID)` —
scoped to the ONE item being shared — so sharing two different items to the same recipient mints
two different zones today (verified by reading the code, not assumed). A Space share must instead
reuse ONE zone per (persona, recipient), which is the entire reason the per-grant transport
(stage 1) exists. This decision is made in a new, small, pure, unit-tested helper —
`SpaceShareZoneDedupe.existingZoneName(recipientShares:activePersonaItemIds:)` — rather than
inline in the view, because it enforces a real invariant (INV-R03): a zone is reused only if it
already holds a share for an item the ACTIVE persona owns, never a zone that only holds a
DIFFERENT persona's earlier single-item share (which would otherwise mix two personas' items into
one CloudKit zone). Reasoning for why "any matching item" is safe (not just "every item"): no
zone can hold items from more than one persona today, because every existing zone-minting path is
either per-item (single-persona at mint time) or this same persona-scoped rule — documented in
the type's doc comment and exercised by `SpaceShareZoneDedupeTests` (6 cases: no shares, same
persona, different persona, mixed zones, multiple items in one zone, empty persona set).

## 2. `ShareSpaceSheet` state flow

```
.checking          — ApprovalPrerequisites.check() on first appear (.task, once)
   ├─ blocked  →  .blocked(Blocker)      — "Check again" re-runs checkPrerequisites()
   └─ ok       →  .config
.config             — pick a Space (activePersonaSpaces, single-select rows) + recipient email
                      + (once a Space is picked) a "What's shared" section showing the mandated
                      disclosure sentence and a live "N of M" eligible-item count, plus the
                      existing multi-device toggle (parity with ShareAccessSheet's P03b toggle,
                      default ON, same footer copy). "Share this Space" is disabled until a
                      Space + valid email + at least 1 eligible item.
   → createShare()  — env.approvalShare.createShare(existingZoneName: SpaceShareZoneDedupe...)
.creating           — reused copy "Setting up encrypted approval transport…"
.waiting(zoneID, shareURL)
   — ShareInviteSentSheet + Messages nudge / ShareLink fallback + Done; toolbar "Check now"
   — .task(id: pollingZoneName) drives pollForProfile(zoneName:), same backoff shape as
     ShareAccessSheet (3s → doubling, capped 10s, ~24 attempts / 2.5 min budget)
   — .onReceive(.shareAcceptanceHint) triggers an immediate checkProfileNow()
   → profile found → .fingerprint(zoneID, code, profile)
.fingerprint        — TrustFingerprintView(code:recipientLabel:onConfirm:) — the ONE ceremony
   → onConfirm → confirmFingerprintAndFanOut():
       1. GC the invite-link record (mirrors ShareAccessSheet's post-acceptance cleanup)
       2. build SpaceShareRecipientContext (see §3) → resolvedRecipient (frozen @State)
       3. await publishFanOut()
.publishing         — spinner + "Sharing your Space…" + live eligible-item count
   → executor.reconcile(spaceItems:, recipient:, nowUnixMs:) — ONE call, freshly reading
     env.repository.items(inFolder:) each time (never a stale snapshot)
   ├─ throws (e.g. fetchAllGrants network failure) → .failed(message)
   └─ returns Summary → .result(summary)
.result(summary)
   — counts card: Added / Updated / Removed (from summary.outcomes)
   — no failures → "Space shared" + Done (dismiss)
   — failures    → "Needs attention" + failed-item-title list (best-effort; itemId-keyed
                    create/update failures resolve a real title, grantId-keyed revoke failures
                    fall back to "an item") + Retry (re-invokes publishFanOut(), NOT the
                    ceremony) + Done
.failed(message)
   — before the ceremony resolved (resolvedRecipient == nil): "Try again" → back to .config
     (same recovery shape as ShareAccessSheet — nothing was published yet, safe to restart)
   — after the ceremony resolved (resolvedRecipient != nil): "Retry" → re-invokes
     publishFanOut() directly, skipping createShare/wait/fingerprint entirely
```

Cancel (the default `VaultSheetScaffold` leading button) is available at every step. Dismissing
mid-ceremony or mid-fan-out is safe: the CKShare zone / any already-published grants persist in
CloudKit regardless of the sheet's lifetime, and re-opening `ShareSpaceSheet` for the same
Space+recipient later resumes correctly — `existingZoneName` finds the same zone,
`fetchParticipantProfile` finds the already-published profile (near-instant `.waiting` → `.fingerprint`,
one harmless re-confirmation tap), and `reconcile` is idempotent (already-published items are
no-ops). This is a deliberate simplification over building cross-launch resumability state for an
in-flight Space share (no persisted "pending Space share" record) — see "Known limitations" below.

## 3. How `SpaceShareRecipientContext` is built

```swift
resolvedRecipient = SpaceShareRecipientContext(
    zoneID: zoneID,                                    // from the ceremony's .fingerprint step
    recipientLabel: normalizedRecipient,                // trimmed + lowercased email, never CloudKit-visible
    profile: SharedGrantComposer.RecipientProfile(
        participantPubKey: profile.participantPubKey,
        deviceSigningKeys: profile.deviceSigningKeys,
        deviceHPKEDirectory: profile.deviceHPKEDirectory),  // straight from the polled participant profile
    deviceScope: allowMultipleDevices ? .multi : .single)  // the sheet's own toggle, same default as ShareAccessSheet
```

Then: `SpaceShareMembershipExecutor(publisher: LiveSpaceShareGrantPublisher(service:
env.approvalShare, store: env.store), store: env.sharingStore).reconcile(spaceItems:
env.repository.items(inFolder: selectedSpace.id), recipient: resolvedRecipient!, nowUnixMs:)`.
`spaceItems` is re-read fresh on every `publishFanOut()` call (including Retry), never cached from
ceremony start, so a concurrent edit to the Space between the ceremony and the fan-out (or between
a failure and a Retry) is picked up correctly — matches the executor's own "live membership" design.

Persona isolation (INV-R03): `selectedSpace` only ever comes from `env.repository.activePersonaSpaces`
(the picker never lists another persona's Spaces), and `env.repository.items(inFolder:)` is itself
persona-scoped (`activePersonaItems` under the hood) — so `spaceItems` can never contain another
persona's items by construction, independent of `SpaceShareZoneDedupe`.

## 4. Flag flip (final edit, as instructed)

`VaultifyCore/Sharing/FamilyShareTransport.swift`: `perGrantEnabled` is now `true`. This makes
**every** owner-side grant publish (single-item AND Space) use deterministic per-grant record
names (`grant:<id>` / `display:<id>`) instead of the legacy zone-wide singleton. Consequences,
verified against the code (not assumed):
- Existing single-item shares published under the legacy names keep resolving: the recipient's
  read path (`ApprovalRecipientService.dedupedLiveGrants`) and the legacy-name decode/cleanup
  fallbacks in `ApprovalShareService`/`ApprovalRecordMapping` were **additive from day one**,
  never gated on this flag — confirmed by re-reading both files during scouting.
- A re-share of the SAME single item now REPLACES its prior grant instead of leaving orphaned
  ciphertext (stage 1's Part 1 fix, `supersededRecordIDs`), which only activates once the flag is
  on — this session is what turns that fix live in production for the first time.
- Multi-grant zones (N items, one member) now work end to end, which is what `ShareSpaceSheet`
  needs to be usable at all.

### Flag-flip fallout in the test suite (flagged prominently, per the task's instruction)

`VaultifyTests/FamilyShareTransportTests.swift` had **one** test that explicitly pinned the flag's
default (`XCTAssertFalse(FamilyShareTransport.perGrantEnabled, "default must stay off — flipping
it is a deliberate, separate decision")`) plus a sibling test asserting the LEGACY record name —
both of which read the LIVE flag through `ApprovalRecordMapping.grantRecord`/`displayEnvelopeRecord`
and therefore broke the instant the flag flipped:
- `testGrantRecordUsesLegacyNameWhileFlagDisabled` — asserted legacy naming AND guarded the flag
  itself being `false`.
- `testDisplayEnvelopeRecordUsesLegacyNameWhileFlagDisabled` — asserted legacy naming (no explicit
  flag guard, but the function it calls branches on the same live flag).

**I did not silently weaken or delete either test.** Both were, by their own doc comments, snapshot
tests of "whatever the flag currently defaults to" (`"Acceptance criterion: with
FamilyShareTransport.perGrantEnabled false (default)..."` — explicitly framed as tracking the
default, with the flip called out as "a deliberate, separate decision"). This task IS that
deliberate decision. I renamed and rewrote both to assert the NEW default with equal strictness
(still hard `XCTAssertEqual`/`XCTAssertTrue`, not loosened):
`testGrantRecordUsesPerGrantNameNowThatTransportIsEnabled` and
`testDisplayEnvelopeRecordUsesPerGrantNameNowThatTransportIsEnabled`, each with a doc comment
explaining the history and pointing at the tests that still cover flag-INDEPENDENT legacy-decode
back-compat (`testLegacyRecordNameConstantsUnchangedByRename`,
`testGrantRecordDecodeIsIndependentOfRecordName` — both construct records with explicit names,
never reading the live flag, so they were never at risk and needed no change). Net effect: zero
coverage lost, two tests now correctly describe the shipped behavior instead of a superseded one.
Confirmed no other test in the suite reads `perGrantEnabled` as a live assertion (grepped the
whole `VaultifyTests` + `Vaultify` + `VaultifyCore` tree; the only other hits are doc comments in
`SharingStoreIdentityTests.swift`/`ApprovalShareServiceSupersedeTests.swift` describing history,
not assertions — both files construct records/state independent of the live flag value).

## Localization

15 new EN/VI pairs added to `Vaultify/Localizable.xcstrings` (verified via `python3 -m json.load`
before and after — file stays valid JSON; inserted as one block right after the catalog's leading
`"" : {}` entry rather than at exact alphabetical position, since Xcode's own sort order does not
match a plain Unicode-codepoint sort — confirmed empirically by round-tripping the file through
`json.dumps(sort_keys=True)` and diffing, which produced 3800+ spurious reordering lines; a
targeted insert avoids that entirely and is functionally identical since JSON object order is not
semantic). Every string was checked against copy rules (no "!", no "—", no "·") before insertion;
one draft ("...couldn't be sent — items already shared...") was caught and rewritten as two
sentences before being added. Reused **11 existing keys verbatim** instead of adding new ones:
"Recipient's iCloud email", its footer, "Allow use on multiple devices" + footer, "Setting up
encrypted approval transport…", "Check now", "Nudge via Messages", "Share invite link", "Done",
"Try again", "Check again", "Needs attention" (repurposed as the partial-result state title — its
existing VI "Cần chú ý" is generic enough), "%lld items" and "%lld of %lld" (both reused for
dynamic counts via SwiftUI's `Text("\(x)")` interpolation → format-string catalog key mapping),
and the blocked-view / Messages-body strings from `ApprovalPrerequisites`/`ShareAccessSheet`.
New keys: "Share a Space", "Space to share", "What's shared", the mandated safelist-disclosure
sentence (verbatim per the task spec), "Logins", "Share this Space", "Sharing your Space…",
"Space shared", "They can now use every shared login…", "Most of this Space shared…", "Added",
"Updated", "Removed", "Retry", and the `FamilyScreen` empty-state replacement copy. VI
terminology for "Space" follows the established in-app convention (confirmed via existing catalog
entries "Spaces"→"Nhóm", "No Spaces yet"→"Chưa có nhóm nào", "Choose a Space"→"Chọn nhóm" — NOT a
literal "Không gian" translation).

## Acceptance

**1. Compiles clean.** `tuist generate --no-open` then
`xcodebuild -workspace Vaultify.xcworkspace -scheme Vaultify -configuration Debug -destination
'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd CODE_SIGNING_ALLOWED=NO` — this
single workspace build embeds both `VaultifyAutoFill.appex` and `VaultifySafari.appex` as PlugIns
(confirmed in the log via `Copy .../VaultifyAutoFill.appex` / `Copy .../VaultifySafari.appex` +
`ValidateEmbeddedBinary` for both). Log tail:
```
PruneExplicitPrecompiledModules /tmp/vaultify-dd/SDKExplicitPrecompiledModules

** BUILD SUCCEEDED **
```
`grep -c "error:" /tmp/vaultify-xc.log` → 0. `grep -n "warning:" | grep -i
"ShareSpaceSheet\|SpaceShareZoneDedupe\|FamilyScreen\|FamilyShareTransport"` → 0 (no warnings in
any changed/new file).

**2. Full `VaultifyTests` suite passes.**
```
Test Suite 'VaultifyTests.xctest' passed at 2026-07-16 11:55:30.942.
	 Executed 806 tests, with 0 failures (0 unexpected) in 40.034 (40.217) seconds
Test Suite 'All tests' passed at 2026-07-16 11:55:30.942.
	 Executed 806 tests, with 0 failures (0 unexpected) in 40.034 (40.218) seconds
** TEST SUCCEEDED **
```
806 = stage 1's baseline 800 + 6 new `SpaceShareZoneDedupeTests`. The flag-flip fallout (2 tests)
is fixed and re-verified passing individually:
`testDisplayEnvelopeRecordUsesPerGrantNameNowThatTransportIsEnabled` and
`testGrantRecordUsesPerGrantNameNowThatTransportIsEnabled` both show `passed (0.000 seconds)` in
the log; `FamilyShareTransportTests` suite as a whole passes.

**3. 2-account test script** (device checklist — not run this session; no second iCloud account
available in this environment, same convention stage 1 used for its own CloudKit-touching halves):

1. **Setup.** Account A (owner) creates a Space "Work" under its active persona with 3 login
   items (each with username+password+url) and one Secure Note or 2FA item also filed in "Work".
   Account B is a second iCloud account with Loox installed, notifications allowed.
2. **Share.** On A: Family → "Share a Space" → pick "Work" → confirm the "3 of 4" eligible count
   shown in "What's shared" → enter B's iCloud email → "Share this Space" → wait for B to accept
   (push or Messages nudge) → "Activate Sharing" on the fingerprint screen → expect `.result` with
   "Space shared", Added: 3, Updated: 0, Removed: 0.
   **Expect:** B's shared-items projection shows exactly the 3 logins (username/password/url/email
   fields visible); the note/2FA item is NOT present on B's device at all.
3. **Re-share, no duplicate.** On A: Family → "Share a Space" → pick "Work" again → same email →
   expect the SAME zone is reused (verify no second entry appears for B in Family's member list —
   `FamilyScreen` groups by `recipientLabel`, so a duplicate zone would still collapse into one row
   visually; the definitive check is CloudKit zone count for B staying at 1, inspectable via
   `ApprovalShareService.ownedZoneNames` on A's device or Console) → expect `.result` with Added:
   0, Updated: 0, Removed: 0 (already converged, matches the reconciler's idempotence).
4. **Add an item, re-run.** On A: add a 4th login to "Work" → Family → "Share a Space" → "Work" →
   B's email → expect the eligible count reads "4 of 5" → share → expect `.result` Added: 1.
   **Expect:** B's projection now shows 4 logins; the new one appears without B re-accepting
   anything (same zone, same participant profile — `pollForProfile` resolves near-instantly).
5. **Revoke the member.** On A: Family → tap B → tap any one of B's shared items →
   `ShareRecipientDetailSheet` → "Revoke access" → confirm. This calls
   `env.approvalShare.revoke(zoneName:)`, which deletes B's WHOLE zone (pre-existing behavior,
   unchanged by this task) — since a Space share puts every item's grant in ONE zone (the entire
   point of per-grant transport), revoking via ANY one item's detail sheet now correctly revokes
   the WHOLE Space share in one action. **Expect:** B loses access to all 4 items immediately (or
   on next sync); A's Family screen no longer lists B.

## Known limitations / deliberate simplifications (documented, not silent)

- **No cross-launch resumability for an in-flight fan-out.** Unlike `ShareAccessSheet`,
  `ShareSpaceSheet` does not persist a "pending Space share" record before the ceremony
  completes — if the app is killed mid-`.waiting`/`.fingerprint`, the owner must re-open
  `ShareSpaceSheet` and pick the same Space+recipient again (safe: `SpaceShareZoneDedupe` finds
  the same zone, the profile is already published so the wait is near-instant, one redundant
  Activate tap, `reconcile` is idempotent). If killed mid-`.publishing`, the in-flight `reconcile`
  Task is not cancelled by the dismiss (matches `ShareAccessSheet`'s own bare-`Task{}`-from-button
  pattern) and completes in the background; re-opening the sheet and re-sharing the same Space
  converges to the same end state either way.
- **Auto-invite rendezvous drop (Loox-to-Loox "U5" tier) omitted.** `ShareAccessSheet` also drops
  a sealed envelope into the recipient's armed invite inbox so their device can self-detect the
  invite. `ShareSpaceSheet` relies on the Messages nudge / ShareLink / native CKShare invitation
  only. This is a delivery-convenience omission, not a ceremony/crypto fork — the CKShare
  creation, acceptance, fingerprint, and grant publishing are unaffected; the recipient still
  gets a real invite either way.
- **Failure attribution for revoke ops is best-effort.** `Summary.failures` for a revoke is keyed
  by `grantId` (the executor's existing shape, unchanged), which `failureLabel` cannot resolve
  back to an item title after the grant record is gone — it falls back to a generic "an item"
  label. Create/update failures (keyed by itemId) resolve real titles.
- **No per-item revoke UI** — explicitly out of scope per the task ("stage 3"). The executor
  already supports it (`revokeGrant`); `ShareRecipientDetailSheet`'s existing "Revoke access"
  remains the only reachable control and now revokes the whole member (see test script step 5).

## Unresolved questions
None blocking. One judgment call already covered above (ceremony-reuse via shared service calls +
components rather than a shared controller type — documented in §1) and one already covered above
(the two test rewrites — documented in "Flag flip fallout").

---

Status: DONE
Summary: Built `ShareSpaceSheet` reusing the single-item ceremony's services/components verbatim
(createShare, profile poll, `TrustFingerprintView`, `SharedGrantComposer.RecipientProfile`) with
its own persona-scoped zone-reuse rule (`SpaceShareZoneDedupe`, new + unit-tested) driving one
`SpaceShareMembershipExecutor.reconcile` fan-out call; wired a "Share a Space" entry into
`FamilyScreen`; flipped `FamilyShareTransport.perGrantEnabled` to `true` as the final edit and
fixed the two tests that pinned the old default, openly documented, with zero coverage lost.
Files changed: `Vaultify/Features/Profile/FamilyScreen.swift`, `Vaultify/Localizable.xcstrings`,
`VaultifyCore/Sharing/FamilyShareTransport.swift`, `VaultifyTests/FamilyShareTransportTests.swift`
(modified); `Vaultify/Features/Sharing/ShareSpaceSheet.swift`,
`Vaultify/Services/Sharing/SpaceShareZoneDedupe.swift`,
`VaultifyTests/SpaceShareZoneDedupeTests.swift` (new)
Compile: PASS (app + VaultifyAutoFill + VaultifySafari, 0 errors, 0 warnings in changed files)
Tests: 806/806 PASS (0 failures)
Concerns: none blocking — 2-account device checklist not run this session (no second iCloud
account in this environment; same convention stage 1 used for its own CloudKit-touching halves).
