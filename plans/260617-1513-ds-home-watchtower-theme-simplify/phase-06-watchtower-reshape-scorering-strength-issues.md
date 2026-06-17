---
phase: 6
title: Watchtower reshape (ScoreRing + strength + issues)
status: completed
priority: P2
effort: 5-7h
dependencies:
  - 1
---

# Phase 6: Watchtower reshape (ScoreRing + strength + issues)

## Overview

Reshape Watchtower (Giám sát) to the DS spec (`Design System/ui_kits/ios-app/Watchtower.jsx`):
a **speedometer ScoreRing**, an overall **StrengthCard**, and a single **"Cần xử lý"** grouped list of
issue categories (count badge + chevron → drill into that category). Replaces today's simple ring +
inline expanded lists. Reuses existing `PasswordAudit` data; independent of the Home track (needs only
Phase 1 colors).

## Requirements

- Functional: 270° gauge with band label; overall strength bar; category rows (compromised / reused /
  weak) each → a drill-down list; HIBP toggle retained; "all clear" state.
- Non-functional: gauge animates score (Reduce-Motion → jump); token-driven; localized; offline-first.

## Key Insights

- Data already exists: `Services/Watchtower/PasswordAudit.swift` (`weak`/`reused`/`pwned`/`score`) +
  `HIBPService.swift`. This phase is mostly **UI restructure**, not new analysis.
- DS gauge: 270° arc open at bottom, green→blue gradient fill, ticks, marker triangle, center score
  (52pt) + band: `≥80 Khá an toàn` / `≥50 Cần chú ý` / `<50 Rủi ro cao` (`Watchtower.jsx:75-79`).
- "Overall strength" (StrengthBar) is **distinct** from the health score — it's the average password
  strength; health score penalizes weak+reused. Add an avg-strength value to `PasswordAudit`.
- 2FA suggestion row → **BUILT** via a curated "supports 2FA" catalog (confirmed Session 1 — see updates below).

## Architecture

`WatchtowerScreen` → `ScoreRing` + `StrengthCard` + "Cần xử lý" `CategoryRow`s → tap →
`WatchtowerCategoryScreen` (filtered issue list reusing existing issue rows).

## Related Code Files

- Create: `Vaultify/Features/Watchtower/WatchtowerScoreRing.swift` — SwiftUI 270° gauge (Path/trim or Canvas), gradient + ticks + marker + center readout + band label.
- Create: `Vaultify/Features/Watchtower/WatchtowerStrengthCard.swift` — "Độ mạnh mật khẩu tổng thể" + segmented strength bar + chevron (tappable).
- Modify: `Vaultify/Features/Watchtower/WatchtowerComponents.swift` — replace `HealthGauge` usage; add `CategoryRow` (IconTile + title + subtitle + count Badge + chevron). Keep `WatchtowerIssueRow` for drill-down.
- Rewrite: `Vaultify/Features/Watchtower/WatchtowerScreen.swift` — title → ScoreRing → subtitle → StrengthCard → "Cần xử lý" category list → HIBP toggle; "all clear" state.
- Create: `Vaultify/Features/Watchtower/WatchtowerCategoryScreen.swift` — drill-down list for one category (compromised/reused/weak), rows → item detail.
- Modify: `Vaultify/Services/Watchtower/PasswordAudit.swift` — add `overallStrength` (avg normalized 0–100) alongside `score`.

## Validation Session 1 updates
<!-- Updated: Validation Session 1 - build the 2FA suggestion row -->

- **Build the "2FA" suggestion row** (Open Q2 resolved — NOT omitted).
  - Create `Vaultify/Services/Watchtower/TwoFactorCatalog.swift`: a curated, bundled set of common
    services (matched by domain/url, fallback by name) known to support 2FA. Conservative + easy to extend.
  - Extend `PasswordAudit`/`VaultHealth` with `missing2FA` (items matching the catalog but with no TOTP
    field). Surface as a 4th "Cần xử lý" category: "Bật xác thực 2 lớp · N mục" (accent tone), tap →
    drill-down list → open item to add 2FA.
  - Acknowledged: catalog coverage is imperfect; only suggest for confident matches (no false alarms).

## Implementation Steps

1. `PasswordAudit`: compute `overallStrength` (mean per-item password strength, 0–100); keep `score`.
2. `WatchtowerScoreRing`: port geometry (270°, START 135°, SWEEP 270°); animate fill; band thresholds;
   Reduce-Motion → no sweep animation.
3. `WatchtowerStrengthCard`: filled portion = `overallStrength`%; spectrum remainder; tappable (→ a
   strength explainer or the weak category).
4. `CategoryRow` + category list: rows for compromised (destructive), reused (warning), weak (warning)
   with counts from `VaultHealth`; render only non-zero; tap → `WatchtowerCategoryScreen`.
5. Keep HIBP toggle (bottom) + "Checking breaches…" overlay + pull-to-refresh `fullAudit()`.
6. "All clear" when no issues. `tuist generate --no-open` → compile.

## Todo List

- [ ] `overallStrength` in PasswordAudit
- [ ] ScoreRing speedometer (animated, RM-safe, band labels)
- [ ] StrengthCard with overall strength bar
- [ ] "Cần xử lý" category rows + drill-down screen
- [ ] HIBP toggle + all-clear retained
- [ ] `make check` passes

## Success Criteria

- [ ] Gauge + band match DS at score 0/49/50/79/80/100 boundaries.
- [ ] Category rows show correct counts; tapping drills into the matching items.
- [ ] HIBP k-anonymity flow unchanged; offline weak/reused still computed.

## Risk Assessment

- **Gauge math in SwiftUI** (arc + ticks + marker) is fiddly → build with `Canvas`/`Path`; snapshot a
  few scores during dev.
- **overallStrength vs score confusion** → label clearly; document the difference.

## Security Considerations

HIBP unchanged (SHA-1 prefix k-anonymity, padding). No password values leave device; no logging of
breach details.
