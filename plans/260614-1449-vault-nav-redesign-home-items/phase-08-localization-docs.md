# Phase 08 — Cross-cutting: Localization (EN+VI) + Docs + CloudKit verify

## Context Links
- String catalog: `Vaultify/Localizable.xcstrings` (EN source + VI translation — MANDATORY)
- Localization helpers: `VaultifyCore/Localization.swift` (`appString()`, `.inAppLocalized`)
- Project conventions: `CLAUDE.md` (localization MANDATORY; missing VI = bug)
- Docs to sync: `docs/codebase-summary.md`, `README.md`, `docs/system-architecture.md` (if present)
- CloudKit: `Vaultify/Services/Sync/CloudSyncService.swift` (compile-gated `VAULTIFY_ICLOUD`)

## Overview
- **Priority:** P1 (localization is non-negotiable per CLAUDE.md)
- **Status:** pending
- **Depends:** Phases 1–7 (collects all new strings + structural changes).
- Ensure every new user-facing string has BOTH EN + VI in `Localizable.xcstrings`; update docs to
  reflect the new navigation + Pin/Archive/Frequently-Used concepts; verify the CloudKit mapping
  compiles under the `VAULTIFY_ICLOUD` flag.

## Key Insights
- The project mandates EN+VI for every string; a missing VI value is a **bug**. New
  `LocalizedStringResource` **titles** use `.inAppLocalized`; runtime strings use `appString()`;
  `TextField`/`SecureField` titles must be `LocalizedStringKey` (not `LocalizedStringResource`) at the
  17.6 target. SwiftUI `Text("…")` literals auto-extract to the catalog on build — still need VI.
- New strings introduced across phases (collect + translate):
  - Tabs: "Home", "Items", "Watchtower", "Search" (Watchtower likely already present).
  - Home sections: "Pinned", "Favorite"/"Favorites", "Recently Created", "Frequently Used",
    "Recently Used", "Recently Modified", "Utilities", "Password Generator".
  - Customize: "Customize Home", section toggle labels (reuse the section titles).
  - Items: "Create Space", "Categories", "Tags", "Spaces", "Archive", "Recently Deleted",
    category section header, empty-states.
  - Actions: "Pin"/"Unpin", "Archive"/"Unarchive".
  - Search: prompt + empty-state copy.
- Some strings already exist (e.g. "Favorites", "Spaces", "Recently Used", category titles via
  `ItemCategory.title`) — reuse existing keys; don't create duplicates (DRY in the catalog).
- CloudKit is compile-gated OFF by default (`isConfigured` false unless `VAULTIFY_ICLOUD`). `make check`
  does NOT exercise the flag → the new `ckRecord`/`apply` lines compile only when the flag is set.
  **Verify-compile** the CloudKit path explicitly (see steps) so the mapping isn't silently broken.

## Requirements
**Functional:** all new UI strings render in EN and switch to VI under the in-app language toggle.
**Non-functional:** no hard-coded user-facing literals; docs reflect new nav; CloudKit mapping compiles
under the flag.

## Architecture
- Strings flow: code uses `appString("…")` / `Text("…")` / `.inAppLocalized` → keys land in
  `Localizable.xcstrings` → each key needs `en` + `vi`. Verify via the catalog (no "stale"/missing-VI).
- CloudKit verify: a one-off compile with `VAULTIFY_ICLOUD` in Swift Active Compilation Conditions to
  confirm the 3 new keys map without type errors (no actual iCloud account needed for compile).

## Related Code Files
**Modify:**
- `Vaultify/Localizable.xcstrings` — add EN+VI for every new string (list above). Reuse existing keys
  where present.
- `docs/codebase-summary.md` — update navigation section (4 tabs Home/Items/Watchtower/Search; Settings
  gear; Generator in Utilities), new metadata (pinned/archived/useCount), ArchiveScreen, Customize Home.
- `README.md` — update any nav/feature description + screenshots-list mention if applicable.
- `docs/system-architecture.md` (if present) — note the new ItemRecord columns + cache split + CloudKit
  field additions.
- (No code change unless localization sweep finds a hard-coded literal to wrap.)

## Implementation Steps
1. Grep new screens for any non-localized `Text("…")` / string literals; wrap per convention.
2. Open `Localizable.xcstrings`; for each new key add EN source + VI translation. Reuse existing keys.
3. Build → confirm no new auto-extracted key is missing a VI value (catalog shows no "stale"/needs-review
   for VI on the new keys). Optionally run a quick check that every new English key has a `vi` entry.
4. Update `docs/codebase-summary.md` + `README.md` (+ system-architecture if present).
5. CloudKit verify-compile: temporarily build with `VAULTIFY_ICLOUD` (e.g. `xcodebuild ...
   SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) VAULTIFY_ICLOUD'`, keeping the `build`-token rule —
   use `xcodebuild` default action, safe `-derivedDataPath`/log names) to confirm `ckRecord`/`apply`
   compile with the 3 new fields. Do NOT commit the flag.
6. `make check` green (flag off).

## Todo List
- [ ] Wrap any hard-coded new literals
- [ ] Add EN+VI for every new string (reuse existing keys)
- [ ] Verify no missing VI on new keys
- [ ] Update codebase-summary + README (+ system-architecture)
- [ ] CloudKit verify-compile under VAULTIFY_ICLOUD (not committed)
- [ ] `make check` green

## Success Criteria
- App fully localized: switching to VI shows VI for all new screens/sections/actions.
- No missing VI values for new keys (no catalog warnings on them).
- Docs reflect the new navigation + concepts.
- CloudKit mapping compiles under the flag; default (flag-off) `make check` green.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| Missing VI translation (= bug) slips through auto-extracted Text literals | Med×Med | Explicit catalog pass + a grep/script listing English keys lacking `vi`. |
| Duplicate catalog keys (e.g. another "Favorites") | Low×Low | Search catalog for existing key before adding; reuse. |
| CloudKit mapping silently broken (flag off in CI) | Med×Med | Mandatory verify-compile step under the flag this phase. |
| `LocalizedStringResource` used where `LocalizedStringKey` required (TextField title, iOS 17.6) | Low×Med | None of the new screens add TextFields with LSR titles; double-check Customize/Create-Space inputs. |

## Security Considerations
- Translations are static UI text — no secrets. CloudKit verify uses no real account (compile only); the
  zero-knowledge model is unchanged (still only sealed blobs + metadata uploaded).

## Next Steps
Phase 9 runs the full test + build verification.
