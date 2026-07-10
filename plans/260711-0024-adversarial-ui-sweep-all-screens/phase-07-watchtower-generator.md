# Phase 7 — Watchtower + Generator

**Status**: pending · **Wave**: W2 · **Owns**: `Watchtower/*`, `Generator/*` (10 surfaces).
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Watchtower = "what should I fix, in order". Generator = "produce a strong value and use it".

## Cluster hotspots
- **WatchtowerScoreRing**: 270° gauge, intro sweep then settle, counting number. Reduce Motion → show final
  value instantly (rule 5, motion never gates result). Band label + color are SEMANTIC roles: ≥80 "Fairly
  secure" / ≥50 "Needs attention" / <50 "At risk" — verify red/amber/green come from roles, not raw colors.
- **WatchtowerStrengthCard**: % bar grow-in animation; spectrum fill uses roles; Reduce Motion collapses.
- **WatchtowerScreen / WatchtowerCategoryScreen / WatchtowerComponents**: to-fix categories appear only when
  count>0, fixed order (Compromised/Reused/Weak/Missing-2FA); "All clear" card replaces list at 0 issues;
  HIBP toggle + k-anonymity footnote honest; "Checking breaches…" overlay state intentional.
- Category row: icon tile + title + description + count badge + chevron; badge count fits; VI descriptions
  ("Đã lộ trong rò rỉ dữ liệu") don't clip at SE.
- **GeneratorScreen / PasswordGeneratorView**: output card tap-to-copy → single `Haptics.success` (service);
  `SecretColoring` for digit/letter/symbol tint (allowed) but not raw semantic-surface colors; strength meter
  reused (Phase 1). Sliders → `Haptics.tap` per change (single, not doubled); Regenerate always present, "Use"
  only when opened from editor. Passphrase/PIN modes reflow controls at SE + Dynamic Type XL.

## Deliverables / Todo
`reports/findings-phase-07.md` · `strings-manifest-phase-07.md` · fixes.
- [ ] Protocol answers (10). [ ] 6 greps. [ ] Ring/bar Reduce-Motion instant-value verified.
- [ ] Band colors semantic. [ ] Generator copy/slider haptics single-fire. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; score/strength motion collapses under Reduce Motion; category empty/all-clear/
checking states intentional; generator copy is single-haptic; EN+VI. Risk: gauge animation math may hardcode
colors (Med×Med) → route through roles; keep durations in `Motion` range.
</content>
