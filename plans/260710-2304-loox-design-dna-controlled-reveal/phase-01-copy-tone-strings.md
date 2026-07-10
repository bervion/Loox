# Phase 1 — Copy-tone + string catalog sweep

**Tier:** T1 · **Priority:** P1 · **Status:** pending · **Depends:** P0 · **Owns:** xcstrings baseline

Enforce "short / calm / confident" copy. Remove `!` and `—` (em-dash) from user-facing EN + VI strings.

## Context
- Audit DNA #8. Tone already ~correct; discrete offenders remain.
- Confirmed offenders: `OnboardingFlow.swift:91` ("Welcome to Loox!" + em-dash "your identity — it autofills");
  `ItemDetailScreen.swift:409` ("Shared with you — you can use…") — **string fixed here, view stays P2's**.
- Clipboard interval verified: `SettingsStore.swift:122` default = 30 (`clipboardClearSeconds`).

## Requirements
1. Sweep `Localizable.xcstrings`: remove `!` (→ period/none) and `—` (→ comma/period/restructure) from all
   user-facing EN values; mirror in VI. Keep meaning; do not flatten VI grammar into EN.
2. `OnboardingFlow.swift:91` — rewrite the identity note: no `!`, no `—`, both languages.
3. `ItemDetailScreen.swift:409` sharedBadge string → no em-dash (P2 owns the view file; **P1 only edits this one
   string literal**, coordinate so P2 doesn't clobber). Prefer: P1 supplies the final string; P2 places it.
4. Honest copy feedback: do NOT use "Copied securely". Standard = `Copied`. When `sensitive && clipboardClearSeconds > 0`,
   optional richer string `Copied · clears in {n}s`. Add both keys EN + VI. (Wiring is P2.)
5. Verify no other `!`/`—` in Swift `Text("…")` literals across touched features (grep sweep).

## Data flow
Strings are static catalog entries. `appString()` / `LocalizedStringResource(...).inAppLocalized` resolve at
runtime via the in-app language toggle. No logic change.

## Files
**Edit**
- `Vaultify/Resources/Localizable.xcstrings` (tone sweep + new `Copied · clears in {n}s` key EN+VI)
- `Vaultify/Features/Onboarding/OnboardingFlow.swift` (line ~91 note string)
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` **(string literal at :409 only — coordinate with P2)**

## Implementation steps
1. Grep the catalog + feature `Text("…")` literals for `!` and `—`; list every hit.
2. Rewrite each EN value; provide the VI translation (missing VI = bug per CLAUDE.md).
3. Fix `OnboardingFlow` note.
4. Add `Copied` (exists) + `Copied · clears in %lld` (new) keys EN+VI.
5. `make check` (string catalog compiles into both targets).

## Todo
- [ ] Catalog `!`/`—` sweep EN
- [ ] Catalog `!`/`—` sweep VI mirror
- [ ] Onboarding welcome note rewritten
- [ ] sharedBadge string de-em-dashed (hand to P2)
- [ ] `Copied · clears in {n}s` key EN+VI
- [ ] grep confirms zero stray `!`/`—` in touched literals

## Success criteria
- No `!` or `—` in user-facing EN/VI strings in the app's copy surfaces.
- Every changed/added key has both EN and VI values.
- Onboarding welcome reads calm, no exclamation.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Em-dash removal changes sentence rhythm awkwardly | M×L | restructure, don't just delete; review each |
| Parallel xcstrings edits with P2–P5 conflict | M×M | P1 lands first; later phases append distinct keys; serialize writes |
| Legitimate `—` in non-UI/dev strings swept | L×L | scope to user-facing values only |

## Rollback
Revert the three files. Copy-only; no structural impact.

## Next
Baseline for P2–P5 copy. P2 wires the `Copied · clears in {n}s` string.
