# Phase 01 — Owner Edit-Share Passkey Management + Stop Grant Strip

## Context Links
- Overview: [plan.md](plan.md)
- Create-flow reference: `Vaultify/Features/Sharing/ShareAccessSheet.swift`
  `confirmFingerprintAndPublish` (passkey seal + device scope) — the behavior to mirror.

## Overview
- **Priority**: P0 (clear bug: edit sheet can't manage passkeys AND degrades the grant)
- **Status**: pending
- **Description**: Add passkey capability rows to `ShareRecipientDetailSheet`, seed them from the
  live grant, and make `applyCapabilities` + `sendUpdateNow` republish with passkeys and device
  scope intact instead of stripping them.

## Key Insights
- `ShareRecipientDetailSheet.capabilitySection` iterates only `item.fields`
  (`ShareRecipientDetailSheet.swift:99-119`); `applyCapabilities` (`:179-207`) calls `publishGrant`
  WITHOUT `displayPasskeys` / passkey `sharedValues` / `deviceScope` / `allowedDevices` → those
  default to empty/multi → passkeys removed, single-device downgraded to multi.
- `sendUpdateNow` (`:156-174`) republishes shared values from `item.fields` only — also drops
  passkey secrets on a manual push.
- CREATE already does it right (`confirmFingerprintAndPublish`): builds `displayPasskeys`, seals
  `PasskeySecret` for `mode == .shared`, resolves `allowedDevices` from the participant profile's
  `deviceHPKEDirectory`, passes all to `publishGrant`.
- The grant carries `allowedDeviceKeyBindings` (single-device) — non-empty ⇒ was single-device.
- `PasskeyCapabilityRow` is already a standalone reusable view
  (`Vaultify/Features/Sharing/PasskeyCapabilityRow.swift`).

## Requirements
Functional:
- Edit sheet lists a `PasskeyCapabilityRow` for each of the item's passkeys (same
  `repository.passkeys` RP-matched source as CREATE + the detail screen).
- Rows seed their mode from the loaded grant's passkey slot capabilities
  (`grant.capabilities[PasskeySlot.slotId(...)]`), defaulting to `.passkey(.none)`.
- `applyCapabilities` republishes the grant preserving: granted passkeys (display meta + sealed
  secret for hand-over) AND the grant's existing device scope (single vs multi) via freshly
  fetched participant profile.
- `sendUpdateNow` re-pushes passkey secrets for currently-granted hand-over passkeys too.
- Turning a passkey OFF removes it on the recipient's next refresh (parity with fields).

Non-functional:
- DRY: extract the shared "compose + publish grant (fields + passkeys + device scope)" into one
  reusable path (ADR-P2) used by both CREATE and EDIT. No crypto-kernel changes.
- Preserve INV-04 (single-device never falls back to synced key): if the grant was single-device
  and the profile no longer yields the bound device, surface the existing `recipientNeedsUpdate`
  error rather than silently widening scope.

## Architecture
- **Composer**: `SharedGrantComposer` (new, `Vaultify/Services/Sharing/`) — pure-ish helper taking
  (item, capabilities, itemPasskeys, vaultKey, participant profile, epoch, zoneID, deviceScope
  intent) → assembles `sharedValues` (fields + hand-over passkey secrets), `displayFields`,
  `displayPasskeys`, `allowedDevices`, then calls `ApprovalShareService.publishGrant`. Both sheets
  call this. Keeps passkey/device logic single-sourced.
- **Edit sheet**: add `itemPasskeys` (repo source), render rows, extend `loadGrant` to seed passkey
  caps + capture prior `deviceScope` from `grant.allowedDeviceKeyBindings`, route
  `applyCapabilities`/`sendUpdateNow` through the composer (needs a `fetchParticipantProfile` call
  to resolve devices).

## Related Code Files
Modify:
- `Vaultify/Features/Sharing/ShareRecipientDetailSheet.swift` — passkey rows, seed, compose.
- `Vaultify/Features/Sharing/ShareAccessSheet.swift` — route `confirmFingerprintAndPublish`
  through the composer (DRY; behavior-preserving).
Create:
- `Vaultify/Services/Sharing/SharedGrantComposer.swift` — shared grant assembly (<200 loc).

## Implementation Steps
1. Extract composer from `confirmFingerprintAndPublish`; switch CREATE to use it; verify unchanged
   behavior (compile + reasoning).
2. Add `itemPasskeys` + `PasskeyCapabilityRow`s to the edit sheet's `capabilitySection`.
3. Extend `loadGrant` to seed passkey slot caps and record prior device scope.
4. Rewrite `applyCapabilities` to fetch the participant profile and call the composer with
   passkeys + preserved device scope (epoch bump).
5. Update `sendUpdateNow` to include hand-over passkey secrets.
6. `tuist generate` (new file) → `make check`.

## Todo List
- [ ] `SharedGrantComposer` extracted; CREATE routed through it
- [ ] Edit-sheet passkey rows
- [ ] `loadGrant` seeds passkey caps + device scope
- [ ] `applyCapabilities` preserves passkeys + device scope
- [ ] `sendUpdateNow` includes passkey secrets
- [ ] Localize any new strings EN + VI
- [ ] `tuist generate` + `make check`

## Success Criteria
- Editing an existing share shows the passkey with its current grant state; toggling ON + Apply
  publishes a grant that carries the passkey (recipient AutoFill offers it).
- Applying capability edits never removes an already-granted passkey or downgrades single-device.
- CREATE behavior unchanged after the composer extraction.

## Risk Assessment
- **Device-scope re-derivation** is the delicate part — mitigate by reusing CREATE's exact
  profile→allowedDevices logic inside the composer; add a unit test for the mapping.
- **Grant epoch bump** already handled by the edit sheet; keep it.

## Security Considerations
- Hand-over passkey secret sealing stays identical to CREATE (INV-07/08). No new plaintext paths.
- Single-device invariant (INV-04) preserved via fail-loud, never widen.

## Next Steps
- Phase 2 (optional): recipient in-app display consuming the now-correct grant.
