# Phase 05 — Conflict-safe participant profile publish (multi-device race)

## Context links

- Audit §3-S2 (silent device drop), §3-S6 (why LWW bites here), §5-R6
- Race site: `ApprovalRecipientService.publishProfile` (`Vaultify/Services/Sharing/ApprovalRecipientService.swift:69-109`), save at `:106-108` with `savePolicy: .allKeys`
- Merge helpers (exist, pure): `ParticipantProfileMerge` (`VaultifyCore/Sharing/ApprovalModels.swift:161`), already unit-tested (`VaultifyTests/DeviceHPKEIdentityTests.swift:43-53`)

## Overview

- **Priority:** P1 (availability-of-security-material bug)
- **Status:** completed
- **Description:** `publishProfile` does fetch → merge → save with `.allKeys`, which ignores the server change tag. Two of B's devices resuming acceptance concurrently last-writer-win: the loser's HPKE directory entry and signing key vanish, so single-device grants sealed to that device dead-end in a Tier-0 placeholder. Switch to `.ifServerRecordUnchanged` with a bounded refetch → re-merge → retry loop.

## Key insights

- The profile is the ONLY multi-writer singleton in the model; owner-written singletons keep their deliberate LWW (`ApprovalConfig.swift:33-35`). Do NOT touch `respond()` — its `.allKeys` is a deliberate idempotency device for single-writer retries (`ApprovalShareService.swift:349-353` comment).
- On `.serverRecordChanged`, CloudKit hands back the live server record in the error (`CKError.serverRecord`); re-running the existing merge (`ParticipantProfileMerge.signingKeys` union + `directory` upsert, `ApprovalRecipientService.swift:86-89`) onto THAT record and re-saving converges — both devices survive.
- Save is a batch API; the per-record error surfaces from `saved.saveResults` `result.get()` (`ApprovalRecipientService.swift:108`) — catch there, not around the whole call.
- Concurrent CREATE (record doesn't exist yet, both devices insert): CloudKit reports `.serverRecordChanged` with the winner as `serverRecord` — the same retry path handles it; no special case.
- `publishProfile` is called from `completeAcceptance` per zone (`ApprovalRecipientService.swift:132-139`) which is itself retried by the 6-attempt resume backoff — an exhausted conflict loop may throw and rely on that outer retry.

## Requirements

**Functional**
1. Save with `.ifServerRecordUnchanged`.
2. On `.serverRecordChanged`: take `error.serverRecord`, re-merge own signing key + HPKE entry + rendezvous pointers onto it, retry. Bounded (3 attempts), then rethrow.
3. Merge semantics unchanged: signing keys unioned, directory upserted by `deviceKeyID`, `participantPubKey`/`createdAtUnixMs`/inbox pointers applied as today (`ApprovalRecordMapping.applyParticipantProfile`, `ApprovalRecordMapping.swift:156`).

**Non-functional**
- No signature change for callers (`completeAcceptance`, `ApprovalRecipientService.swift:135`).
- Keep function under control by extracting the "apply merged fields to a CKRecord" step into a private helper used by both the first attempt and retries (DRY).

## Architecture

```
attempt 1..3:
  base = fetched-or-new record (attempt 1) | error.serverRecord (retries)
  merged keys/directory = ParticipantProfileMerge(existing-from-base, own entry)
  applyParticipantProfile(to: base, ...)
  save(policy: .ifServerRecordUnchanged)
    ok → return
    .serverRecordChanged → loop with error.serverRecord
    other error → rethrow
exhausted → rethrow last (outer resume backoff covers transient storms)
```

## Related code files

**Modify**
- `Vaultify/Services/Sharing/ApprovalRecipientService.swift:69-109` — restructure `publishProfile` into helper + retry loop; comment explains the multi-writer conflict (two devices resuming the same invite) as the WHY.

**Create / delete:** none. (No UI, no strings.)

## Implementation steps

1. Extract `private func mergedProfileRecord(base: CKRecord?, recordID: CKRecord.ID, identity:, ownEntry:, nowUnixMs:) async -> CKRecord` — encapsulates existing lines `:81-105` (decode base if present, union/upsert, `applyParticipantProfile`). Note `inviteRecipientID` needs the async `container.userRecordID()` — fetch it once before the loop, not per attempt.
2. Rewrite save section (`:106-108`) as a `for attempt in 0..<3` loop: save with `.ifServerRecordUnchanged`; unwrap per-record result; on `CKError.serverRecordChanged`, pull `error.serverRecord` (fallback: refetch by id if nil), rebuild via the helper, continue; on success return; otherwise throw.
3. `ShareDiagnostics.log` each conflict retry (owner-visible QA trail, consistent with `:136`).
4. Compile check.
5. Manual QA note for the release checklist: accept the same invite on two of B's devices near-simultaneously (or simulate by re-running resume on device 2 immediately after device 1); verify the owner-side profile lists BOTH `deviceKeyID`s (`fetchParticipantProfile`, `ApprovalShareService.swift:153-159`), then a single-device grant to device 1 still decrypts on device 1.

## Todo list

- [x] Extract merged-record helper (fetch userRecordID once)
- [x] `.ifServerRecordUnchanged` + 3-attempt conflict loop
- [x] Diagnostics on retry
- [x] Compile check
- [ ] Two-device QA note recorded in PR description (deferred to PR creation — checklist assembled in phase 7)

## Success criteria

- Unit (phase 7): merge idempotence/union already pinned; add a conflict-sequence test at the merge layer (server record with device A entry + incoming device B → both present; repeat inverse order → same set).
- Two-device QA: no vanished directory entry; INV-04 single-device grant remains decryptable by its bound device.
- Single-device path (the common case) behaviorally unchanged: one save, no retries.

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| `.ifServerRecordUnchanged` on a record freshly fetched via shared DB but saved after a long pause → spurious conflicts | L×L | Retry loop absorbs them (refetch-and-merge is the recovery, not a failure). |
| `error.serverRecord` nil on some CK error shapes | L×M | Fallback refetch by recordID inside the retry branch. |
| Behavior drift in merge during extraction | L×H | Zero-logic move: reuse the exact existing `ParticipantProfileMerge` + `applyParticipantProfile` calls; phase 7 merge tests pin the semantics. |

## Security considerations

- Strengthens INV-04 availability: a device's published HPKE key can no longer be silently erased by a sibling device.
- No change to what is published (same fields, same zone, same visibility).

## Next steps

Independent; feeds phase 7 tests (merge-conflict coverage).
