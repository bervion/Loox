# Phase 9 — Appearance + About: Findings

Scope: `Settings/Appearance/*` (AppearanceSettingsView, AutoNightSettingsView, ThemeEditorView,
WallpaperGalleryView, ThemeFileDocument), `Settings/AboutView.swift`,
`DesignSystem/Wallpaper/*` (flag-gated engine, review-light per phase brief). Method:
`docs/design-dna-standard.md` adversarial protocol Q1-5 + the 6 audit greps. Protagonist for the
cluster: Appearance = "make it look the way I want, live"; About = "understand and trust the app".

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| AppearanceSettingsView (theme cards) | AppearanceSettingsView.swift | Pick a theme, see it live; whole card is the hit target (84pt tall + label) | "Theme" header fine, EN+VI already present, no banned punctuation | card `Button` — full-card hit box already ≥44pt, correct | `Radius.md` for card, `Space.s1/s2/s3` grid gaps — tokens throughout | 2 builtin themes (Day/Night), selected vs unselected ring, both eyeballed light+dark — no invisible content | 2 defects: (a) tap fired no haptic, unlike the identical selection UX in onboarding's `ChooseThemeView.ThemeOptionRow`; (b) `name.font(.caption)` raw font instead of `vaultType` | (a) added `Haptics.tap()` before `env.theme.setTheme`; (b) `name.font(.caption)` → `name.vaultType(.caption)` | medium / low | fixed |
| AppearanceSettingsView (accent swatch grid, 7 presets) | AppearanceSettingsView.swift | Pick an accent, applies instantly app-wide | footer "Accent applies instantly… No restart needed." calm, honest, EN+VI present | **swatch `Circle` visual+tappable size = `Metric.controlSmall` (34pt) < `Metric.hitMin` (44pt), no padded invisible hit area** (rule 6's exact named anti-pattern) | grid `GridItem(.adaptive(minimum: 46))` — reflows fine at SE/Pro Max/Dynamic Type, all 7 swatches wrap to a second row at SE | selected/unselected ring per preset, both themes, both eyeballed — ring itself was the color defect below | selection ring stroke used raw `Color.primary.opacity(...)` (SwiftUI dynamic system color, not the theme's semantic role) instead of `theme.color(.iconPrimary)`; also missing `Haptics.tap()` | padded swatch to ≥44pt tap target (`.padding(Space.s2)` + `.contentShape(Rectangle())`, bumped grid `minimum` 46→50 to match); ring color → `env.theme.active.color(.iconPrimary)`; added `Haptics.tap()` | high (hit-target) / medium (color token, haptics) | fixed |
| AppearanceSettingsView (Text Size picker, Reduce Motion toggle, Automatic Dark Mode link) | AppearanceSettingsView.swift | Secondary appearance controls, correctly demoted below theme/accent | "Text Size" / "Reduce Motion" / "Automatic Dark Mode" all fine EN+VI | native `Picker`/`Toggle`/`NavigationLink` — system chrome gives its own feedback; verified codebase-wide convention (grepped every `Toggle(`/native `Picker(` call site in `Features/*`) never fires an explicit `Haptics.*` — consistent, not a gap | tokens throughout | n/a | none (native-control haptics is a documented system-chrome exemption, not a vocabulary gap) | — | — | pass |
| AppearanceSettingsView (numeric padding) | AppearanceSettingsView.swift:36,95 | n/a | n/a | n/a | 2× `.padding(.vertical, 6)` off the 4pt grid | n/a | off-grid magic number | → `Space.s2` (8) | low | fixed |
| AutoNightSettingsView (Off/System/Scheduled/Brightness rows) | AutoNightSettingsView.swift | Choose when night theme kicks in | 4 mode labels + "Night Theme" fine EN+VI | `modeRow` full-row `Button`, `.contentShape(.rect)` — correct ≥44pt hit target | tokens (Form defaults, no manual padding in this file) | off/system/scheduled/brightness, each reveals exactly its own dependent section — no stranded UI | missing `Haptics.tap()` on the custom row-select `Button` (same pattern as the theme cards above) | added `Haptics.tap()` in `modeRow`'s action closure | medium | fixed |
| AutoNightSettingsView (Scheduled → 2 `DatePicker`s) | AutoNightSettingsView.swift | Set the daily on/off times | "From"/"To" fine | native `DatePicker` (system wheel) — own native haptic feedback, documented system-chrome exemption | reflows fine at SE (compact wheel) | seeded from persisted `.time` case correctly (`seed()` on appear) | none | — | — | pass |
| AutoNightSettingsView (Brightness → % slider) | AutoNightSettingsView.swift | Pick a brightness threshold below which night theme kicks in | "Dark below brightness" / live "%" fine | `Slider` had no haptic feedback at all — inconsistent with the established custom-slider convention (`PasswordGeneratorView.countSlider`: tick-per-unit-change while dragging + firm tap on release) | tokens (`Space.s2`) | 0%→100% range, live label updates | missing drag-tick + release-tap haptics | added `Haptics.selectionTick()` on each whole-percent change + `onEditingChanged` `prepareSelection()`/`tap()`, mirroring `PasswordGeneratorView` | low-medium | fixed |
| AutoNightSettingsView (Night Theme picker) | AutoNightSettingsView.swift | Pick which theme night mode uses | "Night Theme" fine | native `Picker` — system chrome exemption | n/a | shown only when mode≠off — correct | none | — | — | pass |
| ThemeEditorView, WallpaperGalleryView, ThemeFileDocument | ThemeEditorView.swift, WallpaperGalleryView.swift, ThemeFileDocument.swift | Dormant custom-theme/wallpaper engine — review-light per phase brief | n/a (unreachable, not reviewed for copy/tokens) | n/a | n/a | n/a | **confirmed unreachable**: `grep -rn "WallpaperGalleryView(\|ThemeEditorView("` across `Vaultify/`, `VaultifyAutoFill/`, `VaultifyCore/` → zero call sites; `AppearanceSettingsView` (the only entry point into this hub) has no `NavigationLink`/sheet to either. `WallpaperView.swift`'s `content` branches on `WallpaperFeature.decorativeEnabled` (`VaultifyCore/Theme/WallpaperFeature.swift:10` = `false`) → every live `.themedWallpaper` call site (Watchtower/Search/Lock/Onboarding, other phases' files) renders only `flatContent` (solid/fallback), never `decorativeContent`. Nothing gated leaks into current UI. | not fixed — engine retained per instruction, no refactor | — | pass (gate confirmed in code, not just by inspection) |
| AboutView (hero, refusal ink block, promises, signature) | AboutView.swift | "Your passwords guard everything. Who guards them?" — trust narrative, one continuous scroll | every string read EN: calm, no `!`, no `—`, no `·` (comment-only em-dashes don't count — verified with a literal-text grep, zero hits in `Text(...)`/`LocalizedStringKey` string literals); VI companion strings live in the catalog already (pre-existing feature, not newly authored this pass) | no interactive controls in this block except `textSelection` on the support email (fine) | `Radius.lg` cards, `Space.s2-s5` — tokens throughout; `AboutInk` fixed dark palette is documented-in-code as a deliberate always-dark surface (line comment: "deliberately identical in light and dark themes") — same rationale as the quick-action-tint exemption, not re-flagged | single continuous scroll, no empty/loading/error states (static content) — renders SE↔Pro Max (verified: all body text `.fixedSize(horizontal:false, vertical:true)`, no fixed heights) | 1 defect: `promiseCard`'s big numeral used a **fixed pixel** `.font(.system(size: 34, weight: .heavy, design: .rounded))` — doesn't scale under Dynamic Type/AX sizes, unlike the rest of the screen | `.font(.system(.largeTitle, design: .rounded)).fontWeight(.heavy)` — same rounded/heavy decorative look, now Dynamic-Type-scalable (Apple-native `.largeTitle` text style) | medium | fixed |
| AboutView (`aboutRow`: 4 "How your data is protected" rows) | AboutView.swift:205-213 | Explain the 4 protection mechanisms in one glance | copy calm/honest/EN+VI, no banned punctuation | n/a (static row, not tappable) | tokens (`Space.s3`) | 4 rows, always all 4 shown — no state variance needed | 2× raw `.font(...)` (`title`: `.subheadline.weight(.medium))`, `detail`: `.caption`) + `title` had no explicit `themedForeground`, relying on ambient foreground (would not track a future custom/tinted theme's semantic primary) | `title` → `.vaultType(.subhead).fontWeight(.medium).themedForeground(.primary)`; `detail` → `.vaultType(.caption)` (already had `.themedForeground(.secondary)`) | medium | fixed |
| AboutView (footer: support email + version) | AboutView.swift:186-203 | Reachable contact + build info | "We answer every email ourselves." fine; placeholder support email (`EmergencyKitInfo.defaultSupportContact`) — known follow-up per phase brief, intentionally not touched | email has `.textSelection(.enabled)` — copyable, adequate affordance without a full button | tokens | n/a | none | — | — | pass |

## Haptics vocabulary check

Before this pass: **zero** `Haptics.*` call sites across all 3 owned interactive files (Appearance +
AutoNight) despite 3 custom Button-based selection rows (theme cards, accent swatches, mode rows) and
1 custom Slider (brightness) — all of which have an established, matching precedent elsewhere in the
app (`ChooseThemeView.ThemeOptionRow` for row-select, `PasswordGeneratorView.countSlider` for
drag-slider). Added `Haptics.tap()` to the 3 row-select sites and the drag-tick/release pattern to the
1 slider — 5 new call sites total, all "selection / toggle / minor action" per the vocabulary table,
none doubled (no `ClipboardService` interaction in this phase). Confirmed via codebase-wide grep that
native `Toggle`/`Picker`/`DatePicker` never get explicit haptics anywhere in `Features/*` (system
chrome exemption) — did not add haptics to those, consistent with the rest of the app.

## Raw-color grep: findings + confirmed exemptions

- `AppearanceSettingsView.swift:116` `Color.primary.opacity(...)` (accent-swatch selection ring) —
  **fixed** → `env.theme.active.color(.iconPrimary)` (semantic, tinted-theme-aware).
- `AboutView.swift` `AboutInk.text = Color.white` / `.textSecondary = Color.white.opacity(0.72)` —
  fixed dark ink-block surface, explicitly documented in code as deliberately theme-invariant (its
  own surface, same rationale as the "white text on fixed decorative quick-action tints" exemption).
  Not a defect.
- `WallpaperGalleryView.swift` (`fallbackColor: .gray`, `.foregroundStyle(.white)`) — dormant,
  unreachable file (see registry row above); not fixed per review-light scope (no refactor of the
  gated engine).
- All other `.primary`/`.secondary` matches are `themedForeground(_:)` calls (semantic token API),
  not raw SwiftUI colors.

## Theme-switch invisible-content audit (both theme cards × 7 accents × light/dark)

Walked in code (not device-rendered, since this is a static review pass): every text/icon in
`AppearanceSettingsView` and `AutoNightSettingsView` resolves via `themedForeground(_:)`,
`Color(rgb: theme.…)`, or `Color.accentColor` (system accent, itself driven live by
`env.theme.setAccent`) — no literal `.white`/`.black` outside the swatch color values themselves
(which are the intended per-preset RGB, not text/icon colors). The theme-card preview swatches
(`Color(rgb: preview.background/accent/secondaryText/elevatedBackground/separator)`) are the
documented "literal light/dark preview swatch" exemption — each card renders the OTHER theme's fixed
palette values (by design, so the picker shows what selecting it will look like), not the live theme,
so they intentionally do not track the current selection. No invisible-after-switch text or icon
found in either file across the 2 themes × 7 accents combination space.

## 6 audit greps — final state (owned files, post-fix)

```
1. SE-width / GeometryReader / minimumScaleFactor / lineLimit(1): only 1 intentional lineLimit(1)
   (theme-card name label, short 1-2 word localized theme names, verified fits SE at Dynamic Type
   XL). No GeometryReader, no minimumScaleFactor, no fixed frames that clip the longest VI string.
2. Typography `.font(.`: 5 raw sites found across AppearanceSettingsView (1) + AboutView (3, incl.
   the numeral) — all converted to `vaultType`/Dynamic-Type-scalable `.system(.largeTitle,...)`.
   ThemeEditorView/WallpaperGalleryView raw fonts left as-is (dormant, review-light).
3. Radius: zero numeric literals in the 3 owned interactive files — `Radius.md/lg/xs` tokens
   throughout.
4. Spacing `.padding(`: 2 numeric literals (`.padding(.vertical, 6)` ×2, AppearanceSettingsView) →
   `Space.s2`. Small decorative-preview `.padding(5)`/`.frame(width:9,height:9)` inside the theme-card
   mini-mockup left as-is (literal preview content, not real UI chrome, doesn't affect layout/SE fit).
5. Hit targets: 1 HIGH (accent swatch 34pt < 44pt, no padded hit area) — fixed. Theme cards and mode
   rows already full-row/full-card tappable.
6. Haptics: 5 missing call sites (3 row-select + 1 slider pattern across 2 files) — fixed, matches
   established app-wide precedent (ChooseThemeView, PasswordGeneratorView).
```
