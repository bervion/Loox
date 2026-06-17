# DS Alignment: Theme Simplification + Home + Watchtower Rebuild

**Date**: 2026-06-17 16:10
**Severity**: High
**Component**: Design System, Theme, Home, Watchtower
**Status**: Completed

## What Happened

Closed out an 8-phase plan to align Vaultify against the finalized Design System spec. Simplified the merged Telegram theme engine (7-preset accent, flat backgrounds, palette retuned to `colors.css`); rebuilt Home (folder switcher → quick actions → TOTP quick-view → "needs attention" + favorites + all-pinned-first); reshaped Watchtower (270° ScoreRing, overall StrengthCard, issue categories + 2FA suggestion row). Added password-rotation reminders with OS local notifications. All 8 phases shipped clean builds + test passes + code reviews. PR #4 ready (8 commits, not merged pending user's on-device visual QA).

## The Brutal Truth

Got to "all phases verified" only because of obsessive slice-by-slice validation. The moment the IDE reported "cannot find type" for same-module symbols after every single edit, I *could* have panicked or trusted the error — instead, I validated each one with `make check`, which caught **all stale flags**. That's the exhausting reality: Tuist-generated projects don't index reliably in SourceKit, so the build is your only honest signal. Wasted mental energy doubting myself on every keystroke, but no bugs leaked.

The subagents writing Vietnamese as the source literal in `Localizable.xcstrings` was painful — the project is English-source, Vietnamese-translated by design (standard WWDC practice). Code-review caught it immediately (H1 review), and we re-did the catalog EN-first; final audit came back 0/431 missing VI. Clear lesson: locale model must be explicit in the brief, not assumed.

## Technical Details

**Theme simplification (Phase 1–2):**
- Reversed the prior "keep 10 presets + custom RGB" decision → "7 DS presets only" (user-confirmed during validate). Required tolerant Codable decode on `AccentColor` to drop removed cases gracefully.
- Palette retuned from the merged Telegram engine back to `Design System/tokens/colors.css` light/dark pairs.
- Wallpaper/mesh/pattern/gradient engine **hidden, not deleted** (gated behind `WallpaperFeature`). Appearance UI simplified: builtin theme grid (Day + Night only; code for DayClassic/NightTinted retained), auto-night toggle, text size. No custom theme editor, no `.vaultheme` import/export UI.
- Stripped `nightTinted.gradient` default (redundant under flat-bg).

**Rotation reminders (Phase 3):**
- New model: `rotateDays` + `passwordChangedAt` columns on `ItemRecord` (plaintext); pure `RotationStatus` enum (overdue/due/scheduled/exempt).
- OS local notifications via `UNUserNotificationCenter` (scoped, idempotent). 15 new tests.
- CloudKit mapping deferred (behind `#if VAULTIFY_ICLOUD`, marked non-blocking follow-up M1).

**Home rebuild (Phases 4–5):**
- New component library: `FolderSwitcher`, `QuickActionsRow`, `TOTPQuickView`, `RotationCard`, `FavoritesSection`, `AllItemsSection`.
- Screen assembly: live folder switcher header (adapts to folder count) + sticky quick actions + TOTP quick-view (shows upcoming expirations) + "Needs Attention" (rotation + weak strength) + Favorites + All (pinned first).
- Retired: Customize Home screen, Utilities section, old Pinned/Recent/Frequent sectioning.
- Pinned-first logic restored after code-review catch.

**Watchtower reshape (Phase 6):**
- ScoreRing: 270° arc speedometer (red/yellow/green bands) showing vault score 0–100.
- StrengthCard: summary (N weak, N exposed, N 2FA missing).
- Issue categories: grouped "Weak passwords" + "Exposed" + "Missing 2FA" lists.
- 2FA catalog: curated list of 50+ services (hard-coded, maintainable). Host-suffix matching (not substring) to avoid false positives (e.g., "x.com" no longer matches "netflix.com").

**Localization (Phase 7):**
- EN-source keys + VI translations. Subagent wrote 3 phases in VI-source initially; code-review flagged, fixed to EN-source model. Final audit: 0/431 keys missing VI.
- UI strings use `LocalizedStringResource` with `.inAppLocalized()` for title-fields (iOS 17.6+ compat); runtime uses `appString()`.

## What We Tried

1. **Accent decision**  
   - Path A: Keep 10 presets + custom RGB (prior plan decision).  
   - Path B: 7 DS presets only (user-confirmed during validate → chose B).  
   - Mitigation: Tolerant Codable (ignores missing cases) so old `.vaultheme` files don't crash.

2. **2FA row in Watchtower**  
   - Path A: Hardcode "popular" services (Discord, GitHub, etc.).  
   - Path B: Build a real curated catalog from research.  
   - Chose B (user's "hiển thị đúng services"), gave us 50+ entries; substring matching caused false positives initially → tightened to host-suffix.

3. **Rotation reminder notifications**  
   - Path A: In-app alerts only (cheaper, already in model).  
   - Path B: OS local notifications (user experience, consistency with system).  
   - Chose B (user confirmed during validate), added UNUserNotificationCenter scoped delivery.

4. **Builtin theme grid**  
   - Path A: Keep all historical builtins (DayClassic, NightTinted, 8+ others).  
   - Path B: Trim to Day + Night; gate others in code (simplify UI, preserve engine for later).  
   - Chose B (trim to 2, hide 4 in code); validation found redundant `.gradient` default on NightTinted → removed.

## Root Cause Analysis

Why the session held together despite friction:

1. **Slice-by-slice validation** — each phase built (app + extension), ran tests, passed code-review before commit. Caught the SourceKit false-positives early and independently verified with `make check`.
2. **Explicit locale brief** — after subagents wrote VI-source initially, the code-review team (H1) caught it immediately. Lesson: locale model isn't obvious; must be stated front-and-center.
3. **User validation interview during plan** — the 5-question sweep (custom editor hide/show, 2FA build/skip, notification scope, Customize Home, builtin trim) closed all open decisions *before* implementation. No mid-phase reversals.
4. **Honest scope-up acceptance** — two decisions increased scope (2FA catalog build, OS notifications) but were user-confirmed, so no backpedaling needed.

The core friction came from **relying on IDE signals in a Tuist-generated project**. SourceKit's index doesn't regenerate after `tuist generate` in the simulator env. The build system is the source of truth, not the IDE's squiggles.

## Lessons Learned

1. **Tuist projects require build-first validation** — SourceKit false-positives are expected in Tuist-generated workspaces. Never trust the IDE error until `make check` (or equivalent xcodebuild + workspace) confirms it. Automated checks are your only honest signal.

2. **Locale model must be explicit in briefs** — "multi-language app" is not enough. State it: "English-source keys in Localizable.xcstrings; Vietnamese translations required; use `.inAppLocalized()` for UI strings; test with VI locale active."

3. **Plan validation before cook pays dividends** — the 5-question decision sweep (custom editor, 2FA scope, notification delivery, Customize Home retirement, builtin trim) meant zero mid-phase "wait, should we actually do this?" moments. Hard decisions early; clean implementation later.

4. **Substring matching in catalogs is a landmine** — "x.com" ⊂ "netflix.com" is a false positive. Use domain-suffix matching or explicit key lists for services. Cost of the bug: user adds Netflix, sees suggestion for X.com (noise).

5. **Visual QA lives outside the test suite** — colors, ScoreRing arc rendering, flat-background consistency, rotation-notification appearance — all live. Automated tests verify structure + behavior; subjective judgment (do the colors look right per the Design System?) needs human eyes on the device. Mark this boundary in acceptance criteria.

## Next Steps

1. **User on-device visual QA** — PR #4 awaits user's pass on iPhone (theme colors, ScoreRing rendering, Home layout, Watchtower layout, EN↔VI toggle, rotation-notification permission prompt).
2. **CloudKit sync for rotation columns** (M1, non-blocking) — add `rotateDays` + `passwordChangedAt` to `CloudSyncService` CK mapping (behind `#if VAULTIFY_ICLOUD`) if per-item rotation cadence should sync across devices.
3. **Merge PR #4** once visual QA clears.

---

**Status**: DONE
**Summary**: All 8 phases delivered (theme simplification + Home rebuild + Watchtower reshape + rotation reminders + localization). App + extension compile clean, test suite green, code-reviewed, 0/431 localization keys missing VI. PR #4 ready; awaits user on-device visual confirmation.
**Concerns**: None — verified by build + tests + review. SourceKit noise in Tuist env is environment noise, not code noise; already documented.
