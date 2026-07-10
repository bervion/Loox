# Phase 3 — Home + Search (re-review): Findings

Scope: 18 surfaces (registry row 3: 15 View/component surfaces + 3 private `QuickActionCard`
ButtonStyle/ViewModifier gap-additions) across `Home/*`, `Search/*`. This is a RE-REVIEW of a
screen reworked twice very recently — layout/section order/reveal decisions are settled (per
phase brief) and were NOT touched; only residual defects against `docs/design-dna-standard.md`
were checked and fixed. Method: adversarial protocol Q1-5 + the 6 audit greps.

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| HomeScreen (root) | HomeScreen.swift | "find and use a credential instantly" — protagonist band (shares/approval → TOTP → Needs Attention → Recently Used → Favorites → All) leads; identity strip + quick actions demoted below/after. First glance on both SE and Pro Max reads credential-first. | copy calm throughout, no `!`/`—`/`·` in UI strings (checked: "Your vault is empty", "Sort", "Change", "No results in %@" etc., all VI-present) | see per-control rows below | tokens throughout (`Space`/`Radius`/`Metric`); no numeric padding beyond documented shadow-bleed (see Deferred) | empty-vault / has-items(all 6 conditional sections show/hide correctly) / shared-only-vault (empty local + incoming share = feed, not empty state) all verified in code path | none (structural) | — | — | pass |
| profileRow ("acting as" identity strip) | HomeScreen.swift | thin identity line, correctly demoted below the protagonist alerts but above credential content — doesn't compete | "Set up your identity" / persona name+kind/email calm; VI fits SE | **row was ~32pt tall (24pt avatar + `Space.s1`×2 padding) — under 44pt; phase brief explicitly flagged this "thin identity strip"** | avatar 24pt (doc comment said "28pt" — stale) | n/a (identity always present, kind/email fallback covered) | 2 defects (hit target, stale doc comment) | added `minHeight: Metric.hitMin` to the existing `.frame(maxWidth: .infinity, ...)`; corrected doc comment 28pt→24pt | medium (hit target) / low (comment) | fixed |
| homeSectionHeader (View All action), allItemsHeader (Sort + Space-switcher) | HomeScreen.swift | section-header row: label + optional secondary text action | "Sort"/"View All" calm, short | **all 3 text-only buttons had no hit-target frame (~20-24pt tall) — phase brief explicitly flagged "section-header buttons (Sort, View All, Space switcher)"** | `HStack(alignment: .lastTextBaseline)` in both headers — both sides render the identical `.sectionLabel` style, so baseline vs. center is visually identical today | header appears once per non-empty section; no state variance | 1 defect (hit target) × 3 buttons | switched both HStacks to `.center` (safe: same font both sides) then added `.frame(minHeight: Metric.hitMin).contentShape(Rectangle())` to all 3 buttons (View All, Sort, Space-switcher) | medium | fixed |
| pendingSharesSection, approvalAttentionRow rows | HomeScreen.swift | time-sensitive share/approval alerts, correctly ranked above TOTP | status copy calm ("ready to confirm" / "waiting for %@"), no banned punctuation | rows already ≥`Metric.hitMin` via `.frame(minHeight:)` | tokens throughout (`Space.s4` padding, `Radius.md`) | 0/1/many pending shares and approvals all handled (single → direct sheet, several → notifications inbox) | none | — | — | pass |
| totpSection (scroller), TotpCardView | HomeScreen.swift, TotpCardView.swift | "use this credential's live code" | "Copied"/"Đã sao chép" honest, no over-claim ("Copied" not "Copied securely") | tap-to-copy on full card (≥158×~100pt, comfortably ≥44pt) | card matches DS TotpCard spec (`Radius.md`, hairline stroke); `EdgeInsets(12,14,12,14)` — 14 isn't on the 4pt grid (see Deferred) | 0 items → section hidden entirely (verified); 1/many → `ScrollView(.horizontal)`; countdown ≤10s amber/≤5s red via semantic roles; Reduce Motion → numeric countdown (verified `TotpRingView.reduceMotion` branch) | **3 defects: (a) OTP code used raw `.font(.title3.weight(.bold))` instead of `Font.vaultCode` — the app's own convention for every other code/secret display (`ItemDetail/TOTPCodeView`, `LargeTypeView`, sharing code sheets) — and had no `minimumScaleFactor`/`lineLimit` guard against the fixed 158pt card clipping "123 456" at AX-XXL; (b) copy fired `Haptics.tap()` in addition to `ClipboardService.copy`'s own `Haptics.success` — a doubled haptic on every 2FA copy, the exact anti-pattern called out in the canonical protocol** | (a) `.font(.vaultCode(.title3, weight: .bold))` + `.lineLimit(1).minimumScaleFactor(0.7)` (matches `TOTPCodeView`'s exact guard); (b) removed the local `Haptics.tap()` call | high | fixed |
| TotpRingView (×2: live ring digit, Reduce-Motion fallback digit) | TotpRingView.swift | countdown affordance, not itself a secret | n/a (numeral only) | ring `accessibilityHidden(true)` — correct, the card's own a11y label covers it | tokens (`size`-relative circle geometry, fine); **raw `.font(.caption2.weight(.semibold))` ×2 — the identical countdown-ring digit in `ItemDetail/TOTPFieldRow.swift`'s `CountdownRing` already uses `.vaultType(.caption)`, so this was a cross-screen inconsistency, not just a token-gate hit** | live-tick / Reduce-Motion numeric-only fallback both covered | 1 defect (typography, ×2 sites) | `.font(.caption2.weight(.semibold))` → `.vaultType(.caption).fontWeight(.semibold)` (matches `CountdownRing` convention) | medium | fixed |
| attentionSection, AttentionCell | HomeScreen.swift, AttentionCell.swift | "Needs Attention (%d)" — reason-tagged rows, "Change" opens the fix | "Weak password"/"Check needed" calm; reason labels VI-present | **"Change" button ≈32pt tall (`Space.s1+2` vertical padding around subhead text) — under 44pt; whole row also has its own `onTapGesture` (opens detail instead), so a near-miss silently changes the action rather than dead-ending, but still a real hit-target defect** | tokens throughout; divider inset `Space.gutter + 40 + Space.s3` is a computed alignment (40 = favicon width), not a magic number | 0 items → section hidden; 1..4 items with divider-on-all-but-last verified; destructive(red)/warning(amber) tone split correct | 1 defect (hit target) | added `.frame(minHeight: Metric.hitMin).contentShape(Rectangle())` around the existing Button (visible capsule unchanged) | medium | fixed |
| recentlyUsedSection | HomeScreen.swift | "reach for it again" | "Recently Used" calm | rows reuse `itemRow` (`Metric.rowHeight`≥44) | tokens throughout | **gated to `allItems.count > 5`, matching the phase brief's stated design (small vaults don't need the duplicate strip) — verified correct, not a defect** | none | — | — | pass |
| favoritesSection, allItemsSection, itemRow | HomeScreen.swift | pinned-first sort, full list | copy n/a (data-driven titles) | rows ≥`Metric.rowHeight` | tokens throughout; `groupedCard` uses `.elevation(.level1)` not a stroke (card-diet, correct) | 0 favorites → section hidden; many items → pinned-then-sorted; sort toggle (updated/title) verified | none | — | — | pass |
| quickActionsGrid, QuickActionCard, QuickActionCardLabel | HomeScreen.swift, QuickActionCard.swift | secondary actions, correctly demoted below all credential content (2×2, half-width) | "Add Item"/"Generate Password"/"2FA Codes"/"Watchtower" — VI checked ("Tạo mật khẩu" etc.) all fit at SE in the half-width pill via `lineLimit(1)` + `minimumScaleFactor(0.85)` (above the 0.7 floor) — reflow (2×2, not 1×4) already correctly preferred over shrinking text | pills `minHeight: Metric.hitMin`; counts render as a small trailing badge, not a headline (correct per Q1) | `.padding(3)` on the count badge — not a `Space` token | 0-count badges hidden (`count > 0` guard); glass-vs-flat-fill guarded by `#if compiler`/`#available`/Reduce Transparency — correct pattern, matches tab bar | 1 low defect (magic padding number) | `.padding(3)` → `.padding(Space.s1)` (4pt, negligible visual change) | low | fixed |
| QuickActionCard white icon/text/count-badge fill, `GlyphBadgeSurface`'s `Color.black.opacity(0.18)` glass-well fallback | QuickActionCard.swift | n/a (decorative surface) | n/a | n/a | raw `.white`/`Color.black.opacity(0.18)` on the fixed decorative quick-action tints | n/a | **documented exemption** — `docs/design-dna-standard.md` explicitly lists "white text/icons on the fixed decorative quick-action tints" as exempt; the dark glass-well fallback is the same decorative-tile treatment, not a semantic content color | — | pass, exempt |
| HomeHeaderBar (wordmark + notification/add/settings cluster) | HomeHeaderBar.swift | control-layer glass bar, doesn't compete with content | a11y labels present ("Loox", "Notifications", "Add Item", "Settings") | bell/add/settings all `Metric.hitMin`×`Metric.hitMin` via explicit frame — correct | tokens throughout | 0/1-9/9+ notification counts all render ("9+" cap verified) | **badge text used raw `.font(.caption2.bold())` + `.foregroundStyle(.white)` on the destructive-colored circle — not covered by the quick-action-tint exemption (this is a semantic status badge, not a decorative tile), and the app already computes a WCAG-derived `onDestructive` token for exactly this case** | `.vaultType(.caption).fontWeight(.bold)` + `Color(rgb: env.theme.active.onDestructive)` | medium | fixed |
| HomeFolderPickerSheet, `tile()` helper | HomeHeaderBar.swift | pick/create/manage Spaces | "Create New Space"/"Manage Spaces & Members" calm | rows `.contentShape(.rect)` inside `List` — native row hit-target, correct | **`tile()`'s 30×30 icon tile used a raw `RoundedRectangle(cornerRadius: 8, ...)` — a magic number that happened to equal `FolderBadge`'s own `size * 0.28` proportional formula (used by the sibling folder rows in the SAME list) without expressing it as such** | All-Spaces / per-folder rows / create / manage all covered, item counts correct | 1 low defect (un-derived magic number, latent inconsistency risk if `FolderBadge`'s formula ever changes) | expressed as the same `size * 0.28` formula (documented size-relative-radius pattern) instead of the literal `8` | low | fixed |
| SearchScreen (root), SearchResultsList | SearchScreen.swift | "narrow the pool to the one you want" | "Search vault" prompt, "No results in %@" honest | `.searchable` native field; `NavigationLink`/`List` rows native ≥44pt | tokens throughout | zero-state / has-results / no-results-in-scope(offers "Search all Spaces" escape) / no-results-anywhere all walked; strictAnonymous correctly blocks the All-Spaces chip (`allSpacesSearchAllowed` gate, fail-closed — verified, not re-touched) | none (logic untouched, presentational-only review) | — | — | pass |
| ScopeChip | SearchScreen.swift | switch search scope (This Space / All Spaces / Shared with Me) | labels calm, VI-present ("Tất cả space", "Tìm trong tất cả space") | **no `.frame(minHeight: Metric.hitMin)` — its near-identical sibling `SearchFilterChip` (same screen family, same capsule pattern) already has this guard; inconsistent hit-target compliance between two chip components used back-to-back in the same feature** | tokens (`Space.s3`/`Space.s2` padding, `Capsule`) | only rendered when `> 1` scope available (correct — no redundant single-chip row) | 1 defect (hit target, cross-component inconsistency) | added `.frame(minHeight: Metric.hitMin)` (now matches `SearchFilterChip`) | medium | fixed |
| SearchZeroStateView, SearchFilterChip, recentsSection | SearchZeroStateView.swift | zero-state escape hatch: quick filters + recents, no dead "type something" screen | "Quick filters"/"Recently Used" calm; chip labels VI-checked ("Passkey", "Yếu") fit at SE | `SearchFilterChip` already `minHeight: Metric.hitMin` — pass | tokens throughout | scope-empty (sharedWithMe → recents hidden, correct: shared items carry no local `lastUsedAt`) / has-recents / no-recents(chips only, no stranded empty block) all covered | none | — | — | pass |
| TotpListScreen | TotpListScreen.swift | "all your codes, nothing else" (YAGNI: no search/sort) | "No 2FA codes" / helper line calm, VI-present | `SheetDismissButton("Done")` native; grid reuses `TotpCardView` (now fixed above) | tokens throughout | 0 → `ContentUnavailableView`; 1..many → adaptive grid | none | — | — | pass |
| ItemCard (legacy, `HomeSection.swift`) | HomeSection.swift | n/a — dead code, 0 call sites in the app or extension (`grep "ItemCard("` → no results); comment says "retained in case other feature screens reference it" | n/a | n/a | **raw `.font(.subheadline.weight(.medium))` / `.font(.caption)` — hit the typography audit gate even though unused** | n/a | 1 low defect (typography gate hit on dead code) | `.vaultType(.subhead).fontWeight(.medium)` / `.vaultType(.caption)` (compliance fix only; NOT deleting the dead struct — out of this phase's scope, a separate cleanup decision) | low | fixed |

## Deferred / documented, not fixed

- **`TotpCardView`'s `EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)`** — 12 = `Space.s3`,
  but 14 sits between `Space.s3`(12)/`Space.s4`(16) on the 4pt grid. Comment ties it to "matches DS
  TotpCard spec" (a shipped, spec'd card from the prior DNA pass). Changing it is a real pixel-diff
  to a settled, already-QA'd card for a token-purity gain only — left as documented, no fix (churn
  risk > benefit per phase brief's own Med×Low guidance).
- **`HomeScreen`'s TOTP-scroller shadow-bleed padding** (`.padding(.vertical, 2)/.padding(.horizontal,
  2)/.padding(.horizontal, -2)`) — already code-commented ("2pt padding so card shadows aren't
  clipped" / "Bleed 2pt … back so cards align with section header"). A deliberate shadow-clip
  compensation, not a spacing-scale candidate; not re-flagged.
- **`AttentionCell`/`HomeScreen` divider inset** (`Space.gutter + 40 + Space.s3`) — a computed
  alignment tied to the actual favicon width (40), not a magic padding number; not re-flagged.
- **`SearchOperators.swift`/`SpaceScope.swift`** — pure logic, no UI surface, out of the visual
  protocol's scope; not touched (per instructions, presentational fixes only in search-results logic).

## Audit-grep results (post-fix, owned files)

```
grep -nE '\.font\(\.|\.font\(\.system'                                  → 1 hit: TotpCardView.swift:59
                                                                            `.font(.vaultCode(.title3, weight: .bold))`
                                                                            — this IS the correct fix (vaultCode
                                                                            is the app's endorsed code/secret font),
                                                                            not a residual defect.
grep -nE 'cornerRadius\([0-9]|RoundedRectangle\(cornerRadius: *[0-9]'    → 0 hits
grep -nE '\.padding\([0-9]'                                              → 0 hits (QuickActionCard's `.padding(3)` fixed)
grep -nE '\.white|\.black|\.gray|\.red|\.primary|\.secondary'            → remaining hits are either
                                                                            (a) `themedForeground(.secondary/.primary)` /
                                                                            `theme.color(.secondary/.primary)` — semantic
                                                                            role parameters, not raw SwiftUI colors
                                                                            (false-positive class), or
                                                                            (b) the documented QuickActionCard
                                                                            decorative-tint exemption.
grep -nE 'Haptics\.'                                                     → 0 live call sites in owned files
                                                                            (TotpCardView's doubled `Haptics.tap()`
                                                                            removed; the only remaining match is a
                                                                            code comment explaining why).
grep -nE '\.frame\(width:|GeometryReader|minimumScaleFactor|lineLimit\(1\)' → all remaining hits are correct,
                                                                            intentional uses (fixed-size icon/avatar
                                                                            tiles, TOTP card width, scale-factor/
                                                                            line-limit guards) — no defects.
```

## Summary by severity

- **High (2, both fixed)**: `TotpCardView` raw font on the OTP code (should be `Font.vaultCode`,
  matching every other code display in the app) + missing AX-XXL clip guard; doubled copy haptic
  on every 2FA code copy.
- **Medium (6, all fixed)**: notification badge raw font/color (has a WCAG token available);
  `TotpRingView` countdown digit inconsistent with `ItemDetail`'s identical `CountdownRing`;
  identity-strip hit target; 3× section-header hit targets (View All / Sort / Space switcher);
  `AttentionCell` "Change" hit target; `ScopeChip` missing the hit-target guard its sibling
  `SearchFilterChip` already has.
- **Low (4, all fixed)**: quick-action count-badge magic padding; `HomeFolderPickerSheet` tile
  magic radius; dead-code `ItemCard` typography; stale "28pt" avatar doc comment.
- **Pass (11)**: HomeScreen root composition, pending-shares/approval rows, TOTP section
  gating, Recently-Used gating, Favorites/All-items, quick-actions reflow/scale-factor,
  QuickActionCard decorative exemption, SearchScreen/SearchResultsList states, SearchZeroState
  + filter chips + recents, TotpListScreen.
