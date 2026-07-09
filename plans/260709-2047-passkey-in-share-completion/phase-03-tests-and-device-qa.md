# Phase 03 — Tests + Device QA

## Context Links
- Overview: [plan.md](plan.md)
- After: [phase-01](phase-01-owner-edit-share-passkey-management.md),
  [phase-02](phase-02-recipient-inapp-passkey-display.md)

## Overview
- **Priority**: P1
- **Status**: pending
- **Description**: Unit-cover the composer's pure mapping; 2-account device QA of the passkey
  share lifecycle (CloudKit parts aren't unit-testable).

## Requirements
Unit (`VaultifyTests`):
- `SharedGrantComposer`: given item + capabilities + itemPasskeys + profile, it produces the
  expected `displayPasskeys`, hand-over `sharedValues` (only for `mode == .shared`), and
  `allowedDevices` (single-device picks the bound device; multi ⇒ empty). Pure, no CloudKit.
- Device-scope preservation: a loaded grant with non-empty `allowedDeviceKeyBindings` maps back to
  single-device intent; empty ⇒ multi.
- Passkey capability seeding from a grant round-trips (slot id ↔ mode).

Manual (2 iCloud accounts, ≥1 physical device):
- CREATE: share a login with a passkey, toggle passkey ON → recipient AutoFill offers the passkey;
  in-app recipient shows the Passkeys section (Phase 2).
- EDIT existing share: passkey row visible with correct state; toggle ON + Apply → recipient gains
  it; toggle OFF + Apply → removed on next refresh; a field-only edit does NOT drop an
  already-granted passkey.
- Single-device share with a passkey: editing capabilities keeps it single-device (not widened).
- Hand-over vs Ask-each-time passkey both behave (sign locally vs owner approval).

## Related Code Files
Create:
- `VaultifyTests/SharedGrantComposerTests.swift` (+ any fixture helpers).

## Implementation Steps
1. Add composer unit tests.
2. `make test DEST=<sim-udid>` green.
3. Run the manual matrix; log results in this phase's report.

## Todo List
- [ ] Composer mapping tests
- [ ] Device-scope preservation test
- [ ] Capability seeding test
- [ ] `make test` green
- [ ] Manual 2-account matrix logged

## Success Criteria
- New unit tests pass; existing suite unaffected.
- Every manual path behaves; no passkey/device-scope loss on edit.

## Risk Assessment
- CloudKit propagation can make manual QA flaky → allow a foreground re-check; use the existing
  `ShareDiagnostics` `PASSKEY` line to confirm `matched` count.

## Security Considerations
- Tests use synthetic keys only; no real secrets committed.

## Next Steps
- Merge after QA; fold the DEBUG `ShareDiagnostics` decision (keep vs strip) into the release cut.
