# Phase 4 — Alias detail screen

## Context
- Overview: [reldest-plan.md](reldest-plan.md) · Depends: [P1](reldest-phase-01-destination-plumbing.md), [P2](reldest-phase-02-write-back.md), [P3](reldest-phase-03-change-email-rotate-all.md)

## Overview
- Priority: P2. Status: pending.
- A detail screen for a single alias: address, status, tier, binding, "Forwards to" (editable → rotate),
  and Disable/Revoke + irreversible Delete.

## Key insights (verified)
- Row → detail navigation replaces the current tap-to-copy/activate-in-place on active rows (`PersonaAliasesScreen.swift:89-116`).
- Full address via `AliasAddress.display(...)`; copy via `env.clipboard.copy(..., sensitive:false)` (pattern at `PersonaAliasesScreen.swift:93`).
- Relay calls via `env.relay` (`activate`/`disable`/`delete` + P3 `updateDestination`); busy+error pattern at `PersonaAliasesScreen.swift:153-164`.
- Copy "Forwards to", "Disable", "Revoke", "Delete" already in `Localizable.xcstrings`. Need to add the destructive-confirm body copy (EN+VI).
- Design system: `PolarisIcon(Icons.*)`, `.vaultType`, `.themedForeground`, `Space.*`, `Radius.*`. MainActor.

## Requirements
- `AliasDetailScreen(alias:)`:
  - Address row (copy on tap; only meaningful when `.active`).
  - Status + tier + bound domain/login (per-site) rows.
  - "Forwards to <real email>" row → tap to edit → on commit calls `env.relay.updateDestination(for: persona, to:)` (rotates all active aliases of the persona, per P3). Show busy + error.
  - Actions: Disable (→ `.disabled`) / Revoke label for active; Delete with an **irreversible destructive confirmation** ("This can't be undone; the address stops working").
  - Keep the receive-only reply warning (reuse the banner copy).
- Destination edit here is per-PERSONA (P3 semantics) — the row label must make clear it affects the persona's real email (e.g. footer: "Used for all of this persona's aliases").

## Architecture / data flow
```
PersonaAliasesScreen row tap → NavigationLink → AliasDetailScreen(alias)
  persona = repository.persona(id: alias.personaId)
  "Forwards to" commit → relay.updateDestination(persona, newEmail)   // P3
  Disable → relay.disable(alias) ; Delete → confirm → relay.delete(alias) → pop
```
- Confirmation: SwiftUI `.confirmationDialog`/`.alert` with destructive role (no custom Polaris modal in this native app — match existing alert usage).

## Related code files
Create:
- `Vaultify/Features/Personas/AliasDetailScreen.swift` (<200 LOC; extract an `AliasActionRow`/`ForwardsToRow` subview if needed).
Modify:
- `Vaultify/Localizable.xcstrings` — add destructive-confirm title/body + "Used for all of this persona's aliases" (EN+VI).
Read for context: `PersonaAliasesScreen.swift` (row + run/error patterns), `AliasAddress.swift`, `RelayConfig.swift`, `VaultRepository+Aliases.swift`.

## Implementation steps
1. Build `AliasDetailScreen` scaffold (List/Form sections: Address, Details, Forwards to, Actions).
2. Address row: `Text(verbatim: AliasAddress.display(...))` + copy button (active only).
3. "Forwards to" editable row: local `@State` string seeded from `destinationEmail(for: persona)`; commit → `updateDestination`; busy/error via the P5-shared run helper.
4. Disable/Delete actions; Delete gated by a destructive confirmation dialog → `relay.delete` → `dismiss`.
5. Reuse receive-only warning banner.
6. Add confirm/footer strings EN+VI. `tuist generate` (new file) → `make check`.

## Todo
- [ ] `AliasDetailScreen.swift`
- [ ] address copy + status/tier/binding rows
- [ ] editable "Forwards to" → `updateDestination`
- [ ] Disable + irreversible Delete confirmation
- [ ] EN+VI strings; `make check`

## Success criteria
- Tapping any alias row opens the detail screen.
- Editing "Forwards to" rotates the persona's active aliases (device-verified) and updates the shown email.
- Delete requires explicit confirmation and only removes after backend success; screen pops.
- Screen passes light/dark + Reduce Motion + 44pt targets; all copy localized VI.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| User expects "Forwards to" to change ONLY this alias | Med×Med | Footer copy states it affects all of this persona's aliases (matches locked decision 3) |
| Delete confirm bypassed by fast taps | Low×Med | Destructive role + explicit confirm step; disable button while busy |
| Editing email to invalid value | Low×Med | P3 validates before network |

## Security
- No secret rendered; address is non-sensitive. Persona resolved by `alias.personaId` (INV-R03).

## Next
- P5 wires rows to this screen + guards creation.
