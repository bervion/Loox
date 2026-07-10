# Phase 3 — Home + Search (re-review)

**Status**: pending · **Wave**: W2 · **Owns**: `Home/*`, `Search/*` (16 surfaces).
Both reworked by the prior DNA pass → REGRESSION + consistency re-review; expect fewer NEW findings.
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Home = "find and use a credential instantly". Search = "narrow the pool to the one you want".

## Cluster hotspots
- **HomeScreen / HomeSection**: protagonist order already set (credential-first). Verify no section
  competes above All-Items; empty-vault state ("Your vault is empty") intentional; sections hide when empty.
- **HomeHeaderBar**: floating glass header — glass only on the control layer (rule 2). Notification bell
  badge "9+" fits; Add/Settings glyph hit areas ≥44.
- **QuickActionCard** (2×2): at SE + Dynamic Type XL the 2×2 must not squeeze — reflow rather than clip;
  card labels EN+VI ("Generate Password" / "Tạo mật khẩu"). Tint/glass on iOS 26 guarded.
- **TotpCardView / TotpRingView**: OTP renders grouped `123 456` as a typographic object (`Font.vaultCode`),
  countdown ring → amber ≤10s / red ≤5s via semantic roles; Reduce Motion shows seconds not ring; tap =
  copy → single `Haptics.success` from `ClipboardService` (card must not double it).
- **AttentionCell**: reason color (overdue/weak red, soon amber) semantic; "Change" button ≥44; row tap → detail.
- **SearchScreen / SearchZeroStateView**: zero-state (recents + filter chips) works; scope chips only when
  >1 scope; recognized operator never worsens results (falls back to literal); "No results in {scope}" +
  Search-all-Spaces is a real escape, not a dead end. Strictly-anonymous persona blocks All-Spaces (fail-closed).

## Deliverables / Todo
`reports/findings-phase-03.md` · `strings-manifest-phase-03.md` · fixes.
- [ ] Protocol answers (16). [ ] 6 greps. [ ] SE 2×2 reflow check. [ ] OTP haptic single-fire.
- [ ] Search zero-state + operator-fallback states walked. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; Home reads credential-first at first glance on SE and Pro Max; Search zero/one/
many/no-result states all intentional; EN+VI. Risk: re-touching prior-pass files may reopen settled
decisions (Med×Low) — only fix real new findings, don't churn.
</content>
