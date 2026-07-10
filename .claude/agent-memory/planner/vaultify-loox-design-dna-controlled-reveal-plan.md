---
name: vaultify-loox-design-dna-controlled-reveal-plan
description: Plan for the Loox Design DNA Controlled Reveal UI/UX pass (T1+T2+T3), 7 phases, file-ownership parallel
metadata:
  type: project
---

Plan: `plans/260710-2304-loox-design-dna-controlled-reveal/` (branch `feat/design-dna-controlled-reveal`).
Executes the 10-DNA audit `plans/reports/design-dna-audit-260710-2304-loox-apple-award-dna-report.md`. Scope T1+T2+T3 all user-approved.

**Why:** post-PR#79 quality pass; make Home credential-first (protagonist), enforce typography/concentricity, honest calm copy (no ! or —), glyph-resolve reveal, search superpower, ∞ gate motion.

**How to apply:** 7 phases. P0 primitives blocks all (Radius.concentric, GlyphResolveText, CopyMorphIcon, recentlyUsed helper). After P0: P2 ItemDetail / P3 Home / P4 Search / P5 gate-motion own DISJOINT code files → parallel. P1 copy sweep first (baseline). Only shared file = `Localizable.xcstrings` (append distinct keys, serialize). P6 tests+compile+docs last.

**Verify-first deltas from audit (confirmed vs code):**
- ∞ gate motion NOT blocked (audit Q3 wrong): `logo.imageset/logo.svg:12` is a single extractable ∞ bezier (L/X separate :14-15). BrandLogoMark uses a DIFFERENT asset `SharedAssets/BrandLogo.imageset`.
- clipboardClearSeconds default = 30 (`SettingsStore.swift:122`) → honest "Copied · clears in 30s".
- Copy-morph icons already exist: `Icons.copy`/`Icons.copyDone` (ic_clipboard / ic_clipboard_check).
- `TOTPCodeView` is in `TOTPFieldRow.swift:4` (no own file); currently SF body bold — audit wants MonoLisa vaultCode(.title3).
- allItems sorts by updatedAt not lastUsedAt → recents needs new helper.

Reverses part of PR#79 Home layout (approved). Reduce Motion + EN/VI mandatory. iOS 17.6 ceiling (zoom 18+, glass 26+ guarded). Links [[vaultify-loox-ui-ux-redesign-plan]] (prior 13-đợt pass, P0-P5 context).
