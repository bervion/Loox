# A1 Per-Grant Transport — Code Review Fix Round

Base report: `plans/reports/fullstack-260715-1955-a1-per-grant-transport.md`
Review verdict addressed: NEEDS_FIX (0 critical, 1 high, 2 medium)
Date: 2026-07-15

## Status: DONE

Applied exactly the 3 requested fixes. No new scope, no crypto change, flag semantics unchanged
(`FamilyShareTransport.perGrantEnabled` still defaults `false`, still gates only the owner-side
per-grant WRITE naming).

## H1 — verify-before-dedupe in `dedupedLiveGrants`

**File:** `Vaultify/Services/Sharing/ApprovalRecipientService.swift` (`dedupedLiveGrants`)

**Bug:** the reduction inserted into `byId[grant.id]` unconditionally, then filtered by
`verifyGrant(...) == nil` afterward. A same-id record with a forged/bad signature, if it enumerated
after the legitimate one, would overwrite the dictionary slot and then get filtered out by the
verify pass — taking the legitimate grant down with it. Silently hides an item the owner actually
still shares.

**Fix:** moved the `ApprovalVerifier.verifyGrant(...) == nil` check into the SAME guard that decodes
the record, before the `byId[grant.id] = grant` insertion. A record that fails verification is
`continue`d past and never enters the map — a same-id forgery can no longer win the slot regardless
of enumeration order.

```swift
// before
guard let grant = ApprovalRecordMapping.grant(from: record) else { continue }
byId[grant.id] = grant
...
return byId.values.filter { verifyGrant(...) == nil }.sorted { ... }

// after
guard let grant = ApprovalRecordMapping.grant(from: record),
      ApprovalVerifier.verifyGrant(grant, pinnedOwnerSigningKey: pinnedOwnerSigningKey,
                                   nowUnixMs: nowUnixMs) == nil else { continue }
byId[grant.id] = grant
...
return byId.values.sorted { ... }
```

**Test fix** (`VaultifyTests/FamilyShareTransportTests.swift`): the old
`testDedupedLiveGrantsDropsUnverifiableGrantWithoutHidingOthers` used two DIFFERENT grant ids, which
never exercised the collision path at all. Replaced with
`testDedupedLiveGrantsSameIdCollisionKeepsTheVerifiableGrant` — same id, a copy of the good grant
re-signed by an impostor identity (same claimed `ownerSigningPubKey`, wrong actual signer — the
literal forgery a compromised recipient device could attempt), bad record enumerated LAST (the exact
order that used to evict the good one). Kept the different-ids scenario as a separate test,
`testDedupedLiveGrantsDropsUnverifiableGrantAmongDifferentIds` (same body as before, renamed for
clarity — it's still a valid, distinct case: a bad grant under its own id must not hide a good grant
under a different id).

## M1 — flag-off delete scoping broke legacy re-share/edit

**File:** `Vaultify/Services/Sharing/ApprovalShareService.swift` (`publishGrant`, `sharedFieldRecordIDs`)

**Bug:** `publishGrant` always mints a fresh `grant.id`. The A1 delete was scoped to
`sharedFieldRecordIDs(grantId: grant.id, ...)` unconditionally — since that id has never existed
before this call, the scoped fetch always matched zero records, so the PRIOR grant's field blobs
were never deleted. Pre-A1, `publishGrant` deleted every field record in the zone on every call
(intentional clean-replacement, since a zone held at most one grant). With the flag OFF (a zone
still holds at most one grant, same as pre-A1), the owner's edit-sheet re-share flow
(`SharedGrantComposer`, used by both the create ceremony and the edit sheet) now orphans the
previous grant's ciphertext instead of replacing it — a real back-compat break on the delete side,
plus unbounded growth of dead `ApprovalSharedField` records.

**Fix:** `sharedFieldRecordIDs` now takes `grantId: String?`. `nil` matches every
`ApprovalSharedField` record in the zone by `recordType` alone (byte-for-byte the pre-A1 behavior);
non-nil keeps the existing decode-and-match-by-cleartext-field scoping. `publishGrant` passes
`FamilyShareTransport.perGrantEnabled ? grant.id : nil` — flag off restores the legacy
delete-everything-then-replace; flag on keeps the grantId-scoped delete (the "mints a duplicate
grant on re-share" gap under the flag is unchanged and already documented as deferred to A2 — this
fix did not touch that).

`republishSharedValues` was explicitly NOT touched — its scoped delete already uses the CURRENT
(not freshly-minted) `grant.id` fetched via `fetchGrantFresh`, so "republish A → B untouched" was
already correct there; passing a non-optional `String` into the new `String?` parameter is valid
Swift with zero textual change at that call site.

```swift
// publishGrant, before
let staleBlobIDs = try await sharedFieldRecordIDs(grantId: grant.id, zoneID: zoneID)

// publishGrant, after
let staleBlobIDs = try await sharedFieldRecordIDs(
    grantId: FamilyShareTransport.perGrantEnabled ? grant.id : nil, zoneID: zoneID)
```

No new test added for this one (it's an integration-shaped behavior — "publish once, edit, publish
again, confirm only one grant's worth of field records exist" — that needs the same CloudKit
plumbing the rest of `ApprovalShareService` has never had unit coverage for, consistent with this
codebase's existing convention of leaving CloudKit I/O to the device checklist). Flagged here instead
of silently assumed covered.

## M2 — sequential per-grant→legacy fetch doubled AutoFill fill-gate latency

**Files:** `VaultifyCore/Sharing/SharedGrantLiveCheck.swift` (`verify`),
`VaultifyCore/Sharing/PasskeyApprovalTransport.swift` (`submitRequest`)

**Bug:** both gates tried the per-grant record name first, and only on a definitive miss fell back
to the legacy name — sequentially. Since `FamilyShareTransport.perGrantEnabled` is off by default,
EVERY call today hits the per-grant miss, meaning every AutoFill fill and every passkey
askEachTime request pays a full extra CloudKit round trip before even starting the (real) legacy
fetch, inside the SAME fixed timeout budget — worst case, doubles the chance of hitting the deadline
and fail-closing a fill that would have succeeded with more budget.

**Fix — `SharedGrantLiveCheck.verify`:** replaced the sequential fetch with `async let` probes of
both record names, awaited together, still inside the single existing `withDeadline` budget (not
doubled). Added `ProbeResult` (`.found(AccessGrant)` / `.definitelyAbsent` / `.inconclusive`) so the
two probe outcomes can be reconciled without losing the `revoked` vs `unavailable` distinction
(INV-03):
- either probe `.found` → prefer the per-grant one, authorize/revoke by comparing the decoded `id`
- BOTH `.definitelyAbsent` (unknownItem/zoneNotFound/userDeletedZone on both) → `.revoked`
- anything else (either probe `.inconclusive` — transient error OR a malformed/undecoded record) →
  `.unavailable`

This means an expected per-grant miss (flag off) paired with a real legacy revocation still reads
`.revoked` (both probes are definitive-absence); a transient network hiccup on either probe never
gets misread as `.revoked`; a malformed record is still never treated as proof of absence.

**Fix — `PasskeyApprovalTransport.submitRequest`:** same concurrent-probe shape via a new
`fetchRecordOrNil` helper (`try?`-collapsing, matching this file's existing error style) — no
revoked/unavailable distinction needed here since this file only ever throws one generic
`Failure.grantUnavailable` on a miss, same as before.

The looser-budget recipient-projection paths (`ApprovalRecipientService.fetchGrantRecord`,
`fetchDisplayEnvelopePayload`) were left sequential, as instructed — those aren't on the 4s fill-gate
budget.

No new unit test added — both fixes are pure latency/concurrency-shape changes with no change to
observable outcomes for any input that was already covered (`SharedAccessAuthorizerTests`, which
exercises the `revoked`/`unavailable`/`authorized` outcome mapping this gate feeds into, still passes
unmodified — see Tests below).

## Verification

```
tuist generate --no-open
xcodebuild -workspace Vaultify.xcworkspace -scheme Vaultify -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd \
  CODE_SIGNING_ALLOWED=NO
→ ** BUILD SUCCEEDED **   (0 error: lines; 0 warning: lines in any touched file;
   app + VaultifyAutoFill + VaultifySafari all compiled/linked/embedded)
```

Targeted test run (widened beyond the two files this round touches, to re-verify nothing in the
surrounding sharing-kernel test suite regressed):

```
FamilyShareTransportTests   12/12  (includes the new H1 regression test)
SharedItemsProjectionTests   4/4
SharedAccessAuthorizerTests  5/5   (the Outcome mapping the M2 gate feeds — unaffected)
ApprovalKernelTests, GrantWireV2Tests, ApprovalRequestWireV2Tests, SharedGrantComposerTests
                             33/33 (untouched files, re-run as a regression guard)
── Selected tests: 54/54, 0 failures ──
** TEST SUCCEEDED **
```

`git diff --name-only` (whole session): 10 modified + 2 new source/test files, all within
`VaultifyCore/Sharing`, `VaultifyCore/Models`, `Vaultify/Services/Sharing`, `VaultifyTests` — zero
files matching crypto/HPKE/seal source (`ApprovalCrypto.swift`, `ApprovalSeal.swift`, HPKE code all
untouched). The only "crypto" string matches in the diff are plan `.md` files whose directory name
contains "crypto" (`plans/260715-1848-family-devices-crypto/*.md`), not source.

## Files changed this round

| File | Change |
|---|---|
| `Vaultify/Services/Sharing/ApprovalRecipientService.swift` | H1: verify-before-dedupe reorder in `dedupedLiveGrants`. |
| `Vaultify/Services/Sharing/ApprovalShareService.swift` | M1: `sharedFieldRecordIDs(grantId: String?)`; `publishGrant` flag-gates the delete scope. |
| `VaultifyCore/Sharing/SharedGrantLiveCheck.swift` | M2: concurrent `ProbeResult`/`probe` replacing sequential fetch in `verify`. |
| `VaultifyCore/Sharing/PasskeyApprovalTransport.swift` | M2: concurrent `fetchRecordOrNil` probes replacing sequential fetch in `fetchGrant`. |
| `VaultifyTests/FamilyShareTransportTests.swift` | H1 test: same-id collision case replaces the old false-coverage test; different-ids case kept as a separate test. |
| `plans/reports/fullstack-260715-1955-a1-per-grant-transport.md` | Corrected the "flag off reproduces legacy byte-for-byte on the delete side" claim (was inaccurate pre-M1) and the `publishGrant` "structural no-op" deviation note (now flag-ON-only). |

Status: DONE
Fixes applied: H1 (verify-before-dedupe, `ApprovalRecipientService.swift`) / M1 (flag-gated delete-all vs scoped-delete, `ApprovalShareService.swift`) / M2 (concurrent per-grant+legacy probe, `SharedGrantLiveCheck.swift` + `PasskeyApprovalTransport.swift`)
Compile: PASS (`** BUILD SUCCEEDED **`, 0 errors, app + VaultifyAutoFill + VaultifySafari)
Tests: 54/54 (12 FamilyShareTransportTests incl. new H1 regression test, 4 SharedItemsProjectionTests, 38 re-verified sharing-suite tests)
Crypto files touched: none (`ApprovalCrypto.swift`, `ApprovalSeal.swift`, HPKE code untouched — confirmed via `git diff --name-only`)
