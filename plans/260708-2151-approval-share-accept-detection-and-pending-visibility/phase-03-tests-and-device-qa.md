# Phase 03 — Tests + On-Device QA

## Context Links
- Overview: [plan.md](plan.md)
- After: [phase-01](phase-01-reliable-acceptance-detection.md), [phase-02](phase-02-pending-share-visibility-and-resume.md)

## Overview
- **Priority**: P1
- **Status**: pending
- **Description**: Unit-cover the status model + refresh logic; manual 2-account device QA of the
  full share lifecycle (the CloudKit parts can't be unit-tested without accounts).

## Key Insights
- Pure/deterministic logic (status derivation, back-compat decode, transition→notify) is
  unit-testable in `VaultifyTests`. CloudKit acceptance/propagation needs real devices.
- Run tests via `make test DEST=...` (needs concrete sim UDID) — see project test convention.

## Requirements
Unit:
- `ShareLifecycle` derivation from (acceptanceStatus, profilePresent, fingerprintConfirmed).
- `ItemShareRecord` back-compat decode: legacy JSON (no `statusRaw`) → correct default.
- Transition detection in `OwnerShareRefresher` fires notification only on a real upgrade
  (idempotent refresh = no duplicate notify).
- Resume routing: given a record status, `ShareAccessSheet` picks the correct entry step
  (extract the routing decision into a pure function to test without SwiftUI).

Manual (2 iCloud accounts, ≥1 physical device — CKShare accept can't run on 2 sims easily):
- Happy path: A shares → B accepts (unlocked) → A auto-advances to fingerprint → confirm → B sees
  values. No stuck Waiting.
- Locked-B path: B accepts while locked → A shows "Accepted — finishing on their device"; B
  unlocks → A upgrades to "Ready to confirm".
- Dismiss/kill path: A dismisses waiting + kills app → reopens → pending share visible in
  Notifications with live status; resume without email re-entry.
- Notification path: A backgrounded, B accepts → A gets local notification → tap resumes.
- macOS-B path (if a Mac is available): accept on Mac sets breadcrumb → profile publishes.
- Passkey item: confirm sharing a passkey item is unaffected (regression guard).

## Related Code Files
Modify/Create:
- `VaultifyTests/` — new test file(s) for status model, decode, transition, routing.

## Implementation Steps
1. Extract testable pure helpers (status derivation, resume-step routing) if not already pure.
2. Write unit tests per the list above.
3. `make test DEST=<sim-udid>` — all green.
4. Execute the manual QA matrix on 2 accounts; record results in this phase's report.
5. File any follow-ups (e.g. zone-subscription stretch) as separate notes.

## Todo List
- [ ] Unit: status derivation
- [ ] Unit: legacy decode default
- [ ] Unit: transition→notify idempotency
- [ ] Unit: resume-step routing
- [ ] `make test` green
- [ ] Manual 2-account QA matrix executed + logged
- [ ] Passkey regression check

## Success Criteria
- All new unit tests pass; existing suite unaffected.
- Every manual path behaves per Phase 1/2 success criteria — no stuck "Waiting", no blind pending.

## Risk Assessment
- **CloudKit propagation latency** can make manual QA flaky → allow one foreground re-check;
  document observed timings.
- **Two-sim CKShare accept** is unreliable → prefer one physical device for the acceptor.

## Security Considerations
- Tests use synthetic data only; no real secrets. No credentials committed.

## Next Steps
- Ship via `make release` flow after QA sign-off (per CLAUDE.md CI/CD).
- Consider owner-side zone/database subscription for push-driven accept (deferred stretch).
