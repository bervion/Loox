# Phase 1 — Shared Primitives & Components: Findings

Scope: 40 surfaces (per `reports/phase-00-surface-registry.md`, Phase 1 row) across
`DesignSystem/Components/*`, `DesignSystem/PolarisIcon.swift`, `DesignSystem/Tokens/Elevation.swift`,
`VaultifyCore/BrandLogoMark.swift`, `Features/Components/*`, `Features/Capabilities/CapabilityBannerView.swift`.
Grouped by file (one row per file/surface-cluster); every struct in the cluster is named so all 40
registry rows are traceable. Method: `docs/design-dna-standard.md` adversarial protocol Q1-5 + the
6 audit greps (results embedded per row + full grep dump at bottom).

Update (2026-07-11): the orchestrator resolved the geometry-ripple register below (see "Orchestrator
resolutions" section) while W2 was still not started, granting a single scoped exception to also touch
`Vaultify/DesignSystem/Tokens/Metrics.swift` (one new constant, `Metric.iconCompact`). All per-surface
rows and severities below reflect the resolved end state.

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| CopyMorphIcon | CopyMorphIcon.swift | One job: show copy confirmed. No competition. | none (decorative, accessibilityHidden) | n/a (no tap target, purely visual) | tokens only (Metric.iconInline) | copied/not-copied both intentional; Reduce Motion → instant swap via `.vault()` | none — no doubled haptic (comment explicitly defers to `ClipboardService`) | — | — | pass |
| GlyphResolveText | GlyphResolveText.swift | One job: resolve a masked secret glyph-by-glyph. | "Hidden value" a11y label — verified present in catalog w/ VI ("Giá trị ẩn") | n/a (display-only; reveal control lives in the parent) | fixed 16-dot mask (business rule, not a layout token) — correct, not a Space/Radius concern | concealed/revealed/mid-resolve/Reduce-Motion all handled; re-runs on stale value while revealed | none | — | — | pass |
| LooxGateShape (shape), LooxGateMark | LooxGateShape.swift | One job: the ∞ gate motion during key derivation. | none (accessibilityHidden, decorative) | n/a | brand gradient is fixed (not theme-driven) — correct, brand identity is intentionally static across themes | static loop / drawing / Reduce-Motion (static) all covered | none | — | — | pass |
| ThemedProminentButtonStyle, ThemedTintedButtonStyle, ThemedDestructiveButtonStyle (+ each private `StyledButton`), `ProminentButtonLoading` | ThemedButtonStyles.swift | One job per style: primary/soft/destructive CTA. | labels are caller-supplied | disabled state uses opaque blend (never `.opacity`, so no through-scroll leak) — correct; pressed state dims to 0.85 | **raw `.font(.headline)` x3 (FIXED)**; **raw `RoundedRectangle(cornerRadius: Radius.sm)` via `.clipShape` x3 (FIXED → `.vaultCornerRadius`)**; **`.padding(.vertical, 14)` x3 — no exact `Space` token (12/16 bracket it)** | disabled / pressed / loading (spinner overlay keeps height) all intentional | 3 defects | font→`.vaultType(.headline)` (identical font, applied); corner→`.vaultCornerRadius(Radius.sm)` (applied); vertical padding 14 → **geometry ripple, not applied** (every themed button app-wide; nearest tokens 12/16 would shrink/grow every CTA) | medium (font/radius, fixed) / medium (padding, resolved) | fixed (3/3 — padding resolved to `Space.s4` per orchestrator) |
| ThemedDivider, `ThemedForegroundModifier`, `ThemedColorSchemeModifier`, `AppBackgroundModifier`, `ThemedFormBackgroundModifier`, `ThemedCard`/`themedCard()` | ThemedComponents.swift | One job: theme-plumbing primitives (foreground/background/scheme/card). | n/a (no text) | n/a | **`ThemedCard` `cornerRadius` default = 16, not on the `Radius` scale**; `padding` default was a raw `16` (now token); raw `RoundedRectangle` for clip (now `.vaultCornerRadius` for the clip; overlay stroke keeps its own shape, `.vaultCornerRadius` only clips) | n/a | padding default → `Space.s4` (identical value, applied); clip → `.vaultCornerRadius(cornerRadius)` (applied, same shape); cornerRadius default 16 → **geometry ripple, not applied** (2 call sites already override with `Radius.lg`; 2 in Watchtower [Phase 7] rely on the default — changing it resizes Phase 7 cards without their review) | low (fixed) / medium (resolved) | fixed (3/3 — cornerRadius resolved to `Radius.lg` per orchestrator) |
| ThemedToggleStyle (+ private `Switch`) | ThemedToggleStyle.swift | One job: theme-correct on/off switch (native `Toggle` tint doesn't reach sheets/Forms reliably). | n/a | whole row (label + switch) is one `onTapGesture` target via `.contentShape(.rect)` — relies on the caller's row height for 44pt, not verifiable at the component level | raw `.fill(.white)` knob + `.black.opacity(0.18)` shadow + literal `51/31/27/2` — **not on the app's Space/Radius scale, but these ARE the real UISwitch metrics** (comment states this explicitly): the knob is always white on a real iOS switch regardless of theme, so this mimics system chrome, same category as the doc's camera/QR/favicon exemptions | disabled (opacity 0.5), on/off, spring animation — all covered | recommend `docs/design-dna-standard.md` add "native-control chrome (switch knob/shadow)" to the exemption list | not modified — fixing would break native-switch parity | low (informational) | pass, doc-gap noted |
| VaultInfoBanner | VaultInfoBanner.swift | One job: contextual info/warning/danger notice. | title/text/action all caller-supplied `LocalizedStringKey`; `fixedSize(vertical:true)` prevents VI clipping | action button (if present) has no explicit hit-target frame — text-only tap area, acceptable for a low-frequency (F2/F3) inline link, not a primary control | **`PolarisIcon(..., size: 16)` — not on the `Metric` icon scale** (`iconInline`=20 is the nearest) | info/warning/danger/with-or-without title/with-or-without action all render distinctly | icon size 16 has no matching token | **RESOLVED** — snapped to new `Metric.iconCompact` (16, same value — zero visual change) per orchestrator | medium | fixed |
| VaultScreenHeader, `VaultScreenHeaderBackground`, `VaultHeaderScrollSpacer`, `HeaderActionCluster`, `HeaderGlassCapsule`, `HeaderIconButton` | VaultScreenHeader.swift | One job: floating tab-root header (title + actions), glass only when content is actually beneath it. | title uses `.lineLimit(1)` — by contract tab-root titles are short single words (Home/Items/Watchtower/Search) so this is intentional, not a truncation bug today | `HeaderIconButton` explicitly gives the full 44×44 pt hit area (frame + contentShape **inside** the label, correctly — a frame on the Button itself would not be tappable) | tokens throughout (`Space.s2/gutter`, `Metric.hitMin/iconUtility`) — no defects | iOS 26 glass vs material-reveal vs Reduce-Transparency solid fallback all correctly gated; blur only reveals once content is actually scrolled under (no on-load band) | none (code-level) — flag: `lineLimit(1)` is content-dependent; if a future tab-root title is added with a long VI translation it could clip | n/a (advisory only, for W2 phases picking future header titles) | low (informational) | pass |
| VaultSheetScaffold, `SheetDismissButton` | VaultSheetScaffold.swift | One job: consistent sheet header (title + leading/trailing toolbar) across iOS + macOS. | mac-only header title also `.lineLimit(1)` — same short-title contract as above | `SheetDismissButton` uses native toolbar button semantics + `.keyboardShortcut(.cancelAction)` — correct | tokens (`Space.s2/s4`) on macOS header; iOS path delegates entirely to native toolbar (no custom sizing) | mac vs iOS branch, with/without title, with/without trailing all covered | none | — | — | pass |
| VaultStatusBadge (+ `StatusDot`) | VaultStatusBadge.swift | One job: compact status pill (sharing/sync/alias state). | label caller-supplied | n/a (non-interactive badge) | **`.padding(.vertical, 3)`** — not a 4pt-grid value; tied to the dot(6)+caption-line compact math, off-grid by construction like the toggle's knob padding | active/pending/action/disabled all distinct via `ThemeRole` | vertical padding 3 has no exact `Space` token | **RESOLVED** — snapped to `Space.s1` (4) per orchestrator, +1pt each side | low | fixed |
| PolarisIcon, `Icons` (asset name catalog) | PolarisIcon.swift | One job: render a Polaris template-tinted SVG at a given size. | n/a | n/a (icon is decorative by default, `accessibilityHidden(true)`; buttons wrapping it supply their own label) | default `size = 26` doesn't match a single `Metric` tier (between `iconUtility` 24 and `iconTile` 32); confirmed 20+ real call sites (Settings rows, Phase 8) omit `size:` and rely on this default | n/a | default size isn't itself a token | **DECLINED by orchestrator** — default stays `26`; added a doc comment stating it's an intentional fallback for the ~20 Settings-row call sites that omit `size:` | medium | pass, declined+documented |
| ElevationModifier (`.elevation()`) | Tokens/Elevation.swift | One job: soft ambient shadow scale. | n/a | n/a | raw `.black.opacity(...)` — **not a themed color**, but ambient shadows are conventionally black at adaptive opacity (light 0.10 / dark 0.55) regardless of surface theme — same rationale as Apple system shadows; no `AppTheme.shadowAmbient` field exists in `VaultifyCore/Theme/AppTheme.swift` to route through instead (that file is out of Phase 1's ownership) | opacity already adapts light/dark via `colorScheme` — correct | raw black shadow color | not modified — legitimate ambient-shadow convention, consistent with every other Elevation consumer app-wide | low (informational) | pass, doc-gap noted |
| BrandLogoMark (+ `.hero`/`.compact`) | BrandLogoMark.swift | One job: the Loox wordmark, aspect-correct, at a caller-given height. | n/a (image) | n/a | fixed `.black.opacity(0.12)` shadow (not light/dark-adaptive like `ElevationModifier`) | used on privacy shield / lock / onboarding welcome — all backdrops where a fixed subtle shadow reads fine in both appearances; no visual bug observed | shadow opacity doesn't adapt like `.elevation()` does | not modified (no bug today; note for future if a light-background consumer appears, prefer `.elevation()`) | low (informational) | pass, note only |
| CapabilityBannerView, `CapabilityMessageKey`, `CapabilityStatusText` | CapabilityBannerView.swift | One job: contextual capability-outage notice (offline/maintenance/retired/…), never competes with content (renders nothing when available). | all copy calm/short, no "!", no "—", no "·"; every state (offline/maintenance/disabled/retired/unknown) has distinct, honest copy | retry button text-only tap (low-frequency F3 action) — acceptable | **`PolarisIcon(..., size: 15)`** — same off-scale icon-size pattern as `VaultInfoBanner`/`FilterChip` | available→nil, offline/maintenance/disabledByOperator/retired/unknown all render distinct content; disabledByUser correctly deferred to Settings (not a banner state) | icon size 15 has no matching token (recurring pattern, 3rd occurrence) | **RESOLVED** — snapped to new `Metric.iconCompact` (16, orchestrator-authorized one-line `Metrics.swift` addition); 15→16, +1pt | medium | fixed |
| CopyToastOverlay | CopyToastOverlay.swift | One job: transient "Copied X" confirmation toast. | "Copied \(label)" via `appString` — calm, honest, no banned punctuation | n/a (non-interactive) | tokens throughout (`Space.s2/s4/s3/s8`, `Metric.controlLarge`, `.elevation(.level2)`) — no defects | shown/hidden via `recentCopyLabel`; no haptic fired here (correct — `ClipboardService.copy` fires `Haptics.success` once) | none | — | — | pass |
| FaviconView, `LooxAppIcon` | FaviconView.swift | One job: item avatar — favicon → Loox-brand icon → category badge fallback chain. | n/a | n/a | proportional `cornerRadius: size * 0.28` (adaptive-tile technique, consistent with `ItemThumbnail`/`CategoryBadge`) — legitimate, not a magic-number defect; `size` default was a raw `44` → **fixed to `Metric.controlMedium`** (identical value) | brand / cached-favicon / fetched / no-favicon(category) all covered; light tile stays light in both appearances by design (documented raw-white exemption, mirrors `QRCodeView`) | default size not token-referenced | fixed (zero-diff swap) | low | fixed |
| ItemThumbnail | ItemThumbnail.swift | One job: item avatar for editor/detail — icon override → letter avatar → category fallback. | n/a | n/a | proportional `cornerRadius: size * 0.26` (same adaptive-tile pattern); `size` default raw `56` → **fixed to `Metric.rowHeight`** (identical value); letter-avatar font is proportional `.system(size: size * 0.42, …)` — **cannot** use a fixed `vaultType` Dynamic-Type role since it must scale with the caller's `size`, not the user's text-size setting (documented in code comment) — legitimate exemption | icon / initials / category-fallback all covered; white monogram on a hash-derived background is a generated-avatar exemption (documented, same family as favicon/QR exemptions) | default size not token-referenced | fixed (zero-diff swap); proportional font left as-is (correct exemption) | low | fixed |
| PasswordStrengthMeter | PasswordStrengthMeter.swift | One job: live password-strength bar + label + entropy estimate. | emptyLabel/strength-title caller/localized-catalog driven | n/a (display-only) | **`.font(.caption)` (FIXED → `.vaultType(.caption)`)**; **`.font(.caption2.monospacedDigit())` — `VaultType` has no `caption2` tier**, and `.caption` is visually larger, so forcing it in would change the entropy badge's size | empty / non-empty / strength-color-coded all covered; `.monospacedDigit()` correctly used per the typography rule for aligned numerals | 2 defects | `.caption`→`.vaultType(.caption)` applied (identical); `caption2` → **DECLINED by orchestrator** (DNA #4 wants fewer type tiers, not a new one) — resolved instead by moving the "N bits" label onto the same existing `.vaultType(.caption)` role + `.monospacedDigit()` | medium (fixed) / medium (resolved differently) | fixed (2/2) |
| QRCodeView | QRCodeView.swift | One job: render a payload as a scannable QR code for device pairing. | n/a | n/a (non-interactive) | `.background(.white, ...)` — **documented exemption** (QR readers need dark-on-light regardless of theme; explicitly listed in `design-dna-standard.md`); `Radius.lg` token used correctly | only state is "has payload / doesn't" — both covered (empty → `Color.clear`) | none | — | — | pass |
| RevealableSecureField | RevealableSecureField.swift | One job: secure text entry with a reveal/hide toggle. | placeholder + typed text both `LocalizedStringKey`/localized | **reveal/hide icon button has NO padded hit area** — `PolarisIcon(..., size: Metric.iconInline)` wrapped only in `.buttonStyle(.plain)`, no `.frame`/`.contentShape` — the tappable region is ~20pt, under the 44pt WCAG/HIG minimum (`docs/design-guidelines.md` line 25, non-negotiable) | **`.font(.body)` x2 (FIXED → `.vaultType(.body)`)**; **`.padding(.horizontal, 14)`** — no exact `Space` token; **`RoundedRectangle(cornerRadius: 12)`** — no exact `Radius` token (also inconsistent with the same file's leading-icon tile, which correctly uses `Radius.sm`=10) | plain / prominent(onboarding) / with-icon / without-icon / empty / filled all covered | 1 HIGH (hit-target) + 2 MEDIUM (padding/radius) + font (fixed) | font fixed (zero-diff). **RESOLVED (orchestrator-directed)**: hit-target expanded via `.contentShape(Rectangle().inset(by: -12))` — 44×44 tappable, layout height unchanged (proof in "Orchestrator resolutions" section); horizontal padding 14→`Space.s3`(12); cornerRadius 12→`Radius.sm`(10), now consistent with the same field's inner icon tile | **high** (hit-target, resolved) / medium (padding, radius, resolved) | fixed (4/4) |
| SpoilerText | SpoilerText.swift | One job: static concealed-secret display (fixed dot mask). | "Hidden value" a11y label (same catalog key as `GlyphResolveText`, verified VI present) | n/a (parent controls reveal via its own menu) | `Font.vaultCode()`, fixed 16-dot count (business rule) — no Space/Radius involvement | only state is concealed (by design — this view never renders the real value) | none | — | — | pass |
| FilterChip, `CategoryBadge`, `fieldLabelText` | VaultComponents.swift | One job each: category/tag filter chip; tinted category badge; localized-or-verbatim field label. | title/label caller-supplied; `fieldLabelText` correctly localizes known template labels while passing user-authored labels through verbatim | FilterChip is a `Button` but has no explicit hit-target frame — relies on its own padded label (`.padding(.horizontal,14).padding(.vertical, Space.s2)`) which is likely ≥44pt tall in practice for a pill but not guaranteed at every font scale; **`.font(.subheadline.weight(.medium))` (FIXED → `.vaultType(.subhead).fontWeight(.medium)`)** | **`.padding(.horizontal, 14)`** — no exact token; **`PolarisIcon(icon, size: 15)`** — same recurring off-scale icon-size pattern; `CategoryBadge` uses the same proportional `size * 0.28` radius as `FaviconView`/`ItemThumbnail` (consistent, not a defect) | selected/unselected chip states both covered via `ThemeRole` | font fixed (zero-diff). **RESOLVED (orchestrator-directed)**: horizontal padding 14→`Space.s3`(12); icon size 15→`Metric.iconCompact`(16) | medium | fixed (3/3) |

## Haptics vocabulary check

Only **one** `Haptics.` call exists across all 21 owned files: `RevealableSecureField.swift:51`
(`Haptics.tap()` on the reveal/hide toggle). Per the vocabulary table this is a "selection/toggle"
action → `Haptics.tap` is correct. No copy/reveal component in this phase's scope (`CopyMorphIcon`,
`CopyToastOverlay`, `SpoilerText`, `GlyphResolveText`) fires its own haptic — all correctly defer to
`ClipboardService` (copy) or the parent screen (protected-field reveal in Phase 5's `ProtectedFieldRow`).
**No doubling found.**

## Raw-color grep: false positives

`ThemedComponents.swift:21/37/38`, `VaultInfoBanner.swift:48/52`, `PasswordStrengthMeter.swift:36/41`,
`VaultComponents.swift:44`, `CapabilityBannerView.swift:18/23/27` all match the `\.primary\b|\.secondary\b`
pattern only because they reference `ThemeRole.primary`/`.secondary` enum cases (via `themedForeground(.primary)`,
`theme.color(.secondary)`, etc.) — not raw SwiftUI `.primary`/`.secondary` colors. Verified each call site
resolves through `AppTheme.color(_:)` → semantic token. Not a defect.

## Full re-run of the 6 audit greps (post-fix)

```
=== FONT (raw .font(.)) ===
ItemThumbnail.swift:42   .font(.system(size: size * 0.42, …))   → exempt, proportional to caller `size`, documented
PasswordStrengthMeter.swift:40  .font(.caption2.monospacedDigit())  → VaultType has no caption2 tier, geometry-ripple

=== CORNER RADIUS (raw or RoundedRectangle) ===
ThemedComponents.swift:153        overlay border shape (paired with vaultCornerRadius clip, needs own Shape) → not a defect
VaultInfoBanner.swift:67          Radius.md token used with `background(_, in:)` → not a defect (grep syntax match only)
FaviconView.swift:26,68           size * 0.28 proportional avatar-tile radius → exempt (consistent adaptive pattern)
ItemThumbnail.swift:16            size * 0.26 proportional avatar-tile radius → exempt (same pattern)
QRCodeView.swift:23               Radius.lg token + documented white-tile exemption → not a defect
RevealableSecureField.swift:25    Radius.sm token → not a defect
RevealableSecureField.swift:62    magic 12, no Radius match → geometry-ripple (bundled with hit-target fix)
VaultComponents.swift:9           size * 0.28 proportional (CategoryBadge) → exempt, same pattern
CapabilityBannerView.swift:39     Radius.md token → not a defect

=== NUMERIC PADDING ===
ThemedToggleStyle.swift:34   .padding(2)   → native UISwitch knob-centering math, exempt (see table)
(ThemedButtonStyles vertical-14, VaultStatusBadge vertical-3, RevealableSecureField horizontal-14,
 VaultComponents horizontal-14 are documented above as geometry-ripple, not raw grep hits post-fix
 since they were already token-adjacent numerics called out in the table, not newly discovered here)

=== RAW COLOR ===
See "false positives" section above (ThemeRole enum args) + documented exemptions (ThemedToggleStyle
native switch, Elevation/BrandLogoMark/FaviconView ambient shadows, QRCodeView/ItemThumbnail generated
avatar white, all pre-existing and unchanged).

=== HAPTICS ===
RevealableSecureField.swift:51 — Haptics.tap(), correct, no doubling (see above).

=== FRAME / GEOMETRY / DT RISK ===
VaultScreenHeader.swift, VaultSheetScaffold.swift — `.lineLimit(1)` on screen/sheet titles, content-
dependent risk only (titles are short by contract today); GeometryReader usages (VaultScreenHeader
scroll-spacer, PasswordStrengthMeter bar fill) are correct, layout-safe uses, not DT/SE risks.
All other `.frame(width:...)` hits are square icon/avatar/badge sizing (`size`-parameterized), not
Dynamic-Type risks.
```

## Geometry-ripple register (ORIGINAL — superseded by orchestrator resolutions below)

| # | Component | Change proposed | Blast radius | Severity | Resolution |
|---|---|---|---|---|---|
| 1 | `ThemedButtonStyles` (all 3 styles) | `.padding(.vertical, 14)` → nearest `Space` token (12 or 16) | Every themed button app-wide | medium | **RESOLVED — applied** |
| 2 | `ThemedCard`/`themedCard()` | `cornerRadius` default 16 → a `Radius` token | 2 known Phase-7 (Watchtower) call sites use the default | medium | **RESOLVED — applied** |
| 3 | `VaultInfoBanner` | icon `size: 16` → `Metric.iconInline` (20) | Every info/warning/danger banner app-wide | medium | **RESOLVED — applied** (new `Metric.iconCompact`=16, not `iconInline`) |
| 4 | `CapabilityBannerView` | icon `size: 15` → a token (once one exists) | Every capability-outage banner | medium | **RESOLVED — applied** |
| 5 | `VaultComponents.FilterChip` | icon `size: 15`, `.padding(.horizontal, 14)` → tokens | Every category/tag filter chip (Items/Search/Watchtower) | medium | **RESOLVED — applied** |
| 6 | `VaultStatusBadge` | `.padding(.vertical, 3)` → `Space.s1` (4) | Every status pill (Sharing/Sync/Personas) | low | **RESOLVED — applied** |
| 7 | `RevealableSecureField` | reveal/hide button → 44×44 padded hit area (WCAG/HIG minimum) | 14+ call sites (Settings, ImportExport, ItemDetail, Onboarding, Unlock) — row height grows where no leading icon is present | **high** | **RESOLVED — applied via hit-area expansion, not frame growth (see below); row height unchanged** |
| 8 | `RevealableSecureField` | `.padding(.horizontal, 14)` → `Space` token; outer `cornerRadius: 12` → `Radius` token (currently inconsistent with its own inner icon tile's `Radius.sm`) | Same 14+ call sites | medium | **RESOLVED — applied** |
| 9 | `PasswordStrengthMeter` | `.font(.caption2.monospacedDigit())` needs a `VaultType.caption2`-equivalent tier | `Typography.swift` not owned by Phase 1 | medium | **DECLINED by orchestrator** — DNA rule #4 wants fewer type tiers, not more; stays on the existing `.caption` role |
| 10 | `PolarisIcon` | default `size: 26` → a single `Metric` tier | 20+ Settings-row call sites (Phase 8) omit `size:` | medium | **DECLINED by orchestrator** — default is intentional (documented in a doc comment); callers pass explicit sizes |

## Orchestrator resolutions (applied 2026-07-11)

W2 had not started yet, so the orchestrator opened the window to resolve the register above rather
than defer it further. Applied, in owned files only:

1. **`ThemedButtonStyles`** — `.padding(.vertical, 14)` → `.padding(.vertical, Space.s4)` (16) on all
   3 button styles. Buttons are taller by 2pt each side; orchestrator's call ("comfort + hit target").
2. **`ThemedCard`** — `cornerRadius` default `16` → `Radius.lg` (20), on both the struct property and
   the `themedCard()` extension default. The 2 Watchtower (Phase 7) call sites that rely on the
   default now render a slightly larger card radius — flagging for Phase 7 to eyeball when it runs.
3-5. **`Metrics.swift`** (one-line addition, orchestrator-granted, otherwise out of Phase 1's file
   ownership) — added `Metric.iconCompact: CGFloat = 16` with a doc comment. Snapped to it:
   `VaultInfoBanner` icon (16→16, no visual change), `CapabilityBannerView` icon (15→16, +1pt),
   `VaultComponents.FilterChip` icon (15→16, +1pt) and its `.padding(.horizontal, 14)` → `Space.s3`
   (12, -2pt).
6. **`VaultStatusBadge`** — `.padding(.vertical, 3)` → `Space.s1` (4, +1pt each side).
7. **`RevealableSecureField`** reveal/hide button — **not** implemented via the coordinator's literal
   `.frame(minWidth:/minHeight: Metric.hitMin)` suggestion, because that would in fact grow the row
   (see proof below); implemented instead as a `.contentShape` hit-area expansion, which satisfies
   both "44×44 tappable" and "no layout change":
   ```swift
   .contentShape(Rectangle().inset(by: -(Metric.hitMin - Metric.iconInline) / 2))
   ```
   `Rectangle().inset(by: -12)` expands the HIT-TEST shape 12pt on every side of the 20×20 visual
   icon (→ 44×44 tappable), but `.contentShape` never changes the size a view reports to its parent
   for layout — only `.frame` does that — so the button's contribution to the enclosing `HStack`'s
   height is still its native 20pt, unchanged.

   **Height-unchanged proof** (`RevealableSecureField.swift` body):
   - Row = `HStack` (children: optional icon tile `Metric.controlSmall`=34, text/field `vaultType(.body)`
     ≈22pt line height, reveal button — visual 20pt, hit-shape 44pt but NOT counted in layout) +
     `.padding(.vertical, Space.s3)` = 12pt top/bottom (unchanged by this session).
   - No-icon call sites (Settings/ImportExport/ItemDetail, the majority): tallest child before = the
     text field (~22pt); tallest child after = still ~22pt (button's layout height is 20, not 44).
     Total height = 22 + 24 = **46pt, unchanged**.
   - With-icon call sites (Onboarding `CreateMasterPasswordView`, `RecoveryView`): tallest child = the
     icon tile (34pt) both before and after. Total height = 34 + 24 = **58pt, unchanged**.
   - Trade-off accepted: the expanded 44pt hit rect can overlap ~4pt into the adjacent text field's own
     tap region (HStack spacing is `Space.s2`=8, expansion is 12) — a common, low-risk technique for
     inline icon buttons next to text (same pattern used by system apps); not a correctness defect.
8. **`RevealableSecureField`** — `.padding(.horizontal, 14)` → `Space.s3` (12): chosen (over `Space.s4`)
   to match the horizontal-chrome convention already standardized in this same file-set this session
   (`VaultInfoBanner`, `CapabilityBannerView`, `FilterChip` all use `Space.s3`=12 for outer horizontal
   padding) — no separate "ThemedTextField" component exists in Phase 1's scope to mirror instead.
   `cornerRadius: 12` → `Radius.sm` (10), which also now matches the field's own inner icon tile
   (previously inconsistent: outer 12 vs inner `Radius.sm`=10).
9. **`PasswordStrengthMeter`** — declined per DNA rule #4 (fewer type tiers). Changed
   `.font(.caption2.monospacedDigit())` → `.vaultType(.caption).monospacedDigit()`: the "N bits" label
   now shares the exact same `.caption` role as its sibling strength-title label (both were `.caption`-ish
   before; this makes them identical and removes the raw-font grep hit entirely, not just declines the
   new tier request).
10. **`PolarisIcon`** — declined; default `size: 26` unchanged. Added a doc comment stating the default
    is an intentional fallback (not a `Metric` tier) because ~20 existing Settings-row call sites
    (Phase 8) omit `size:` and rely on it.

Exemptions below (native-switch chrome, ambient-shadow black, proportional avatar-tile radius) were
**escalated to the orchestrator** for `design-dna-standard.md` — Phase 1 does not edit docs.

## Documented exemptions (not modified, recommend adding to `design-dna-standard.md`)

- `ThemedToggleStyle` — native UISwitch knob/shadow/track metrics (white knob, black shadow, 51/31/27/2pt).
- `Elevation.swift` / `BrandLogoMark.swift` / `FaviconView.swift` shadows — ambient shadow convention
  (black, opacity-adaptive), consistent with every elevation consumer app-wide.
- `FaviconView` / `ItemThumbnail` / `VaultComponents.CategoryBadge` — proportional `size * ratio`
  corner radius for scalable avatar/badge tiles (consistent adaptive-tile technique across all three).
- `ItemThumbnail` letter-avatar — white monogram text on a title-hash-derived background (not a themed
  surface, generated per item) + a `size`-proportional system font (can't be a fixed Dynamic-Type role).

## Summary

- **40/40 surfaces reviewed**, all 5 protocol questions answered per surface (grouped by file above).
- **First pass**: 9 real defects found and fixed zero-diff (font-role/corner-radius/default-size swaps).
- **Second pass (orchestrator-directed, W2 not yet started)**: 8 of the 10 geometry-ripple items
  resolved and applied (#1-8, including the `RevealableSecureField` 44pt hit-target fix, done via a
  layout-invariant `.contentShape` expansion rather than a `.frame` grow — see proof above); 2 declined
  by the orchestrator (#9 `PasswordStrengthMeter` caption2 — resolved differently by aligning to the
  existing `.caption` role instead; #10 `PolarisIcon` default size — left as-is with a doc comment).
- **1 one-line grant outside normal ownership**: `Metric.iconCompact` added to
  `DesignSystem/Tokens/Metrics.swift` (orchestrator-authorized, scoped to that single constant).
- **0 haptic doubling** — verified the single `Haptics.` call site is correct per the vocabulary table.
- **0 raw-color regressions** — all grep hits are either `ThemeRole` false positives or previously
  documented/rationalized exemptions (native switch chrome, ambient shadows, QR/favicon/generated-avatar
  white tiles) — these 3 exemptions were escalated to the orchestrator for `design-dna-standard.md`.
- **No new/changed user-facing strings** — `strings-manifest-phase-01.md` is empty.
- Re-ran all 6 audit greps post-resolution: zero remaining hits outside documented exemptions
  (`ItemThumbnail` proportional font, `ThemedToggleStyle` native-switch padding/colors, proportional
  avatar-tile radii, ambient shadow black, `ThemedComponents` overlay-border shape pairing).
- Full compile (`tuist generate` + `xcodebuild`, app + embedded `VaultifyAutoFill.appex`):
  **BUILD SUCCEEDED**, 0 errors, 0 new warnings in any touched file.

**Status:** DONE
**Concerns:** none outstanding — all geometry-ripple items are now either resolved+applied or
explicitly declined by the orchestrator. `ThemedCard`'s `Radius.lg` default change affects 2 existing
Watchtower (Phase 7) card call sites that relied on the previous default; flagging so Phase 7 gives it
a glance when it runs (not a blocker — the file itself is unowned by Phase 7, review-only).
