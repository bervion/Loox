# Phase 6 — Tests · compile both targets · docs sync

**Tier:** — · **Priority:** P1 · **Status:** pending · **Depends:** P0–P5 merged · **Runs:** last

Verification gate + documentation sync. No feature work.

## Context
- Build: `tuist generate --no-open` then xcodebuild per CLAUDE.md (never the bare word "build" in paths/log names;
  reach products via `*uild` glob). `make check` = app + embedded extension compile.
- Tests: `make test` (VaultifyTests; pattern = in-memory VaultStore + `adoptUnlocked` fixed key).

## Requirements
1. **Compile** both targets clean (app + AutoFill extension) — new files globbed in via `tuist generate`.
2. **Unit tests** for pure/testable logic added this pass:
   - `Radius.concentric` boundary cases (clamps to `xs`).
   - `SearchOperators` keyword→predicate map (EN+VI keywords, composition with free text, isolation-within-scope).
   - `recentlyUsed` ordering (most-recent `lastUsedAt` first, excludes never-used).
   - OTP `TOTPCodeView.format` grouping unchanged (regression).
3. **Manual QA matrix** (device/sim, cannot be unit-tested): Reduce Motion + Reduce Transparency on every new
   motion (glyph resolve, copy morph, gate motion, zoom); light + dark; SE + Pro Max + XXL Dynamic Type;
   in-app EN↔VI toggle on all changed strings; Home reorder regression (persona/Space filter, shared feed).
4. **Docs sync**: `docs/design-guidelines.md` (concentricity rule P0, Controlled Reveal section P5),
   `docs/codebase-summary.md` (new components: `GlyphResolveText`, `CopyMorphIcon`, `LooxGateShape`,
   `SearchOperators`, `recentlyUsed`; Home/ItemDetail/Search behavior changes).

## Files
**Create/Edit:** `VaultifyTests/…` (new test files for the units above)
**Edit:** `docs/design-guidelines.md`, `docs/codebase-summary.md`

## Todo
- [ ] `tuist generate` + `make check` green (app + extension)
- [ ] `make test` green
- [ ] tests: `Radius.concentric`, `SearchOperators`, `recentlyUsed`, OTP `format`
- [ ] manual QA matrix walked (Reduce Motion/Transparency, light/dark, Dynamic Type, EN/VI)
- [ ] Home reorder regression (persona/Space/shared feed)
- [ ] `docs/design-guidelines.md` synced (concentric + Controlled Reveal)
- [ ] `docs/codebase-summary.md` synced (new components/behaviors)

## Success criteria
- Both targets compile; `make test` all green (no skipped/failed).
- New pure logic covered by unit tests; QA matrix signed off.
- Docs reflect the new primitives and screen behaviors.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Extension build breaks (VaultifyCore globs) | L×H | `make check` builds embedded extension too; run before ship |
| UI motion regressions invisible to unit tests | M×M | explicit manual QA matrix; screenshots before/after Home + ItemDetail |
| Missing VI translation slips through | M×M | grep changed keys for VI presence; String Catalog "stale" audit |

## Rollback
Docs/tests are additive; no product rollback here. If a test exposes a regression, fix in the owning phase's files.

## Next
Ship gate. After green: commit per conventional commits, then release flow when approved.
