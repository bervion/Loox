# P2.4 — Persona management completeness + QuickType threat-model

## Context links
- Canonical: `proposal-v3-locked-decisions.md` — INV-R03. Overview: `p2-plan.md`. Deferred from P1.3 (see
  `p1-plan.md` "Out of scope": isolationPolicy editor, persona edit/delete UI + delete guard).
- Guard pattern to mirror: `VaultRepository+Identity.swift:32-43` (`isLastActiveIdentity`, `identityRemovalGate`).
- Convergence to preserve: `normalizeDefaultPersona` (`VaultRepository.swift:219`), exactly-1-default invariant.

## Overview
- **Priority:** P2 · **Status:** pending · **Depends on:** P2.2 (policy is now consumed, so it must be settable).
- Make `PersonaIsolationPolicy` user-settable (create + edit), add persona rename/kind/policy edit + delete with a
  guard, and record the QuickType privacy decision. Keep minimal.

## Key insights
- `PersonaSwitcherScreen.swift` (88 LOC) currently has list/switch + create (name + kind only). No policy picker,
  no edit, no delete. `addPersona(displayName:kind:)` (`VaultRepository+Personas.swift:61`) omits policy.
- Delete guard = mirror identity gate: block deleting the **last** persona AND the **default** persona (user must
  set another default first). Reassign/no-op on members: personas don't own items yet (folders unpartitioned), so a
  deleted persona needs no item reassignment — only demote/guard + tombstone the record (bump `updatedAt`, LWW-safe).
- **QuickType threat-model (D-F, documented acceptance):** `CredentialIdentityService` (`:74-83`) publishes
  `username + host` for EVERY owned login into the system index, with NO notion of active persona (the OS matches by
  host at fill time). A strictAnonymous persona's login, once saved, IS an owned item and WILL be suggested on its
  host. This is **host-scoped** (only on the matching site), not in-app cross-persona correlation, so it does not
  violate INV-R03's "surface … from another Persona" within the app surfaces. Per-item persona suppression would need
  P1's unbuilt per-item persona tag → **deferred (YAGNI)**. Record the accepted decision; no code mitigation in P2.

## Requirements
- Create/edit sheet includes an isolation-policy picker (standard/isolated/strictAnonymous) with a one-line
  explanation each, EN+VI.
- `updatePersona` (rename + kind + policy, re-seal, bump `updatedAt`) and `deletePersona` (tombstone) with a
  `PersonaRemovalGate` (`.ok` / `.lastPersona` / `.defaultPersona`).
- `addPersona` accepts an `isolationPolicy` argument (default `.standard`).
- QuickType decision documented in `docs/codebase-summary.md` + a self-contained code comment (no plan refs).

## Architecture / data flow
```
PersonaSwitcherScreen (create/edit sheet: name, kind, policy) 
  → VaultRepository+PersonaManagement.updatePersona/deletePersona/addPersona(policy:)
  → re-seal PersonaSecret (updatedAt bump) → reload() → normalizeDefaultPersona() convergence
```
```swift
// VaultRepository+PersonaManagement.swift
enum PersonaRemovalGate: Equatable { case ok, lastPersona, defaultPersona }
func personaRemovalGate(_ p: Persona) -> PersonaRemovalGate
func updatePersona(_ p: Persona) throws      // re-seal via sealPersona, record.updatedAt = .now, dirty
func deletePersona(_ p: Persona) throws      // guard first; tombstone deletedAt + updatedAt bump
// addPersona gains: displayName:kind:isolationPolicy: (default .standard) — extend existing signature.
```

## Related code files
- **Create:** `Vaultify/Data/Repositories/VaultRepository+PersonaManagement.swift` (<150 LOC)
- **Modify:** `Vaultify/Features/Personas/PersonaSwitcherScreen.swift` — policy picker in create; edit + delete (swipe/menu) with modal on gate hit.
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+Personas.swift` — **only if** extending `addPersona`
  in place would collide with P2.3 (which also edits this file for the mirror call). To keep ownership clean, add an
  `addPersona(..., isolationPolicy:)` overload in the NEW `+PersonaManagement.swift` instead; leave `+Personas.swift` to P2.3.
- **Modify:** `Vaultify/Resources/Localizable.xcstrings` — policy labels + descriptions, edit/delete, guard messages EN+VI. (Serialize after P2.2/P2.3.)
- **Modify:** `docs/codebase-summary.md` — QuickType per-persona threat-model note.
- **Create:** `VaultifyTests/PersonaManagementTests.swift`
- **Read for pattern:** `VaultRepository+Personas.swift:61-95` (addPersona/setDefaultPersona seal+bump), `+Identity.swift:32-43`.

## Implementation steps
1. `+PersonaManagement.swift`: `personaRemovalGate`, `updatePersona`, `deletePersona`, `addPersona(...,isolationPolicy:)` overload. All writes re-seal + bump `updatedAt` + `reload()` + `noteLocalMutation()`.
2. `PersonaSwitcherScreen`: add policy `Picker` to the create sheet; add an edit sheet (name/kind/policy) reachable per row; add delete with `PolarisModal.destructive`, blocked by a `.info` modal when the gate returns `.lastPersona`/`.defaultPersona`.
3. Localize all new strings EN+VI (policy names + one-line meanings; guard copy).
4. Add the QuickType decision note to `docs/codebase-summary.md` + a stable code comment in `CredentialIdentityService` (why: host-scoped, per-persona suppression deferred).
5. `tuist generate --no-open`; `make check`.
6. Tests + `-only-testing:VaultifyTests/PersonaManagementTests`.

## Todo
- [ ] `+PersonaManagement.swift` (gate + update + delete + addPersona overload)
- [ ] policy picker (create + edit) + delete UI w/ guard modals
- [ ] EN+VI strings (serialized catalog edit)
- [ ] QuickType threat-model note (docs + code comment)
- [ ] `PersonaManagementTests` green

## Success criteria
- Setting a persona to strictAnonymous in-app makes P2.2/P2.3 isolation observably active (manual: search chips lose
  All Spaces; extension prefill empties).
- `deletePersona` blocked (gate) for the last persona and the current default; allowed otherwise; tombstone bumps
  `updatedAt` (survives LWW pull).
- `updatePersona` re-seals and bumps `updatedAt`; exactly-1-default invariant preserved after reload.
- QuickType decision is written down (docs + code comment), self-contained (no phase/finding refs).

## Risk assessment
- **Med L × Med I:** deleting a persona that other device still references (default flip race). Mitigation: gate blocks
  default deletion; `normalizeDefaultPersona` reconverges post-pull; tombstone bumps `updatedAt`.
- **Med:** users expect strictAnonymous to hide items from QuickType too. Mitigation: explicit doc + (future) P3 tagging;
  in-app copy for the policy avoids over-promising ("limits suggestions & search", not "hides everywhere").
- **Low:** catalog merge conflict with P2.2/P2.3. Mitigation: serialize catalog edits (run last).

## Security
- Persona edits re-seal under the Vault Key (identity-bearing name/policy stay sealed). Delete is a tombstone, not a
  hard delete (sync-safe). No secret enters plaintext columns.

## Next steps
Closes P2. Manual device QA matrix: create strictAnonymous persona → verify search + AutoFill exclusion (P2.2/P2.3) →
delete guard behavior. Feeds P3 (local alias model) which introduces per-persona alias binding and may revisit the
QuickType per-item tagging deferred here.
</content>
