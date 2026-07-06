# Phase 3 — Change real email + rotate-all

## Context
- Overview: [reldest-plan.md](reldest-plan.md) · Depends: [Phase 1](reldest-phase-01-destination-plumbing.md)
- Locked decision 3: destination is per-persona; changing persona A's email re-rotates ONLY A's ACTIVE aliases.
- Backend: change real email = call `rotateDestination` again for EACH active alias with the new email.

## Overview
- Priority: P2. Status: pending.
- Editing a persona's real email re-rotates its active aliases to the new destination. Trigger =
  explicit "Forwards to" control (recommended, KISS) rather than hooking item-edit.

## Key insights (verified)
- Phase 1 gives `send(.rotateDestination, aliasID:localPart, path:.../destination, destination:)`.
- `aliases(forPersona:)` + filter `.active` gives the set to rotate — `VaultRepository+Aliases.swift:42`.
- Real email lives in the profile card's first non-"Private email" `.email` field (Phase 1 `destinationEmail`).
- `update(_:)` re-seals the identity item — `VaultRepository.swift:365`.
- **Gap accepted:** editing the identity email via the normal Item editor does NOT auto-rotate. Only the
  "Forwards to" control triggers rotation. Documented limitation (see Risks); item-edit hook is a future option.

## Requirements
- `RelayService.updateDestination(for persona:, to newEmail:)`:
  1. Persist the new email into the profile card's real Email field (via repository).
  2. For each ACTIVE alias of the persona, `rotateDestination(localPart, newEmail)` sequentially.
  3. On each success, store `forwardingTarget = newEmail`.
  4. On a failure, stop and throw with progress info; already-rotated aliases keep the new target (correct);
     the rest keep the old target. Re-invoking retries the remainder (rotateDestination is idempotent).
- Validate `newEmail` non-empty + basic email shape before any network call; reject empty (would strand aliases).

## Architecture / data flow
```
"Forwards to" edit (Phase 4 UI) → RelayService.updateDestination(persona, newEmail)
  validate(newEmail)
  repository.setProfileEmail(persona, newEmail)     // update real Email field (local, sealed)
  for alias in repository.aliases(forPersona:).filter(.active):
      send(.rotateDestination, aliasID: alias.localPart, path: .../destination, destination: newEmail)  // 204
      repository.setForwardingTarget(alias, newEmail)   // after success only
  // partial failure → throw .rejected(...) with "n of m"; leave rotated ones as-is
```

## Related code files
Modify:
- `Vaultify/Services/Relay/RelayService.swift` — add `updateDestination(for:to:)` (may exceed 200 LOC → extract relay-destination helpers into `RelayService+Destination.swift`).
Create (if extraction needed):
- `Vaultify/Services/Relay/RelayService+Destination.swift` — `updateDestination`, email validation.
- `Vaultify/Data/Repositories/VaultRepository+AliasWriteback.swift` (from P2) — add `setProfileEmail(persona:_:)` + `setForwardingTarget(alias:_:)`.
Read for context: `VaultRepository+Aliases.swift`, `VaultRepository+PersonaContext.swift` (`destinationEmail`, `profileItem`).

## Implementation steps
1. `setProfileEmail(_ persona:, _ email:)` in repository: find/append the real `.email` field (label "Email", NOT "Private email") on `profileItem(for:)`, set value, `update`.
2. `setForwardingTarget(_ alias:, _ email:)`: set `forwardingTarget`, re-seal via `updateAlias`.
3. `updateDestination(for:to:)`: validate → setProfileEmail → loop active aliases (rotate + setForwardingTarget) → throw on first failure with count.
4. Keep each file <200 LOC (extract if needed). `tuist generate` (if new file) → `make check`.

## Todo
- [ ] `setProfileEmail` + `setForwardingTarget` repository helpers
- [ ] `updateDestination(for:to:)` with sequential rotate + partial-failure reporting
- [ ] email validation
- [ ] `make check`

## Success criteria
- Changing persona A's email re-rotates all of A's ACTIVE aliases to the new destination; persona B untouched.
- Reserved/disabled aliases are NOT rotated (no backend call).
- A mid-loop failure leaves already-rotated aliases forwarding to the new email; a retry rotates the rest (idempotent).
- Empty/invalid email is rejected before any network call.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Partial rotate leaves aliases split across old/new email | Med×Med | Sequential + idempotent retry; report "n of m"; each rotated alias is individually correct |
| Item-editor email change silently not rotated | Med×Med | Documented; "Forwards to" is the supported path; future: hook `update(_:)` on identity items |
| Empty email stranding all aliases | Low×High | Validate non-empty/shape before loop; reject |
| Rotating another persona's aliases | Low×High | Loop strictly over `aliases(forPersona: persona.id)` |

## Security
- New destination rides kind=3 transcript only; never logged. No cross-persona rotation.

## Next
- P4 exposes the "Forwards to" edit control that calls `updateDestination`.
