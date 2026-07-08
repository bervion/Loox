# Deep Audit — Recipient Never Publishes Profile (breadcrumb burn)

Date: 2026-07-08. Follow-up after the first fix shipped (PR #75). User reported still stuck —
screenshot showed status `.accepted` ("Họ đã chấp nhận — đang hoàn tất…"), proving Phase-1
detection works but the flow never reaches milestone 2 (owner fetches B's `participant-profile`).

User confirmed: **two different Apple IDs** (proper cross-account share). Same-account self-share
was ruled out.

## Root cause (verified)

`ApprovalRecipientService.completeAcceptance` published to **zero zones and returned success**
when the accepted CKShare zone had not yet propagated into B's shared DB. `container.accept`
returns before `sharedCloudDatabase.allRecordZones()` lists the new `apz-` zone, so B's first
resume pass (fired on `.vaultShareAccepted` → `recipientChangeCounter`, right after accept)
enumerates zero zones.

Because zero-zone was not a throw, the caller treated it as done and **deleted the resume
breadcrumb** (`VaultShellBehaviors.resumePendingShareAcceptance`, old line 132). The shell resume
is guarded on that breadcrumb, so every later unlock/foreground early-returned — **permanent
disarm**. The catch-block comment "retried on next pass" was a false promise: only a *throw*
preserved the flag; empty-zone success cleared it. B never published; A's `fetchParticipantProfile`
failed forever → stuck on "accepted".

`SharedWithMeScreen.refresh` had the same premature-clear and was the only flag-independent
publisher, but requires B to manually open "Shared with Me".

## Fix (this branch)

- `completeAcceptance` returns the count of zones published (`@discardableResult -> Int`). **Zero
  is not success.**
- `resumePendingShareAcceptance`: clears the breadcrumb ONLY when `published > 0`; a zero-zone
  pass keeps the flag and retries with backoff (6 attempts, 2s→15s) to ride out propagation lag;
  reentrancy-guarded.
- Also re-triggered on every foreground activation (flag-gated → cheap no-op when nothing
  pending), so a share accepted moments earlier completes without needing a relock/unlock.
- `SharedWithMeScreen.refresh` clears the breadcrumb only on `published > 0`.

Owner side needs no change — `OwnerShareRefresher` + the waiting poll advance to
`readyForCeremony` automatically once B's profile lands.

## Recovery for the ALREADY-stuck share

Its breadcrumb on B is already burned, so the shell auto-resume won't re-fire for it. Recover by
opening **"Shared with Me"** on B once (flag-independent path, now fixed to publish). New shares
created after this fix complete automatically.

## Verification
- Compile check passes (app + extension). Full unit suite green (0 fail).
- CloudKit accept/propagation timing is not unit-testable → device QA required.

## Unresolved questions
- Same-account self-share is still unsupported (no shared-DB zone ever appears). Out of scope
  here; if desired later, needs a private-DB fallback or a fail-fast "can't share to yourself"
  guard. For the user's own multi-device, iCloud vault sync is the intended path, not sharing.
