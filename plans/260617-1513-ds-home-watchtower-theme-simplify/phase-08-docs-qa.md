---
phase: 8
title: "docs & QA"
status: pending
priority: P2
effort: "2-4h"
dependencies: [1, 2, 3, 4, 5, 6, 7]
---

# Phase 8: docs & QA

## Overview

Final integration: update docs + `CLAUDE.md` so future sessions comply with the simplified theme model
and the DS-aligned Home/Watchtower; run the full build + test + on-device QA matrix.

## Requirements

- Functional: docs reflect 7-preset accent (no custom RGB), flat-background gate, rotation feature, new
  Home/Watchtower composition.
- Non-functional: `make check` (app + extension) + `make test` green; QA matrix passes.

## Related Code Files

- Modify: `docs/design-guidelines.md` — accent set now 7 DS presets (light/dark); wallpaper engine
  gated off (`WallpaperFeature.decorativeEnabled`); flat-background contract; Home/Watchtower component
  inventory.
- Modify: `docs/codebase-summary.md` — rotation fields on `ItemRecord`; new Home/Watchtower files;
  retired Customize Home (per Open Q4).
- Modify: `CLAUDE.md` — Design System section: accent = 7 presets, no custom RGB; flat backgrounds
  (engine gated); rotation reminder feature note.
- Optional: `docs/development-roadmap.md` / changelog entry.

## Implementation Steps

1. Reconcile docs with shipped reality (read final code, not the plan).
2. Update `CLAUDE.md` Design System + Don'ts (e.g. "no custom RGB accent; 7 DS presets").
3. `tuist generate --no-open` → `make check` (app + embedded extension) → `make test DEST=...`.
4. On-device/simulator QA matrix; capture issues; fix or log.

## QA matrix

- Light / Dark / Increased Contrast / Reduce Transparency / Reduce Motion — no invisible text/icons,
  no light↔dark desync after live theme+accent switch.
- All 7 accents: `onAccent` legible in light + dark; tab indicator + selected states correct.
- Device scale: iPhone SE (0.9x) → Pro Max (1.12x) — 44pt hit targets, no clipping.
- Language: EN + VI toggle across Home, Watchtower, Appearance, editor rotation.
- Functional: rotation overdue/soon surfaces in "Cần chú ý"; TOTP copy; Watchtower drill-downs; HIBP
  k-anonymity; existing vault opens (no migration data loss).
- AutoFill extension: themed colors resolve with the retuned palette; flat background.

## Todo List

- [ ] design-guidelines.md updated
- [ ] codebase-summary.md updated
- [ ] CLAUDE.md updated (accent/flat-bg/rotation)
- [ ] `make check` (app + ext) green
- [ ] `make test` green
- [ ] QA matrix passed (a11y, scale, EN+VI, extension)

## Success Criteria

- [ ] Docs + CLAUDE.md teach the simplified theme model; no stale "10 presets + custom" guidance.
- [ ] Full build + tests pass; QA matrix clean; existing vaults intact.

## Risk Assessment

- **Doc drift**: write docs from final code, not from this plan, to avoid encoding superseded choices.
- **Extension parity**: easy to forget — explicitly QA the AutoFill target's theming.

## Security Considerations

Confirm no secrets/notes/strength values leaked into plaintext columns or logs introduced this plan.
