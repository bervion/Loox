# P3 Phase 3 — Minimal UI: aliases screen, editor, Settings entry, localization

**Context:** `p3-plan.md` · Phase 2 (repo API). Canonical D14 warning copy.
**Pattern sources (verified):** `Vaultify/Features/Personas/PersonaSwitcherScreen.swift`
(List/sheet/swipe/editor pattern), `Vaultify/Features/Settings/SettingsScreen.swift:103`
(`NavigationLink { PersonaSwitcherScreen() }`), Design-System token API (CLAUDE.md).

## Overview
Priority P2 · Status pending · Depends P2.
One Settings entry → a screen listing the **active persona's** aliases (persona-tier +
per-site), create draft/reserved aliases, bind a per-site alias to a login. Everything labeled
"not active yet"; D14 warning always visible. No `.active` state anywhere (flag off).

## Key insights
- Reuse the active-persona context model (`activePersona` always resolves) — the screen acts on
  `env.repository.activePersona`, matching how the app already scopes by persona. Switch persona
  via the existing switcher. Avoids a persona picker (KISS).
- **Address rendering** goes through `AliasAddress.display(..., flag: RelayFeature
  .activeAliasesEnabled)` — with the flag off it shows the bare `localPart` + a "Reserved" badge,
  never `localPart@…`. The UI must NEVER string-concatenate a domain itself.
- Localization is MANDATORY EN+VI (`Vaultify/Localizable.xcstrings`); titles via
  `.inAppLocalized`, runtime via `appString()`; every new `Text` literal gets a VI value.

## Requirements
Functional:
- Settings → "Email aliases" (VI "Email ẩn danh") `NavigationLink` → `PersonaAliasesScreen`.
- `PersonaAliasesScreen`: header naming the active persona; a persistent D14 warning banner;
  a "Persona alias" section (create if none, else show the one reserved alias); a "Per-site
  aliases" section (list + add); swipe to disable/delete.
- `AliasEditorSheet`: tier is fixed by entry point; for per-site, pick a login item from the
  active persona's items (sets `boundItemId`); show generated `localPart` (regenerate button);
  show `forwardingTarget` label (read-only, from persona profile email); D14 warning; Save →
  repo create/update.
- Empty/flag-off copy: a "Coming soon — receive-only relay" note so users understand reserved
  aliases don't work yet.

Non-functional: Design-System tokens only (no hardcoded visual constants); Polaris SVG icons;
44pt hit targets; light/dark/Reduce-Motion/contrast verified; each Swift file <200 LOC.

## Architecture
`PersonaAliasesScreen` reads `env.repository.aliases(forPersona: activePersona.id)` +
`personaAlias(forPersona:)`. Mutations call `createPersonaAlias`/`createPerSiteAlias`/
`setAliasStatus`/`deleteAlias`. `@Observable` repo drives refresh (same as switcher). No local
state beyond editor presentation + the login picker selection.

D14 banner text (localized):
- EN: "Replies from your destination inbox may reveal your real email address."
- VI: "Thư trả lời từ hộp thư đích của bạn có thể để lộ địa chỉ email thật."

## Related code files
Create:
- `Vaultify/Features/Personas/PersonaAliasesScreen.swift` — list + sections + banner (~150 LOC).
- `Vaultify/Features/Personas/AliasEditorSheet.swift` — create/edit + login picker (~150 LOC).
Modify:
- `Vaultify/Features/Settings/SettingsScreen.swift` — add the `NavigationLink` near `:103`.
- `Vaultify/Localizable.xcstrings` — all new EN strings + VI translations.

## Implementation steps
1. `AliasEditorSheet.swift`: `NavigationStack`/`Form` mirroring `PersonaEditorSheet`
   (`PersonaSwitcherScreen.swift:95-161`). Sections: generated localPart (with regenerate),
   per-site login picker (`Picker` over active persona's login items), forwarding label
   (read-only), D14 footer. Save routes by tier to the repo.
2. `PersonaAliasesScreen.swift`: `List` with persona-alias section, per-site section, D14 banner,
   `.sheet(item:)` for the editor, swipe actions (Disable → `setAliasStatus(.disabled)`, Delete
   → `deleteAlias`). Address rows use `AliasAddress.display(...)` + a "Reserved"/"Disabled" badge.
3. `SettingsScreen.swift`: add `NavigationLink { PersonaAliasesScreen() } label: {...}` with a
   Polaris mail icon, adjacent to the Personas row.
4. Add every literal to `Localizable.xcstrings` with EN + VI (banner, section titles, buttons,
   "Coming soon" note, badges).
5. `tuist generate --no-open`; `make check`. Manual QA on sim `83B71AA8-…`.

## Todo
- [ ] AliasEditorSheet.swift (tier-routed create/edit + login picker + D14)
- [ ] PersonaAliasesScreen.swift (sections + banner + swipe)
- [ ] SettingsScreen NavigationLink
- [ ] Localizable.xcstrings EN+VI for all new strings
- [ ] tuist generate + make check
- [ ] Manual QA checklist

## Success criteria
- From Settings you can create a persona alias + a per-site alias bound to a login; both show as
  "Reserved", never as a `foo@bar` address.
- D14 warning visible on the aliases screen and the editor.
- No hardcoded colors/spacing (tokens only); Polaris icons; passes light+dark+Reduce Motion.
- Every new string has a VI translation (no missing-VI bug).
- Grep check: no view constructs an alias address by concatenating `@` (only `AliasAddress`).

## Risks
| Risk | L×I | Mitigation |
|------|-----|------------|
| UI renders a live-looking address | L×H | rows call `AliasAddress.display` only; grep-guard + review |
| Missing VI translation ships | M×M | step 4 checklist; xcstrings review |
| Login picker leaks cross-persona items (INV-R03) | L×H | picker source = active persona's items only |

## Security
- Screen only reads decrypted caches; no new persistence. Isolation preserved (single active
  persona scope). No address that implies a working relay.

## Next steps
Phase 4 (optional/deferred) — surface reserved aliases in the create-login editor. Not required:
binding already exists here via the alias editor's login picker.
