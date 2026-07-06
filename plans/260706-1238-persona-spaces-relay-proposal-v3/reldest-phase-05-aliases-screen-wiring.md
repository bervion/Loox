# Phase 5 — Aliases screen wiring + guards

## Context
- Overview: [reldest-plan.md](reldest-plan.md) · Depends: [P1](reldest-phase-01-destination-plumbing.md), [P4](reldest-phase-04-alias-detail-screen.md)

## Overview
- Priority: P2. Status: pending.
- Guard alias creation when the persona has no destination email; navigate rows to the detail screen;
  keep the receive-only warning.

## Key insights (verified)
- Create entry points: "Reserve a private alias" (`PersonaAliasesScreen.swift:59-66`) and `AliasEditorSheet.save()` (`AliasEditorSheet.swift:57-64`). Both reserve then `activate($0)`. Activate now throws `.missingDestination` (P1) if no email.
- `AliasEditorSheet` already shows "Forwards to <identityUsername>" (`AliasEditorSheet.swift:38-45`) — update to `destinationEmail(for:)` and surface the missing-email guidance.
- Row currently switches on status for copy/activate (`PersonaAliasesScreen.swift:89-116`) — replace active/reserved rows with a `NavigationLink` to `AliasDetailScreen`; keep tap-to-activate affordance for reserved OR move activation into detail.
- `run(_:_:)` maps `RelayService.Failure` to a generic connection message (`PersonaAliasesScreen.swift:158-162`) — extend to surface `.missingDestination` with the "add an email first" copy.

## Requirements
- Before reserving/activating, check `destinationEmail(for: persona) != nil`. If nil, block and show
  "Add an email to this identity first" (do not mint). Applies to both persona-tier and per-site create.
- Alias rows navigate to `AliasDetailScreen`.
- `.missingDestination` maps to the guidance message (distinct from the connection error).
- Keep the receive-only reply warning banner.

## Architecture / data flow
```
create tapped → if repository.destinationEmail(for: persona) == nil → show "add email first", stop
             → else reserve → activate (P1)
row tapped   → NavigationLink → AliasDetailScreen(alias)   // P4
activate error .missingDestination → "Add an email to this identity first"
```

## Related code files
Modify:
- `Vaultify/Features/Personas/PersonaAliasesScreen.swift` — pre-create email guard; rows → `NavigationLink(AliasDetailScreen)`; extend `run`/error mapping for `.missingDestination`.
- `Vaultify/Features/Personas/AliasEditorSheet.swift` — "Forwards to" uses `destinationEmail(for:)`; disable Save + show guidance when nil.
- `Vaultify/Localizable.xcstrings` — "Add an email to this identity first" (EN+VI).
Read for context: `AliasDetailScreen.swift` (P4), `VaultRepository+PersonaContext.swift` (`destinationEmail`).

## Implementation steps
1. Add computed `hasDestinationEmail` guard in `PersonaAliasesScreen`; gate both create buttons; show guidance when missing.
2. Convert `aliasRow` to a `NavigationLink` → `AliasDetailScreen(alias:)`; keep status label; drop in-row copy/activate (moved to detail).
3. Extend `run` to catch `.missingDestination` → guidance string.
4. `AliasEditorSheet`: replace `identityUsername` with `destinationEmail(for:)`; if nil, disable Save + inline "add an email first".
5. Add EN+VI string. `make check`.

## Todo
- [ ] pre-create destination-email guard (both tiers)
- [ ] rows → `AliasDetailScreen`
- [ ] `.missingDestination` error copy
- [ ] `AliasEditorSheet` forwards-to = real email + guard
- [ ] EN+VI string; `make check`

## Success criteria
- Persona with no profile email: create is blocked with clear guidance; no reserved alias minted.
- After adding an email, create + activate succeed.
- Tapping a row opens `AliasDetailScreen`.
- Receive-only warning still shown; all copy localized VI.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Reserved-but-not-activated aliases linger if activate blocked mid-flow | Med×Low | Guard BEFORE reserve (check email first), so nothing is minted on the blocked path |
| Row nav change regresses copy affordance | Low×Low | Copy moves to detail; keep it discoverable there |

## Security
- Guard reads own-persona profile only (`destinationEmail` via `profileItem(for:)`). No cross-persona surface.

## Next
- Device QA: full create→activate→forwards-to→delete loop on sim/device (live relay + iCloud escrow).
