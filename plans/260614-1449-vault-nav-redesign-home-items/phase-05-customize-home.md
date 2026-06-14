# Phase 05 — Customize Home (section toggles + order)

## Context Links
- Prefs store: `Vaultify/App/SettingsStore.swift` (UserDefaults-backed `@Observable`; `Key` enum)
- Home section model: `Vaultify/Features/Home/HomeSection.swift` (Phase 4)
- Home consumer: `Vaultify/Features/Home/HomeScreen.swift` (Phase 4)

## Overview
- **Priority:** P2
- **Status:** pending
- **Depends:** Phase 4 (HomeScreen + HomeSection exist).
- A **Customize Home** screen letting the user toggle the optional sections (Recently Used, Recently
  Modified) and — ideally — reorder sections. Persist in `SettingsStore`. HomeScreen reads this config
  to drive section visibility + order.

## Key Insights
- `SettingsStore` is the established prefs home: `@Observable` + `didSet` → `UserDefaults`, with a
  private `Key` enum (`SettingsStore.swift:82-94`). Follow that exact pattern for the new keys. No new
  store, no new persistence layer (KISS/DRY).
- Persisting an **ordered list of enabled sections** is the cleanest single source of truth for both
  visibility and order. Store as a `[String]` of `HomeSection` raw values in UserDefaults (encode via
  the existing `defaults.set(_, forKey:)` pattern; decode in `init` with a default fallback). This makes
  `HomeSection` need a `String` raw value / stable id.
- **Scope guard (YAGNI):** the locked decision says "toggle (and ideally reorder)". Toggling is required;
  reorder is "ideally". **Recommend: ship toggles now; reorder via `.onMove` in an `EditMode` List is
  cheap if the persisted model is already an ordered array** — so design the persisted model as an
  ordered array from the start (enables reorder with ~no extra model work), and include `.onMove`.
- Default-ON sections (Pinned/Favorite/Recently Created/Frequently Used) — locked as default ON. Decide
  whether they're user-hideable. **Recommend: all six sections are reorderable + toggleable, with the
  four defaults ON and the two optional OFF by default.** (Confirm — see Open Q.)

## Requirements
**Functional:**
- Customize Home screen lists all sections with a toggle each; supports drag-reorder (`.onMove`).
- Changes persist immediately to `SettingsStore` and reflect on HomeScreen live (`@Observable`).
- Defaults: Pinned/Favorite/Recently Created/Frequently Used = ON; Recently Used/Modified = OFF.
- Utilities section is always shown (not user-toggleable) — or include it as toggleable (Open Q).

**Non-functional:** localized labels EN+VI; Polaris icons; no new persistence mechanism.

## Architecture
**Data flow:** Customize Home screen ↔ `SettingsStore.homeSectionOrder: [String]` (enabled+ordered) and
`SettingsStore.homeSectionsEnabled` (or fold enabled-state into the ordered array: an item present =
enabled). **Recommend a single `homeSections: [HomeSectionConfig]`** where each entry = (id, isOn), JSON-
encoded in UserDefaults — captures both order and visibility in one key.
- `HomeScreen` reads `settings.homeSections`, maps ids → `HomeSection`, filters `isOn` + non-empty,
  renders in stored order. Falls back to the default config when the key is absent (fresh install).

## Related Code Files
**Create:**
- `Vaultify/Features/Home/CustomizeHomeScreen.swift` (≤140 LOC) — EditMode List of toggles + `.onMove`.

**Modify:**
- `Vaultify/App/SettingsStore.swift` — add `homeSections` persisted property (JSON `[HomeSectionConfig]`
  via Codable, encoded into UserDefaults; `didSet` writes, `init` reads with default). Add `Key` entry.
  Keep the file's existing pattern; if Codable JSON pushes the file over ~200 LOC, split the Home-config
  read/write into a `SettingsStore+HomeSections.swift` extension.
- `Vaultify/Features/Home/HomeSection.swift` — add stable `String` id/rawValue + a `defaultConfig`.
- `Vaultify/Features/Home/HomeScreen.swift` — drive section list from `settings.homeSections` (replace
  the Phase-4 hardcoded order); add the Customize entry (header button or a row) → `CustomizeHomeScreen`.

## Implementation Steps
1. Give `HomeSection` a stable `String` id + `defaultConfig: [HomeSectionConfig]`.
2. Add `HomeSectionConfig: Codable, Identifiable` (id + isOn).
3. `SettingsStore`: add `homeSections` (Codable JSON in UserDefaults; default fallback) + `Key`.
4. Create `CustomizeHomeScreen` (List, per-section Toggle, `.onMove`, EditMode; binds to
   `settings.homeSections`).
5. `HomeScreen`: render from `settings.homeSections` (ordered + isOn + non-empty); add Customize entry.
6. `tuist generate` + `make check` green.

## Todo List
- [ ] HomeSection stable id + defaultConfig
- [ ] HomeSectionConfig Codable model
- [ ] SettingsStore.homeSections persisted (+ Key)
- [ ] CustomizeHomeScreen (toggles + reorder)
- [ ] HomeScreen reads config (order + visibility)
- [ ] `make check` green

## Success Criteria
- Toggling a section in Customize Home shows/hides it on Home immediately and survives relaunch.
- Reordering persists and reflects on Home.
- Fresh install shows the four default-ON sections in default order.
- `make check` green.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| Persisted config drifts from `HomeSection` cases (added/removed section) | Med×Med | On decode, reconcile: keep known ids in stored order, append any new `HomeSection` not in config (as default isOn), drop unknown ids. One reconcile function. |
| File >200 LOC after Codable in SettingsStore | Low×Low | Split to `SettingsStore+HomeSections.swift` extension. |
| Reorder scope creep | Low×Low | Ordered-array model makes `.onMove` near-free; if time-boxed, ship toggles only and leave order = default (still persisted-ready). |

## Security Considerations
None — UI preference flags only, no secrets.

## Next Steps
None downstream depends on this. Phase 8 localizes its strings.
