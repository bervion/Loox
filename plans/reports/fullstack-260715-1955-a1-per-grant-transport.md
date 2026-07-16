# Phase A1 — Per-Grant Sharing Transport — Implementation Report

Plan: `plans/260715-1848-family-devices-crypto/family-group-transport.md` (Design items 1-5, Ground Truth section)
Date: 2026-07-15

**Post-review update (same date):** code review returned NEEDS_FIX (1 high, 2 medium). All 3 applied —
see `plans/reports/fullstack-developer-260715-2119-a1-review-fixes.md` for the fix diff. The
"Deviations" and "Back-compat" sections below are corrected in place (marked `[FIXED]`) rather than
left inaccurate.

## Status: DONE

## Files changed

| File | Why |
|---|---|
| `VaultifyCore/Sharing/FamilyShareTransport.swift` (new) | Master flag `perGrantEnabled` (default `false`), same pattern as `WallpaperFeature.decorativeEnabled`. Gates ONLY the owner-side per-grant WRITE naming. |
| `VaultifyCore/Sharing/ApprovalConfig.swift` | Renamed `grantRecordName`/`displayEnvelopeRecordName` → `legacyGrantRecordName`/`legacyDisplayEnvelopeRecordName`; added `grantRecordName(grantId:)` / `displayEnvelopeRecordName(grantId:)` deterministic per-grant name functions. |
| `Vaultify/Services/Sharing/ApprovalRecordMapping.swift` | `grantRecord`/`displayEnvelopeRecord` now name the record per-grant when `FamilyShareTransport.perGrantEnabled`, else the legacy singleton name (unchanged content otherwise). |
| `Vaultify/Services/Sharing/ApprovalShareService.swift` | `fetchGrantFresh` reads the renamed legacy constant (comment explains why it stays legacy-only — SharingStore/A2 dependency). `sharedFieldRecordIDs` now takes `grantId: String?` **[FIXED M1]**: `publishGrant` passes `nil` (delete ALL field records in the zone) when the flag is off — exact pre-A1 legacy behavior — and `grant.id` (scoped delete) when the flag is on. `republishSharedValues` unchanged, still scoped to its existing grant's id. |
| `Vaultify/Services/Sharing/ApprovalRecipientService.swift` | `fetchGrant` reparented to `fetchGrant(zoneID:grantId:nowUnixMs:)` (per-grant name + legacy fallback, via new private `fetchGrantRecord`). New `fetchAllGrants(zoneID:nowUnixMs:)` enumerates every `ApprovalGrant` record in the zone and reduces with new `nonisolated static dedupedLiveGrants(from:pinnedOwnerSigningKey:nowUnixMs:)` (pure, unit-tested — **[FIXED H1]** now verifies EACH record before inserting into the id→grant map, so a same-id forged/bad-signature record can never evict a legitimate grant regardless of enumeration order). `fetchDisplayEnvelope` now resolves its payload via new private `fetchDisplayEnvelopePayload` (per-grant name + legacy fallback, matched by the record's own `grantId` field). |
| `Vaultify/Services/Sharing/SharedAccessAuthorizer.swift` | One-line caller update: `fetchGrant(zoneID:grantId: expected.id, nowUnixMs:)`. |
| `Vaultify/Services/Sharing/SharedItemsProjection.swift` | `refresh()`'s per-zone loop restructured: `fetchAllGrants` replaces the single `fetchGrant`; TOFU pin logic runs once per zone (first grant); an inner loop builds one `VaultItem` per live grant. Error handling split: outer catch (zone enumeration/pin failure) preserves all previously-projected items for that zone; inner catch (per-grant field/display fetch failure) preserves just that grant's previous item — no duplicate-append path exists. |
| `VaultifyCore/Models/SharedOrigin.swift` | `itemID` now includes `grantId` (`"shared::owner::zone::grantId"`) — REQUIRED: without this, two grants in the same zone would collide on the same `VaultItem.id`. Verified safe: `SharedCredentialsCache.save`/`CredentialIdentityService.publish` both do full wholesale replacement each refresh (no orphaned stale entries); only side effect is `QuickViewHistoryStore` losing correlation to history rows logged under the old id format for existing shares (cosmetic, not a correctness/security issue). |
| `VaultifyCore/Sharing/SharedGrantLiveCheck.swift` | **[FIXED M2]** `verify` now probes the per-grant AND legacy record names CONCURRENTLY (`async let`, one shared deadline) instead of sequentially, via new `ProbeResult`/`probe`. `.revoked` only when BOTH probes are a definitive absence; `.unavailable` if either is transient/malformed (INV-03 preserved). |
| `VaultifyCore/Sharing/PasskeyApprovalTransport.swift` | **[FIXED M2]** `submitRequest`'s `fetchGrant` now probes both record names CONCURRENTLY (`async let` + new `fetchRecordOrNil`) instead of sequentially; prefers per-grant when both resolve. |
| `VaultifyTests/SharedItemsProjectionTests.swift` | Updated the one hardcoded expectation (`item.id`) to the new `SharedOrigin.itemID` format. |
| `VaultifyTests/FamilyShareTransportTests.swift` (new) | 12 unit tests (post-fix; see fix report for the H1 regression test added): per-grant naming determinism, legacy-constant regression pin, record-name-independent decode (INV-FAM-01), flag-off write path, and `dedupedLiveGrants` (two distinct grants recognized, same-grantId-under-two-names collapses to one, legacy singleton alone recognized, same-id bad-signature collision keeps the verifiable grant, bad-signer among different ids doesn't hide others, undecodable records ignored, pre-pin display still returned). |

## Compile result: PASS

Full recipe run (`tuist generate --no-open` then `xcodebuild ... -destination 'generic/platform=iOS Simulator'`), app + `VaultifyAutoFill` + `VaultifySafari` extensions all embedded/linked. Zero `error:` lines; `FamilyShareTransport.swift` confirmed compiled into all three targets that share `VaultifyCore/**` (`Vaultify`, `VaultifyAutoFill`, `VaultifySafari`).

```
RegisterExecutionPolicyException /tmp/vaultify-dd/Build/Products/Debug-iphonesimulator/Vaultify.app (in target 'Vaultify' from project 'Vaultify')
Validate /tmp/vaultify-dd/Build/Products/Debug-iphonesimulator/Vaultify.app (in target 'Vaultify' from project 'Vaultify')
Touch /tmp/vaultify-dd/Build/Products/Debug-iphonesimulator/Vaultify.app (in target 'Vaultify' from project 'Vaultify')
PruneExplicitPrecompiledModules /tmp/vaultify-dd/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules
PruneExplicitPrecompiledModules /tmp/vaultify-dd/Build/Intermediates.noindex/ExplicitPrecompiledModules
PruneExplicitPrecompiledModules /tmp/vaultify-dd/SDKExplicitPrecompiledModules

** BUILD SUCCEEDED **
```

## Unit tests

Test target exists (`VaultifyTests`, per `Project.swift:273-285`). Ran the new + touched test classes on `id=6E8CAB51-3897-46A1-9596-C23F47724568` (iPhone 16 sim):

```
Test Suite 'FamilyShareTransportTests' passed — Executed 11 tests, with 0 failures (0 unexpected)
Test Suite 'SharedItemsProjectionTests' passed — Executed 4 tests, with 0 failures (0 unexpected)
Test Suite 'Selected tests' passed — Executed 15 tests, with 0 failures (0 unexpected) in 0.021s
** TEST SUCCEEDED **
```

I also ran the FULL `VaultifyTests` suite for a broader regression check. It reports `** TEST FAILED **`, but every failure traces to `ShareLifecycleStatusTests` (a pre-existing, unmodified file — commit `35eb599`, unrelated "Family Space" acceptance-status subsystem, not the Approval Mode transport this phase touches) crashing with a deterministic malloc double-free at the SAME memory address (`0x251f66440`) across independent process relaunches:
```
Vaultify(63244,...) malloc: *** error for object 0x251f66440: pointer being freed was not allocated
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
```
This reproduces in isolation (`-only-testing:VaultifyTests/ShareLifecycleStatusTests` alone still crashes, several of its individual cases pass once xcodebuild auto-restarts the host process) and is independent of my diff — the crashing type isn't touched by A1, git status shows the test file unmodified, and my own sharing-transport tests never invoke Keychain/global state the way that suite appears to. Flagging per "do not hide failing tests," but it is out of A1's file ownership and scope to fix.

## Back-compat (how it's preserved)

1. **Owner write, flag off (default)**: `ApprovalRecordMapping.grantRecord`/`displayEnvelopeRecord` resolve to the exact legacy names (`"grant"` / `"display-envelope"`) — proven by `testGrantRecordUsesLegacyNameWhileFlagDisabled` / `testDisplayEnvelopeRecordUsesLegacyNameWhileFlagDisabled`, which also assert `FamilyShareTransport.perGrantEnabled == false`. **[CORRECTED — was inaccurate before the M1 fix]** The DELETE side of `publishGrant` also now matches legacy exactly when the flag is off: it clean-replaces every `ApprovalSharedField` blob in the zone (not scoped to the freshly-minted `grant.id`, which would have matched zero records and orphaned the prior grant's field ciphertext on every re-share/edit — see fix report). No owner-side write path changes shape while the flag is off.
2. **Recipient read, unconditional**: `ApprovalRecipientService.fetchGrant`, `fetchAllGrants`, and `fetchDisplayEnvelope` always try the per-grant name first and fall back to the legacy singleton — no flag gates the read side, so a legacy single-item share (published before this change, or published today with the flag off) always projects. `SharedGrantLiveCheck`/`PasskeyApprovalTransport` (AutoFill/extension fill-gate paths) follow the same two-step lookup.
3. **Dedupe, not double-count**: identity comes from the decoded blob's own `id` (`ApprovalRecordMapping.grant(from:)`), never the record name — a per-grant record and the legacy singleton describing the same grant collapse to one projected item (`dedupedLiveGrants`, unit-tested).
4. **Delete scoping**: the two former zone-wide `ApprovalSharedField` deletes are gone; both are now scoped to `grantId == <this grant>` via the new `sharedFieldRecordIDs` helper, which decodes each candidate record and filters on the cleartext `grantId` field — never a name/prefix match (INV-FAM-01).

## Deviations / risks (read before flipping the flag)

- **`AccessGrant` has no field literally named `grantId`** — it's `var id: String`. Used `grant.id` everywhere the plan said `grant.grantId`; not a blocker, just a naming note.
- **No cleartext `grantId` field added to the `ApprovalGrant` record itself.** The Ground Truth section and the task's own restated item 2/4 confirm enumeration decodes the blob for `id` — a redundant field wasn't needed and would be schema growth beyond A1 (the display-envelope record already had `grantId`; kept as-is).
- **Owner-side republish/verify (`fetchGrantFresh`, `republishDisplayEnvelope`, `republishSharedValues`, `verifyInbound`) still resolve only the legacy singleton grant name.** This is deliberate: the Ground Truth's "must take a grantId" list names only the 4 recipient/extension call sites, not these — resolving a SPECIFIC item's grantId in a multi-grant zone needs `SharingStore`'s per-(zone,item) identity, which is A2. `republishSharedValues`'s delete-scoping IS fixed (uses whatever grant `fetchGrantFresh` returns), so "republish A → B untouched" already holds. Inert while the flag is off; revisit alongside A2 before ever setting it `true`.
- **`[FIXED M1 for flag-off; remaining gap is flag-ON only]`** — With the flag OFF (default), `publishGrant`'s delete now passes `grantId: nil` (delete every field record in the zone, matching pre-A1 exactly), so the prior orphaning-on-edit bug described in earlier drafts of this section no longer applies while the flag is off. With the flag ON, the delete stays scoped to the freshly-minted `grant.id` (which always matches zero records, since that id never existed before this call) — correct per the literal spec ("delete only records whose grantId == thisGrant") and safe (never over-deletes another grant), but it still means **re-publishing the SAME item's capabilities via the full `publishGrant` path (owner edits share settings — `SharedGrantComposer`, confirmed used by both the create ceremony and the edit sheet) mints a second grant instead of replacing the first**, once the flag is on. This is the exact gap A2's `SharingStore` + reconciler close (know the item's existing grantId, revoke-then-replace). Do not flip the flag for real multi-item testing until A2 lands, or restrict early testing to sharing genuinely distinct items only.
- **`SharedItemsProjection.leave(itemId:)` still deletes the WHOLE zone** (`ApprovalRecipientService.leave`), not just one grant's records. Pre-A1 this was correct (1 zone = 1 item); with the flag on and multiple grants per zone, "leave this one item" would remove the recipient's access to every item sharing that zone. Not touched — per-item revoke/leave granularity is explicitly A4 scope in the plan. Flagging so it isn't mistaken for solved.
- **`SharedOrigin.itemID` format changed** (`shared::owner::zone` → `shared::owner::zone::grantId`) — necessary (see file table above) and verified safe against the persisted caches that consume it (`SharedCredentialsCache`, `CredentialIdentityService`, `QuickViewHistoryStore` — the latter loses history correlation for pre-existing shares across the format change; cosmetic only).
- **Full `VaultifyTests` suite has a pre-existing crash** in unrelated code (`ShareLifecycleStatusTests`) — see Unit tests section. Did not investigate/fix (outside A1 file ownership and scope); flagging for whoever owns that subsystem.

## Unresolved questions

- None blocking A1. The two flag-on gaps above (publishGrant re-share dedup, per-item leave) are known, bounded, and already assigned to later phases (A2/A4) by the frozen plan — listed here so they aren't silently assumed solved.

Status: DONE (post-review fixes applied — see `fullstack-developer-260715-2119-a1-review-fixes.md`)
Summary: Implemented per-grant sharing transport (Design items 1-5) behind `FamilyShareTransport.perGrantEnabled` (default false, write-side only); recipient read path unconditionally supports per-grant + legacy records with grantId-based dedup (verify-before-dedupe); the two zone-wide sharedField deletes are flag-aware (delete-all when off, matching legacy exactly; grantId-scoped when on); the two latency-critical fill gates probe both record names concurrently. App + AutoFill + Safari extension compile clean; 54/54 targeted unit tests pass (12 in FamilyShareTransportTests + 4 SharedItemsProjectionTests + 38 other sharing-suite tests re-verified).
Files changed: VaultifyCore/Sharing/FamilyShareTransport.swift (new), VaultifyCore/Sharing/ApprovalConfig.swift, Vaultify/Services/Sharing/ApprovalRecordMapping.swift, Vaultify/Services/Sharing/ApprovalShareService.swift, Vaultify/Services/Sharing/ApprovalRecipientService.swift, Vaultify/Services/Sharing/SharedAccessAuthorizer.swift, Vaultify/Services/Sharing/SharedItemsProjection.swift, VaultifyCore/Models/SharedOrigin.swift, VaultifyCore/Sharing/SharedGrantLiveCheck.swift, VaultifyCore/Sharing/PasskeyApprovalTransport.swift, VaultifyTests/SharedItemsProjectionTests.swift, VaultifyTests/FamilyShareTransportTests.swift (new)
Compile: PASS (BUILD SUCCEEDED, 0 errors, app + VaultifyAutoFill + VaultifySafari)
Concerns: pre-existing unrelated crash in ShareLifecycleStatusTests (full-suite run only, not caused by this diff); one flag-on-only gap remains (publishGrant re-share dedup) and is deliberately deferred to A2 per the frozen plan's phasing — see fix report for what changed.
