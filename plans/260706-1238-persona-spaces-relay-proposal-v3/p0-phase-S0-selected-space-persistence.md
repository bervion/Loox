# P0-S0 — Selected-Space persistence (persona-ready)

Context: [p0-plan.md](p0-plan.md) · D7 · audit §A gap 1 · execution note 3

## Overview
- Priority: P1 · Status: pending · Depends on: S1
- Persist the Home Space filter across launches. Today `selectedFolderId` is plain `@State` (`HomeScreen.swift:20`) → resets every cold launch. Build **persona-ready** per D7: store a map `lastSelectedSpaceByPersona`, keyed now by a **placeholder persona id** (single default bucket), so P1 rebinds to the real personaID without reshaping storage. Local preference only — **not synced**, never mixed into identity truth.

## Key insights
- Exact precedent already in the codebase: `SettingsStore.selectedPaymentCardId: String?` (`SettingsStore.swift:73`) — a device-local, non-synced, nullable display preference in `UserDefaults`. S0 mirrors this pattern but as a **map** (D7 shape).
- `UserDefaults` natively stores `[String:String]` — no JSON encoder needed.
- Selection domain today = `String?` where `nil` = "All Spaces". S0 persists exactly that (a folderId or the all-spaces sentinel). Shared-with-Me is NOT a Home filter today (S5 handles it as a search scope only) → keep S0 to folderId/all.
- Validate on load: a persisted id may point at a folder deleted on another device → fall back to All Spaces.

## Requirements
- Functional: last Home Space selection restored on cold launch; survives lock/unlock; cleared correctly when the folder no longer exists.
- Persona-ready: storage is `[personaID: spaceID]`; P0 writes/reads under `PersonaID.placeholder`. P1 changes only the **key argument**, not the store.
- Non-functional: no sync, no secret exposure (folderId is not secret — it's plaintext on `ItemRecord`/`FolderRecord` metadata already).

## Architecture
New tiny type to name the seam:
```swift
// PersonaID.swift (VaultifyCore or Vaultify/App)
enum PersonaID {
    /// P0 single-bucket key. P1 replaces call-site usage with the active
    /// persona's id; the storage map shape is unchanged, so no migration.
    static let placeholder = "__default__"
}
```
Add to `SettingsStore`:
```swift
private var lastSelectedSpaceByPersona: [String: String]   // persisted [personaID: folderId]
func lastSelectedSpace(persona: String) -> String?
func setLastSelectedSpace(_ folderId: String?, persona: String)  // nil removes the key (= All Spaces)
```
Data flow:
- Write: Home `selectedFolderId` didSet/onChange → `settings.setLastSelectedSpace(selectedFolderId, persona: PersonaID.placeholder)`.
- Read (cold launch): Home `.task` → `let saved = settings.lastSelectedSpace(persona: PersonaID.placeholder)`; if `saved` matches a live folder id, apply it; else All Spaces. Runs **before** `autoSelectSingleSpace()` so a restored choice wins.

Interaction with existing auto-select: restoration takes precedence. If nothing persisted, fall through to `autoSelectSingleSpace()` (S1 resolver).

## Related code files
- Create: `Vaultify/App/PersonaID.swift` (~8 lines)
- Modify: `Vaultify/App/SettingsStore.swift` (map property + Key + get/set helpers; init decode `dictionary(forKey:) as? [String:String] ?? [:]`)
- Modify: `Vaultify/Features/Home/HomeScreen.swift` — restore on `.task` (before auto-select), persist on selection change (`:20` state stays, add persistence side-effect at the 3 mutation points: `:68`, `:111`, folder-picker binding `:119`)

## Implementation steps
1. Create `PersonaID.swift` with `placeholder`.
2. `SettingsStore`: add `Key.lastSelectedSpaces = "last_selected_space_by_persona"`; store `[String:String]`; init reads `defaults.dictionary(forKey:) as? [String:String] ?? [:]`; add `lastSelectedSpace(persona:)` / `setLastSelectedSpace(_:persona:)` (setting nil → `removeValue`).
3. HomeScreen: add a `restoreSelectedSpace()` that reads the placeholder key, validates against `env.repository.folders`, sets `selectedFolderId`; call it in `.task` **before** `autoSelectSingleSpace()`; guard so it runs once per launch.
4. HomeScreen: on every `selectedFolderId` change (folder picker, "All Spaces" tap `:111`, auto-select) persist via `setLastSelectedSpace`. Simplest: add `.onChange(of: selectedFolderId) { settings.setLastSelectedSpace($0, persona: PersonaID.placeholder) }`.
5. Guard the single-space auto-select so it does not clobber a validly restored different selection.
6. `make check`; add unit test for get/set/remove + stale-id fallback.

## Todo
- [ ] `PersonaID.placeholder`
- [ ] SettingsStore map + helpers + Key + init decode
- [ ] Home restore-on-task (before auto-select, once/launch, validated)
- [ ] Home persist-on-change (`.onChange(of: selectedFolderId)`)
- [ ] Stale-id fallback to All Spaces
- [ ] Compile + unit test

## Success criteria
- Select Space A → kill → relaunch → Home shows A. Select All Spaces → relaunch → All Spaces.
- Delete restored Space on device B, sync, relaunch device A → falls back to All Spaces, no crash/empty filter.
- `UserDefaults` key holds a `[placeholder: folderId]` dict; nothing hits CloudKit.

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Restored id points at deleted folder | Med×Med | Validate against live `folders` on load; else All Spaces. |
| Restoration fights `autoSelectSingleSpace` | Med×Low | Restore first, once/launch; auto-select only when nothing restored. |
| Over-engineering the map for a P1 that may change | Low×Low | Map is the D7 contract + trivial in UserDefaults; flagged as decision (dict vs flat) below. |

## Security
folderId is non-secret metadata (already plaintext at rest). No sealed data touched. Preference is device-local; excluding it from sync is the privacy-correct default (a selected-Space leak across devices would reveal nothing sensitive but is unnecessary).

## Open decision (confirm before coding)
- **Storage shape:** map `[personaID:folderId]` (recommended — zero P1 migration, matches D7 `lastSelectedSpaceByPersona`) vs flat `String?` (simpler now, reshaped later). Recommend map.
- **Placeholder value** `"__default__"` acceptable as the P0 bucket key?

## Next steps
S2 search default derives from the (now-persisted) current Space. P1 replaces `PersonaID.placeholder` with the active persona id at the 2 call sites.
