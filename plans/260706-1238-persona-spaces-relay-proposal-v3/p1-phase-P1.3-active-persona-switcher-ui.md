# P1.3 — Active-persona selection + switcher UI

Context: [p1-plan.md](p1-plan.md) · D7 (local selection) · Depends on **P1.2**. Rebinds the P0 `PersonaID.placeholder` seam.

## Overview
- Priority: P1 · Status: pending · Depends on: P1.2
- Give the user a **minimal** way to see personas and switch the active one, and rebind the two persona-keyed call sites from `PersonaID.placeholder` to `activePersona.id`. Switching the active persona changes which `primarySpaceID` drives Home's primary Space and which bucket keys `lastSelectedSpaceByPersona`. Keep it a thin first cut (KISS): **list + switch + minimal create**; edit/delete/avatar deferred.

## Key insights
- Only **3** call sites use `PersonaID.placeholder` today (verified):
  - `HomeScreen.swift:81` — restore last selected Space on `.task`.
  - `HomeScreen.swift:122` — persist on `selectedFolderId` change.
  - `SearchScreen.swift:44` — derive default scope from the last selected Space.
  Replace each with `env.repository.activePersona?.id ?? PersonaID.placeholder` (the `?? placeholder` keeps a stable bucket before the seed lands / if resolver is momentarily nil — no crash, no key churn).
- Home already has a **Space switcher** control in the "All" section header (`HomeScreen.swift:422`) — the natural, low-risk anchor to also reach the persona switcher without new chrome. But to avoid Home-layout surgery risk, the **primary** entry point is a Settings row; a Home affordance is optional (decision D-P1-c).
- The switcher must **re-drive** Home: after `setActivePersona`, `activePersona.primarySpaceID` changes, so Home should re-apply its selected-Space restore. Simplest: on persona change, reset `selectedFolderId` via the same restore path (validated against live folders).
- Localization is mandatory EN+VI; `LocalizedStringResource` titles use `.inAppLocalized`, runtime strings `appString()`.

## Requirements
- **Functional:**
  1. `PersonaSwitcherSheet` lists `repository.personas` (kind icon + `displayName`), checkmarks `activePersona`, tap → `setActivePersona(id)` + dismiss.
  2. Minimal **create**: "Add" → name field + `PersonaKind` picker → `addPersona(displayName:kind:)`; new persona selectable immediately. (Default `isolationPolicy=.standard`; no policy picker — P2.)
  3. A **Settings** row ("Personas" / "Danh tính") opens the sheet.
  4. Rebind the 3 `PersonaID.placeholder` call sites to `activePersona?.id ?? PersonaID.placeholder`.
  5. On active-persona change, Home re-restores its Space filter for the new persona (respects the persisted `lastSelectedSpaceByPersona[newID]`, else primary Space).
- **Non-functional:** design tokens only; Polaris SVG icons for kind glyphs (no SF Symbols); sheet uses the app's standard sheet/elevation tokens; all new strings EN+VI in `Localizable.xcstrings`.

## Architecture
Data flow: tap persona → `repository.setActivePersona(id)` → writes `settings.activePersonaID` → `repository.activePersona` recomputes → `primarySpaceId` + Home restore + persistence key all follow the new active id. No sync, no record write (selection is local, D7).

`Vaultify/Features/Personas/PersonaSwitcherSheet.swift` (new): a `View` reading `@Environment` `AppEnvironment`; `List`/`ForEach(repository.personas)`; row = kind icon + name + trailing check on active; footer "Add persona" → inline create (name + `Picker(PersonaKind.allCases)`). Kind→icon map (Polaris assets) kept in the view or a small `PersonaKind+Icon` helper.

`SettingsScreen.swift`: add one `PolarisListItem`/row that presents the sheet.

Home rebind (`HomeScreen.swift`): replace `PersonaID.placeholder` at :81 and :122 with `env.repository.activePersona?.id ?? PersonaID.placeholder`; add `.onChange(of: env.repository.activePersona?.id)` → re-run the restore-selected-Space path (once, validated). Search rebind (`SearchScreen.swift:44`): same replacement.

## Related code files
- Create: `Vaultify/Features/Personas/PersonaSwitcherSheet.swift` (~120 LOC), optional `Vaultify/Features/Personas/PersonaKindIcon.swift` (kind→Polaris asset)
- Modify: `Vaultify/Features/Home/HomeScreen.swift` (:81, :122, + `onChange` re-restore)
- Modify: `Vaultify/Features/Search/SearchScreen.swift` (:44)
- Modify: `Vaultify/Features/Settings/SettingsScreen.swift` (one row → sheet)
- Modify: `Vaultify/Resources/Localizable.xcstrings` (EN+VI: "Personas", "Danh tính", "Add persona", persona kind labels, sheet title)

## Implementation steps
1. `PersonaKindIcon` (or inline): map each `PersonaKind` → a Polaris SVG asset + a localized label.
2. `PersonaSwitcherSheet`: list personas, checkmark active, tap → `setActivePersona` + dismiss; inline "Add" (name + kind) → `addPersona`.
3. `SettingsScreen`: add "Personas" row presenting the sheet.
4. Rebind `HomeScreen.swift:81` + `:122` and `SearchScreen.swift:44` to `activePersona?.id ?? PersonaID.placeholder`.
5. `HomeScreen`: `.onChange(of: env.repository.activePersona?.id)` → re-restore selected Space for the new persona (guarded, validated against live folders).
6. Add all new strings to `Localizable.xcstrings` with EN **and** VI values.
7. `make check`; verify light/dark + Reduce Motion + 44pt hit targets; VI present for every new string.

## Todo
- [ ] `PersonaKindIcon` map (Polaris assets, localized labels)
- [ ] `PersonaSwitcherSheet` (list + switch + minimal create)
- [ ] Settings entry row
- [ ] Rebind 3 `PersonaID.placeholder` call sites → `activePersona?.id`
- [ ] Home re-restore on active-persona change
- [ ] EN+VI strings in `Localizable.xcstrings`
- [ ] `make check` + light/dark/a11y pass

## Success criteria
- Switcher lists the seeded Personal persona; creating a 2nd persona makes it appear + selectable.
- Switching active persona: Home's primary/selected Space follows that persona's `primarySpaceID` + its remembered `lastSelectedSpaceByPersona` bucket; kill+relaunch preserves the active persona (from `settings.activePersonaID`).
- `grep 'PersonaID.placeholder'` shows it only as the **fallback** operand (no bare call-site usage).
- Every new string has an EN + VI value; no SF Symbols; renders in light + dark.
- Works with `iCloudSyncEnabled` OFF (selection + personas fully local).

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Switcher over-build (edit/delete/avatar/policy) balloons P1 | Med×Med | Scope = list + switch + minimal create only. Edit/delete/avatar/isolation-policy explicitly deferred to P2 (documented). |
| Create-without-delete = awkward UX (can't remove a persona) | Med×Low | Accepted P1 limitation (internal beta). Delete needs the ≥1 + can't-delete-default guard (mirror `isLastActiveIdentity`) → P2. Flag D-P1-b. |
| Active-persona change doesn't refresh Home Space | Med×Med | Explicit `.onChange(of: activePersona?.id)` re-restore path; validated against live folders. |
| Missing VI translation ships | Low×Med | Checklist item + grep xcstrings for new keys before `make check` sign-off. |
| Home-header entry point risks switch latency (native TabView caveat) | Low×Med | Primary entry = Settings row (no Home chrome). Home affordance optional (D-P1-c) and only if it reuses the existing :422 switcher control. |

## Security
No secrets in the UI beyond already-decrypted `displayName`. Selection is device-local. Sheet inherits the app's privacy-screen behavior; no new key handling.

## Next steps
Unblocks **P2** (Persona Context + AutoFill): isolation-policy editor + consumption (`allSpacesSearchAllowed` driven by policy, INV-R03 hard candidate exclusion), ranking engine, Create-Login context, persona edit/delete + avatar.
