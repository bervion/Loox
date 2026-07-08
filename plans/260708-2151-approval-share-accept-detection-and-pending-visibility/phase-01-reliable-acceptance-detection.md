# Phase 01 — Reliable Owner-Side Acceptance Detection

## Context Links
- Overview: [plan.md](plan.md)
- Diagnosis report: `plans/reports/` (verified code-trace, this session)

## Overview
- **Priority**: P0 (fixes the "A stuck on Waiting" defect)
- **Status**: pending
- **Description**: Make the owner learn that B accepted independently of the ephemeral
  in-sheet poll, using CloudKit `CKShare` acceptanceStatus + an off-sheet foreground refresh.

## Key Insights
- `CKShare.participants[].acceptanceStatus` flips to `.accepted` the moment B accepts —
  network-only, no dependency on B unlocking or publishing a profile. This is the missing
  authoritative signal.
- Two distinct milestones must be modeled separately:
  1. **Accepted** — CKShare acceptanceStatus == `.accepted` (B tapped accept).
  2. **Profile ready** — `fetchParticipantProfile` succeeds (B's device published keys;
     requires B unlocked). Only THIS enables `publishGrant`.
- Owner already fetches the CKShare (`ApprovalShareService.fetchShare`, private, line 126-129) —
  extend, don't reinvent.
- Refresh hook already exists: `VaultShellBehaviors.swift:70-74` calls
  `refreshOwnerRequests()` on `scenePhase == .active`. Add a sibling owner-share refresh there.

## Requirements
Functional:
- On foreground/unlock, for every `ItemShareRecord` with `!fingerprintConfirmed`, fetch its
  CKShare acceptance + participant profile and update a persisted status.
- Owner UI (waiting view + config "Shared with" row) shows: `Invite sent` / `Accepted —
  finishing on their device` / `Ready to confirm` / `Active`.
- If profile is ready while the sheet is CLOSED, the record status becomes `readyForCeremony`
  and the owner can resume the fingerprint step (wired in Phase 2).
- macOS accept path sets `pendingShareAcceptanceKey` (parity with iOS).

Non-functional:
- No crypto-invariant change. Grant sealing still gated on real profile (INV unchanged).
- Off-sheet refresh must be cheap (bounded record fetches, only unconfirmed records).
- MainActor isolation preserved; network work already async.

## Architecture
- **Status model** (`SharingStore.swift`): add `enum ShareLifecycle: String, Codable`
  `{ inviteSent, accepted, readyForCeremony, active }` + persisted `statusRaw` on
  `ItemShareRecord` (default `inviteSent`; `active` derived from `fingerprintConfirmed == true`
  for back-compat when decoding old records).
- **Service** (`ApprovalShareService.swift`):
  - `func participantAcceptance(zoneID:) async -> CKShare.ParticipantAcceptanceStatus?`
    (reads `fetchShare`, matches the single non-owner participant).
  - Keep `fetchParticipantProfile` as-is (the profile milestone).
  - `func refreshShareStatus(record:) async -> ShareLifecycle` combining both signals.
- **Refresh driver**: new `OwnerShareRefresher` (small `@MainActor` helper) iterating
  `env.sharingStore.shares.filter { !$0.fingerprintConfirmed }`, updating the store. Invoked
  from the existing scene hook in `VaultShellBehaviors`.
- **Sheet**: `pollForProfile` stays for the live case but ALSO advances the persisted status;
  waiting copy keys off the record status, not just profile presence.

## Related Code Files
Modify:
- `Vaultify/Features/Sharing/SharingStore.swift` — status enum + field + migration decode.
- `Vaultify/Services/Sharing/ApprovalShareService.swift` — acceptance read + combined refresh.
- `Vaultify/Features/Sharing/ShareAccessSheet.swift` — status-driven waiting copy; write status.
- `Vaultify/Features/Main/VaultShellBehaviors.swift` — invoke owner-share refresh on active/unlock.
- `Vaultify/App/AppPushDelegate.swift` — macOS branch sets `pendingShareAcceptanceKey`.
Create:
- `Vaultify/Services/Sharing/OwnerShareRefresher.swift` — foreground refresh pass (<120 loc).

## Implementation Steps
1. Add `ShareLifecycle` + `statusRaw` to `ItemShareRecord`; back-compat decode (old record →
   `fingerprintConfirmed ? .active : .inviteSent`). Add `SharingStore` mutators.
2. Add `participantAcceptance(zoneID:)` and `refreshShareStatus(record:)` to `ApprovalShareService`.
3. Create `OwnerShareRefresher.refreshAll()` — iterate unconfirmed records, call
   `refreshShareStatus`, `env.sharingStore.upsert` updated status. Gate on `approvalModeEnabled`.
4. Wire `OwnerShareRefresher` into `VaultShellBehaviors` scene `.active` + unlock task (beside
   `refreshOwnerRequests`).
5. `ShareAccessSheet`: drive `waitingView` copy from the record's `ShareLifecycle`; when
   `pollForProfile` fetches profile, set status `readyForCeremony` before moving to `.fingerprint`.
6. macOS `userDidAcceptCloudKitShareWith`: set `pendingShareAcceptanceKey = true` before accept.
7. `tuist generate` (new file) → compile check (`make check`).

## Todo List
- [ ] `ShareLifecycle` enum + persisted status + back-compat decode
- [ ] `participantAcceptance` + `refreshShareStatus` on service
- [ ] `OwnerShareRefresher` helper
- [ ] Scene/unlock wiring in `VaultShellBehaviors`
- [ ] Status-driven waiting copy in `ShareAccessSheet`
- [ ] macOS breadcrumb parity
- [ ] Localize new strings EN + VI
- [ ] `tuist generate` + `make check`

## Success Criteria
- After B accepts (vault locked), A (sheet closed, app relaunched) shows `Accepted — finishing
  on their device` within one foreground cycle — no longer stuck on generic "Waiting".
- After B unlocks + publishes, A's status becomes `Ready to confirm` off-sheet.
- Old persisted `ItemShareRecord`s decode without loss.
- Builds clean (app + extension).

## Risk Assessment
- **CKShare fetch cost on every foreground** → mitigate: only unconfirmed records, bounded.
- **acceptanceStatus semantics** (`.accepted` before profile) → intentional; UI distinguishes.
- **Decode migration** for existing records → covered by defaulting rule; add a unit test.

## Security Considerations
- Only public/ciphertext CloudKit data read; no plaintext, no vault key. ADR-2 intact.
- Status is device-local (UserDefaults) — no new sync surface.

## Next Steps
- Phase 2 consumes `ShareLifecycle` for the NotificationsScreen row, accept notification, and
  resume-from-record.
