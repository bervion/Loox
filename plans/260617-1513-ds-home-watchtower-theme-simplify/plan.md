---
title: DS alignment — Home + Watchtower components & simplified theme settings
description: >-
  Align Home + Watchtower screens to the finalized Design System UI kit, and
  dial the merged Telegram theme engine back to a simple DS-accurate theme
  settings surface (flat backgrounds, 7-preset accent, retuned palette).
  Advanced theming stays in code, gated for later.
status: completed
priority: P2
branch: main
tags:
  - ios
  - swiftui
  - design-system
  - theme
  - home
  - watchtower
blockedBy: []
blocks: []
created: '2026-06-17T08:27:44.100Z'
createdBy: 'ck:plan'
source: skill
---

# DS alignment — Home + Watchtower components & simplified theme settings

## Overview

Two tracks against the now-final **`Design System/`** spec (web source of truth: `ui_kits/ios-app/*`, `tokens/*.css`):

1. **Theme simplification + color fix** (user's primary pain: "color thấy chưa hợp lắm"). Retune builtin palette to `tokens/colors.css`; replace 10-preset+custom accent with the **7 DS presets** (no custom RGB); force **flat themed backgrounds** (gate the wallpaper/mesh/pattern/gradient engine off, keep code); strip wallpaper from the Appearance UI. Advanced Telegram theming returns later by flipping the gate.
2. **Home + Watchtower to DS spec** (user: "hiển thị component nào ở Home, giám sát"). Home = folder switcher header + quick actions + TOTP quick view + "Cần chú ý" (rotation+weak) + Yêu thích + Tất cả mục. Watchtower = ScoreRing speedometer + overall StrengthCard + "Cần xử lý" issue list. Requires a **new rotation-reminder** feature (user chose "bám spec tối đa").

## Confirmed decisions (user, 2026-06-17)

1. **Home faithfulness:** *bám spec tối đa* — build rotation reminders + full "Tất cả mục" list + folder switcher (maps DS "space" → existing **Folders**).
2. **Accent:** *đúng 7 preset design* — blue/indigo/teal/purple/pink/graphite/mono (light+dark from `accents.css`); **remove custom RGB**. (Reverses the earlier "keep 10 + custom" decision in `260616-2345-design-system-standardization`.)
3. **Settings depth:** keep **builtin theme grid + auto-night + text size**; remove **wallpaper/gradient/pattern + custom RGB**. Engine code is **hidden, not deleted**.

## Phases

| Phase | Name | Status | Depends |
|-------|------|--------|---------|
| 1 | [Color & accent foundation (DS palette + 7 presets)](./phase-01-color-accent-foundation-ds-palette-7-presets.md) | ✅ Completed | — |
| 2 | [Flat background & simplified Appearance UI](./phase-02-flat-background-simplified-appearance-ui.md) | ✅ Completed | 1 |
| 3 | [Rotation reminder model & logic](./phase-03-rotation-reminder-model-logic.md) | ✅ Completed | — |
| 4 | [Home DS component library](./phase-04-home-ds-component-library.md) | ✅ Completed | 1 |
| 5 | [Home screen assembly (DS spec)](./phase-05-home-screen-assembly-ds-spec.md) | ✅ Completed | 3,4 |
| 6 | [Watchtower reshape (ScoreRing + strength + issues)](./phase-06-watchtower-reshape-scorering-strength-issues.md) | ✅ Completed | 1 |
| 7 | [Localization](./phase-07-localization.md) | ✅ Completed | 2,5,6 |
| 8 | [docs & QA](./phase-08-docs-qa.md) | ✅ Completed | 1-7 |

**Suggested order:** 1 → 2 (theme, low-risk, ships user's main fix) ‖ 3 (model) → 4 → 5 (Home) ‖ 6 (Watchtower) → 7 → 8.
Tracks Home (3-4-5) and Watchtower (6) can run in parallel after Phase 1.

## Build / verify (every phase)

After adding/removing files: `tuist generate --no-open`, then compile the workspace (CLAUDE.md "Build & run") or `make check` (app + extension). Tests: `make test DEST=...`. Never put the word "build" in paths/log names (hook block).

## Related plans

- `260616-2345-design-system-standardization` — **done** (token system + native tab bar). This plan continues it at screen level + retunes color. Reverses its accent decision #3 per user.
- `260614-1810-telegram-theme-engine` — **merged** (PR #2). This plan **gates its UI off** (flat bg, no wallpaper picker); engine code retained for later re-enable.
- `260614-1449-vault-nav-redesign-home-items` — current Home (Pinned/Recent/Frequent) implements it; this plan **supersedes that Home UI** with the DS-spec Home (personalized sections retired; `pinned`/`favorite`/`useCount` data kept).

## Validation Log

### Session 1 — 2026-06-17 (validate)

**Verification pass (Full tier, 8 phases): Failed: 0.** Verified against code — SwiftData uses
lightweight auto-migration (`VaultStore.swift:12-13`, no `SchemaMigrationPlan`); `VaultItem` already
mirrors `ItemRecord` metadata (`VaultItem.swift:10-18`); derived tokens incl. `onAccent` computed via
`RGBMath` (`AppTheme+Tokens.swift`). Surfaced: builtin `nightTinted` ships a `.gradient` default
(`BuiltinThemes.swift:28`) → redundant under flat-bg.

**Decisions confirmed (user) — all 4 open questions closed + 1 verification finding:**
1. Custom theme editor + `.vaultheme` import/export → **HIDE** (keep code). [→ Phase 2]
2. Watchtower 2FA row → **BUILD** it via a curated "supports 2FA" catalog. [→ Phase 6] **(scope ↑)**
3. Rotation reminder → **ADD OS local notifications** (not in-app only). [→ Phase 3] **(scope ↑)**
4. Customize Home → **RETIRE** (screen + toggles). [→ Phase 5]
5. Builtin themes → **TRIM grid to Day + Night** (keep DayClassic/NightTinted code). [→ Phase 1/2]

### Whole-Plan Consistency Sweep
Re-read `plan.md` + all 8 phases after propagation. No stale terms / contradictions remain; the two
scope-up decisions (2FA build, local notifications) are reflected in Phases 6 + 3. Plan is eligible to
implement (Failed: 0).

## Cook progress (2026-06-17)

Branch `feat/ds-home-watchtower-theme-simplify`. Each commit: `make check` (app+ext) + full test suite green + code-review.

- **Phase 1 + 2 done** — `d618e2c` feat(theme) + `d4bd0e5` docs(plan). 7-preset accent (light/dark), palette retuned, flat-bg gate, simplified Appearance, builtin grid → Day+Night.
- **Phase 3 done** — `2f17096` feat(vault). Rotation reminders + OS local notifications. 15 new tests.
- **Phase 6 done** — `1005b14` feat(watchtower). ScoreRing + StrengthCard + issue categories + 2FA catalog.
- Code-review fixes applied: localization converted to EN-source + VI (the Phase 2/3/6 strings are localized — **Phase 7 now only needs the Phase 4/5 Home strings + a final audit**); 2FA catalog uses host-suffix matching (no substring false-positives).

- **Phase 4 + 5 done** — `94fe20a` feat(home). Folder switcher + quick actions + TOTP quick-view + Needs-attention + Favorites + All (pinned-first); Customize Home / Utilities / old sections retired. Review fixes: pinned-first restored, duplicate nav destination removed, `%lld days` VI added.
- **Phase 7 done** — localization audit: 0/431 keys missing VI.
- **Phase 8 done** — docs synced (`CLAUDE.md`, `design-guidelines.md`, `codebase-summary.md`).

**All 8 phases implemented + verified**: `make check` (app+ext) + full test suite green every slice, code-review per slice, localization audit clean, docs synced. **On-device visual QA is the user's** (theme look, ScoreRing, flat bg, EN↔VI, rotation-notification permission) — automated checks pass; subjective/visual confirmation needs a device pass. Branch not pushed (awaiting user).

**Follow-up (M1, non-blocking):** `rotateDays`/`passwordChangedAt` are device-local; add to `CloudSyncService` CK mapping (behind `#if VAULTIFY_ICLOUD`) if per-item cadence should sync when iCloud is enabled.
