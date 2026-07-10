# Phase 7 — Watchtower + Generator

**Status**: done · **Wave**: W2 · **Owns**: `Watchtower/*`, `Generator/*` (10 surfaces).
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
`reports/phase-07-findings.md` · `strings-manifest-phase-07.md` · fixes.
- [x] Protocol answers (10). [x] 6 greps. [x] Ring/bar Reduce-Motion instant-value verified.
- [x] Band colors semantic. [x] Generator copy/slider haptics single-fire. [x] Fixes + manifest.

Done 260711. See `reports/phase-07-findings.md` for the full table. Highlights: empty-vault
scaffolding bug fixed, an unlocalized HIBP detail string fixed (+ a sibling one flagged
out-of-scope in `PasswordAudit.swift`), score-ring safety gradient rewired from fixed hex to
`theme.destructive/warning/success` (RGBMath.blend), strength-bar fill routed to `theme.color(.success)`,
CategoryRow title lineLimit 1→2 (EN title clipped at SE), Generator's copy icon/toast switched to
the shared `CopyMorphIcon`/`CopyToastOverlay` primitives (was reinventing both), missing haptic on
"Use Password" added. Compile green (app + AutoFill extension).

## Success / Risk
Success: audit-grep clean; score/strength motion collapses under Reduce Motion; category empty/all-clear/
checking states intentional; generator copy is single-haptic; EN+VI. Risk: gauge animation math may hardcode
colors (Med×Med) → route through roles; keep durations in `Motion` range.
</content>
