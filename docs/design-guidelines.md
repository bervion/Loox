# Vaultify Design Guidelines

Last updated: 2026-06-17  
Audience: AI agents, designers, iOS engineers  
Platform: Native iOS SwiftUI, deployment target iOS 17.3+

## Purpose

This document is the visual and interaction source of truth for Vaultify. Agents must use it before changing UI, design tokens, navigation, tab bar, icons, typography, or theme behavior.

Vaultify should feel Apple-native, calm, private, fast, and strong. The reference direction is Apple system apps, Telegram-level polish, and a minimal Threads-like bottom navigation fallback when advanced glass materials are unavailable.

The product must not feel like generated UI assembled screen by screen. Every surface, icon, label, and state should come from a shared design language.

## Non-Negotiable Rules

- Read `README.md`, `CLAUDE.md`, `docs/codebase-summary.md`, and this file before UI work.
- Use native SwiftUI patterns compatible with iOS 17.3 unless newer APIs are guarded with `#available`.
- Icons are Polaris assets, reached through `VaultIcon(_:size:)` — never `Image(systemName:)` or
  `Image(name)` directly. `Icons` holds the chrome tokens. SF Symbols appear only as extra
  choices inside the Space/item icon picker, never as app chrome. See CLAUDE.md.
- All visible user-facing text must be localized in English and Vietnamese.
- Do not hardcode raw colors in feature screens.
- Do not use `Color.primary`, `Color.secondary`, `.white`, `.black`, `.red`, or opacity guesses on custom themed surfaces unless explicitly mapped through semantic tokens.
- Do not create one-off button/card/list styles inside feature screens.
- Icon-only controls must still have accessibility labels, hints where useful, and selected state.
- Minimum touch target is 44 x 44 pt.
- Text contrast target is at least 4.5:1 for normal text and 3:1 for large text.
- UI components, icons, focus rings, separators, and selection indicators must reach at least 3:1 against adjacent colors.
- Theme changes must update live without killing and reopening the app.

## Product Direction

Vaultify is a secure utility app, not a marketing page. The app should prioritize:

- fast scanning
- low visual noise
- clear hierarchy
- confident spacing
- strong contrast
- predictable navigation
- native motion
- restrained decorative effects

Visual personality:

- Apple-native structure
- Telegram-like clean utility density
- Threads-like bottom bar minimalism
- secure, premium, quiet
- no playful gradients as a primary language
- no oversized cards unless they carry primary data

## Design System Model

The design system has four layers:

1. Foundation tokens: color, typography, spacing, radius, elevation, motion.
2. Semantic tokens: background, text, icon, surface, separator, accent, on-accent.
3. Components: tab bar, buttons, rows, cards, icon tiles, fields, sheets.
4. Feature screens: only compose components and semantic tokens.

Agents must update lower layers first when a pattern repeats. Feature screens should not invent new visual language.

## Swift Token API (implemented)

The four layers map to concrete Swift symbols. **Use a token — never a magic number, ad-hoc font, or raw shadow.**

| DS concept | Swift symbol | Location |
| --- | --- | --- |
| Spacing (4pt grid) | `Space.s1…s10`, `Space.gutter` (adaptive screen margin 16/20, screen edges only — card interiors use `Space.s4`), `Space.contentMax` | `DesignSystem/Tokens/Spacing.swift` |
| Corner radius | `Radius.xs/sm/md/lg/xl/pill` + `.vaultCornerRadius(_)` | `DesignSystem/Tokens/Radius.swift` |
| Control / icon / row sizing | `Metric.hitMin/controlSmall/Medium/Large/rowHeight/iconInline/Utility/Tab/Tile/TileLarge/badgeTile/iconPickerTile` | `DesignSystem/Tokens/Metrics.swift` |
| Legacy custom tab-bar layout | `TabBarMetric.*` | `DesignSystem/Tokens/Metrics.swift` |
| Elevation (soft shadow) | `.elevation(.level1/.level2/.level3/.sheet)` | `DesignSystem/Tokens/Elevation.swift` |
| Motion | `Motion.spring/standard/fast/base/medium/slow/pressScale`, `.vault(_,reduceMotion:)` | `DesignSystem/Tokens/Motion.swift` |
| Typography roles | `.vaultType(.largeTitle/.screenTitle/.section/.headline/.body/.callout/.subhead/.footnote/.caption/.sectionLabel)` | `DesignSystem/Typography.swift` |
| Secrets/codes | `Font.vaultCode(_:weight:)` — SF text with tabular digits | `DesignSystem/Typography.swift` |
| Semantic foreground | `.themedForeground(role)` / `theme.color(role)` (`ThemeRole`) | `DesignSystem/Components/ThemedComponents.swift` |
| Semantic palette (stored) | `AppTheme` fields via `Color(rgb: theme.<token>)` | `VaultifyCore/Theme/AppTheme.swift` |
| Semantic palette (derived) | `surfaceFloatingSolid/surfaceInset/surfacePressed/accentSoft/accentText/accentPress/icon*/textDisabled/*Soft/destructiveFill/onDestructive/separatorOpaque` | `VaultifyCore/Theme/AppTheme+Tokens.swift` |
| Card / divider / form bg | `ThemedCard`, `.themedCard()`, `ThemedDivider`, `.appBackground()`, `.themedFormBackground()` | `DesignSystem/Components/ThemedComponents.swift` |
| Buttons | `.buttonStyle(.themedProminent/.themedTinted/.themedDestructive)` | `DesignSystem/Components/ThemedButtonStyles.swift` |
| Compact inline buttons (row-adjacent, not full-width) | `.buttonStyle(.themedCompact/.themedCompactProminent)` | `DesignSystem/Components/ThemedButtonStyles.swift` |
| Switch | `.toggleStyle(.themed)` | `DesignSystem/Components/ThemedToggleStyle.swift` |
| Icons | `PolarisIcon(Icons.<name>, size: Metric.icon*)` | `DesignSystem/PolarisIcon.swift` |

`ThemeRole` values: `primary, secondary, tertiary, disabled, iconPrimary, iconSecondary, iconDisabled,
accent, accentFill, accentText, accentSoft, onAccent, destructive, destructiveFill, onDestructive, success, warning`.
A filled destructive control paints `destructiveFill` (the red darkened just enough for a white label to clear
4.5:1) under an `onDestructive` label; raw `destructive` is for text, icons and strokes. Derived tokens are computed
on `AppTheme` so **every** builtin and custom theme gets them without touching constructors.

### Concentricity (nested corner radii)

Radius is a **relationship, not a per-view pick**. When a rounded shape sits inset inside a rounded
parent (avatar in a card, glyph badge in a tile, embedded tile in a sheet), derive the child radius
from the parent instead of grabbing a scale token:

```swift
// R_inner ≈ R_outer − inset, floored at Radius.xs
.vaultCornerRadius(Radius.concentric(outer: Radius.lg, inset: Space.s4))
```

A child radius larger than `outer − inset` reads "flared", smaller reads "pinched" — both break the
visual parallel between the two corners. Standalone (non-nested) shapes keep using the fixed scale.

## Loox Motion Language: Controlled Reveal

The product physics of Loox is **reveal / conceal**: nothing is exposed before it needs to be, and
every hidden↔visible state change speaks the same motion vocabulary. Do not invent a new effect for
a new surface — pick the matching verb:

| Transition | Verb | Shipped primitive |
| --- | --- | --- |
| Secret field reveal | glyphs **resolve** in place (dots → characters, left to right, fixed budget) | `GlyphResolveText` (`DesignSystem/Components/GlyphResolveText.swift`) |
| Unlock | locked world **blurs away**, vault resolves behind it | `AnyTransition.controlledReveal` (`App/RootView.swift`) |
| Lock | lock screen **contracts back in**; unlocked content vanishes instantly beneath (privacy) | same transition, insertion side |
| Key derivation in flight | the ∞ **draws itself open** (gate working) | `LooxGateMark` / `LooxGateShape` (`DesignSystem/Components/LooxGateShape.swift`) |
| Copy confirmation | clipboard glyph **morphs** to check + haptic tick | `CopyMorphIcon` (`DesignSystem/Components/CopyMorphIcon.swift`) |

Rules: every verb collapses to an instant swap under Reduce Motion (`Animation.vault(_:reduceMotion:)`);
motion never gates or delays a security result (the session flip always wins); durations stay inside the
`Motion` token range (≤ ~0.4s). Whole-field crossfades on secrets are the anti-pattern — the value should
read as *decrypting*, not fading in.

## Theme And Contrast

### Status (resolved)

The earlier theme-switch desync class of bugs has been fixed; keep these invariants when adding UI:

- `VaultColors` surfaces are dynamic `UIColor`s that re-resolve on a color-scheme flip (no static
  snapshot lag) — backgrounds stay in lock-step with trait-driven foregrounds.
- No raw system colors on themed surfaces: use `.themedForeground(role)` / `theme.color(role)`
  instead of `.primary/.secondary/.tertiary/.red/.white` (camera, favicon, and literal
  light/dark mode swatches are the only allowed exceptions).
- `accentForeground` (on-accent) is derived by **WCAG contrast** (`RGBMath.onColor`), never a raw
  luminance threshold — built-in Night / Night-Tinted accents are deep enough that white clears AA.
- Sheets and full-screen covers carry `.themedColorScheme()` so their system chrome (nav title,
  `Form` section headers/footers, pickers) follows the theme, not the device appearance.
- `Toggle` uses `ThemedToggleStyle` (native `.tint` does not reach a switch inside `Form`/sheets).

### Color Principle

Use semantic color names that describe purpose, not exact appearance.

Required semantic tokens:

| Token | Purpose |
| --- | --- |
| `backgroundBase` | Root app background |
| `backgroundGrouped` | Grouped screen background |
| `surfaceBase` | Standard cards and panels |
| `surfaceElevated` | Raised cards, sheets, menus |
| `surfaceFloating` | Translucent floating controls when allowed |
| `surfaceFloatingSolid` | Solid fallback for floating controls |
| `surfaceInset` | Resting fill for tiles nested inside a card: `secondaryBackground` in light themes, `controlBackground` in dark themes |
| `surfacePressed` | Pressed/hover/touch state |
| `textPrimary` | Main readable text |
| `textSecondary` | Supporting readable text |
| `textTertiary` | Metadata only; not critical content |
| `textDisabled` | Disabled text |
| `iconPrimary` | Important icons |
| `iconSecondary` | Inactive navigation and secondary icons |
| `iconDisabled` | Disabled icons |
| `accent` | Brand/action tint |
| `onAccent` | Text/icon on accent |
| `accentSoft` | Low-emphasis selected background |
| `accentText` | Existing accent/control role: same hue, guarded to the user-locked 3:1 floor on controlBackground and accentSoft. Preserve the brand/control pairing; this is not a universal 4.5:1 body-text guarantee |
| `separator` | Hairlines and dividers |
| `shadowAmbient` | Soft outer shadow |

### Contrast Rules

- `textPrimary` on every background/surface: minimum 4.5:1.
- Normal-sized explanatory/status content must meet 4.5:1. Use the opt-in body roles below rather than assuming a control/icon color meets that floor.
- `textTertiary`: use only for metadata; still aim for 3:1 minimum.
- `accent` used as text/icon: minimum 3:1 for icons, 4.5:1 for text.
- `onAccent` must be selected by comparing black and white contrast against `accent`, not by simple brightness threshold.
- Placeholder text must not be used as the only label.
- Disabled text can be below 4.5:1 only when the disabled state is obvious and nonessential.

Private Email and Member content use opt-in `ThemeRole.secondaryBody`, `.successBody`
and `.warningBody`. They resolve to derived `AppTheme.secondaryBodyText`,
`successBodyText` and `warningBodyText` in `VaultifyCore/Theme/AppTheme+Tokens.swift`.
The derivation guards 4.5:1 on background, secondary/grouped/elevated/control backgrounds
and pressed surfaces. These roles change no stored palette fields and apply only at
call sites that select them; the existing accent, icon and control 3:1 pairing stays intact.
Use them for normal-sized explanatory or status copy on content surfaces. Continue to
verify the actual foreground/background pair for each new use and custom theme.

### Mode Requirements

Every theme must define values for:

- light mode
- dark mode
- tinted/accented mode
- increased contrast
- reduced transparency

Do not ship a theme if any state has invisible text, unreadable icons, or controls that disappear into the background.

## Typography

Use Apple-like type hierarchy: clear, compact, and consistent.

Recommended roles:

| Role | Size | Weight | Usage |
| --- | ---: | --- | --- |
| Large title | 32-34 | Bold | Rare root identity screens |
| Screen title | 28-30 | Bold | Root screen title, e.g. `Kho` |
| Section title | 17-19 | Semibold | Section headings |
| Body | 16-17 | Regular | Main rows, descriptions |
| Callout | 15-16 | Regular/Medium | Secondary row content |
| Caption | 12-13 | Regular/Medium | Metadata |
| Secrets/codes | `Font.vaultCode` (SF) | role-specific | Passwords, codes, card numbers, TOTP |

Rules:

- Do not make important labels smaller than 15 pt.
- Do not use tiny tab labels; the tab bar is icon-only.
- Do not mix many weights on one screen.
- Prefer system dynamic type styles where possible.
- Support Dynamic Type without overlapping controls.
- Use SF everywhere — no monospaced typeface. For aligned numerals (countdowns, scores) add `.monospacedDigit()` (still SF, tabular figures).

## Icon System

Vaultify renders every icon through `VaultIcon`, which resolves an `sf:`-prefixed name to an SF
Symbol and anything else to a bundled Polaris asset. The app's icon language is Polaris; SF is
offered only as an additional pick inside the Space/item icon picker.

Icon asset rules:

- Normalize artboards to 24 x 24 pt.
- Use optical glyph size around 20-22 pt inside the artboard.
- Keep stroke weight visually consistent, usually 2 pt for outline icons.
- Provide selected/filled variants for tab icons when possible.
- Use template rendering so semantic colors control icon color.
- Avoid icons with tiny interior details that collapse at 22-26 pt.
- Keep active and inactive variants optically aligned.

Runtime icon rules:

- Default inline icon size: 20-22 pt.
- Navigation/tab icon size: 24-28 pt.
- Utility tile icon size: 22-26 pt.
- Decorative icons should be rare.
- Icon-only buttons require accessibility labels.

## Bottom Tab Bar Direction

The Vaultify tab bar must use the native iOS `TabView` tab bar for switching performance,
system safe-area behavior, and Apple-provided Liquid Glass on iOS 26+. The visual tab items
remain icon-only by supplying Polaris image assets without visible text labels.

The tab bar should look and behave like a native Apple control layer, not a Material bottom
navigation bar and not a heavy custom overlay.

### Required Behavior

- No visible title labels in the tab bar.
- Icons only.
- Four primary tabs:
  - Home/Vault
  - Items/Categories
  - Watchtower/Monitoring
  - Search
- Preserve each tab's navigation stack state.
- Switching tabs must not recreate root views unnecessarily.
- Let the native tab bar own safe-area/content avoidance. Do not add a second custom bottom
  overlay unless a feature explicitly requires it.
- The selected tab must be visually obvious without relying on text.
- Badges are allowed only for meaningful alerts; use dots or compact counters.
- Use reduced-motion fallback for users who request it.
- Do not trigger wallpaper/mesh morphing on tab selection; keep switching cheap and immediate.

### Accessibility

Icon-only is visual only. Accessibility must remain explicit:

- Each tab button has localized `accessibilityLabel`.
- Each selected tab exposes selected state.
- Each tab is a button.
- Badge values are announced.
- VoiceOver order follows visual order.
- Minimum hit area is 44 x 44 pt.
- Do not hide accessibility by setting icon views inaccessible unless the parent tab button supplies the full label and state.

Suggested labels:

- `Trang chủ` / `Home`
- `Mục` / `Items`
- `Giám sát` / `Watchtower`
- `Tìm kiếm` / `Search`

These labels are not visible in the tab bar.

### Layout Spec

The system owns bar height, corner radius, safe-area behavior, Liquid Glass surface, and
selection interaction. Vaultify owns only the tab order, icon asset choice, accent tint, and
localized accessibility labels.

Icon asset guidance:

- Keep tab icon artboards normalized and optically balanced.
- Provide filled selected variants where possible.
- Use template rendering so the system/accent tint can apply cleanly.
- Do not reintroduce visible labels.

### Visual States

Inactive tab:

- rendered by the native tab bar
- use the outline Polaris icon asset where possible
- opacity must not be the main contrast strategy in custom assets

Active tab:

- rendered by the native tab bar with app accent tint
- use the filled Polaris icon asset where possible
- no visible text label

Pressed state:

- leave press/highlight interaction to the system tab bar
- do not add custom spring, drag, scale, or glass morphing on top

Badge state:

- dot or compact counter on top trailing of the icon hit area
- badge color must pass non-text contrast against the bar surface
- badge must not resize the tab item layout

### Motion

Default:

- native tab selection animation only
- no app-driven wallpaper/mesh morph on tab selection

Avoid excessive blur, glow, rotation, drag-follow, or long elastic movement in tab switching.

Reduced Motion:

- rely on system behavior
- do not add additional custom tab motion

## Liquid Glass Strategy

Liquid Glass belongs to the navigation/control layer, not ordinary content cards.

Use it for:

- bottom tab bar
- floating toolbars
- compact navigation controls
- sheets or overlays when system APIs provide it

Do not use it for:

- every card
- list rows
- dense content panels
- nested glass-on-glass surfaces
- decorative backgrounds

### Supported OS Path

When the local Xcode SDK exposes Apple Liquid Glass APIs, use native APIs behind availability guards.

Rules:

- Guard all new APIs with `#available`.
- Prefer native system glass/material behavior over custom blur stacks.
- Let system accessibility settings change glass automatically where possible.
- Do not simulate Liquid Glass with heavy blur, glow, distortion, or random gradients.
- Test light, dark, increased contrast, reduced transparency, and reduced motion.

### Fallback Path For Older iOS

For iOS versions without native Liquid Glass APIs, use a solid or near-solid floating capsule inspired by Threads:

Light mode fallback:

- surface: near-white `surfaceFloatingSolid`
- opacity: 0.94-1.0
- border: subtle separator
- shadow: soft outer shadow
- selected fill: neutral light gray or accent soft

Dark mode fallback:

- surface: near-black elevated surface
- opacity: 0.96-1.0
- border: subtle lighter separator
- shadow: soft, not glowing
- selected fill: neutral dark gray or accent soft

Reduced Transparency:

- always use the solid fallback
- increase border clarity slightly
- remove background blur

Increased Contrast:

- strengthen icon contrast
- strengthen selected indicator edge
- avoid low-alpha separators

## Tab Bar Implementation (implemented)

Built in `Vaultify/Features/Main/` using native SwiftUI `TabView`. The native tab bar remains
visible so iOS owns switching, safe area, selection interaction, and iOS 26 Liquid Glass. Vaultify
keeps the visual bar icon-only by providing only Polaris `Image` assets in each `.tabItem`; localized
labels are accessibility-only.

- `MainTabView`: owns the `TabView(selection:)`, tab order, app accent tint, inactivity timer, and copy toast.
- `VaultTab`: enum (order, outline + filled Polaris icon, localized accessibility label).
- `VaultTabBar` / `VaultTabBarBackground`: legacy custom implementation kept out of the runtime path unless
  a future experiment explicitly re-enables it.

Liquid Glass note: prefer framework-provided Liquid Glass from the native tab bar. Use custom
`glassEffect` only for truly custom floating controls, guarded by `#if compiler(>=6.2)` +
`#available(iOS 26, *)` with a solid/material fallback. Never glass on content cards/rows.

Implementation constraints:

- Keep per-tab state alive.
- Do not hide the native tab bar for the main shell.
- Do not place labels visually under icons.
- Do not hardcode strings in tab item views.
- Do not construct icons with `Image(systemName:)` — go through `VaultIcon`.
- Use Polaris assets for icon rendering.
- Use semantic theme tokens for all colors.
- Let native `TabView` handle bottom safe area for root content.
- Keep tab bar independent from feature screens.

Suggested layering:

```text
Root container
  Native TabView
    Home navigation stack
    Items navigation stack
    Watchtower navigation stack
    Search navigation stack
    Native system tab bar
      Icon-only Polaris tab items
```

Do not place the tab bar inside every feature screen.

## Screen Composition

Root screens:

- Use a strong screen title.
- Keep top actions small and icon-based.
- Use section titles consistently.
- Use cards only when grouping or affordance is needed.
- Keep content aligned to a shared horizontal grid.
- Let the native tab bar reserve bottom space; add extra bottom padding only for custom overlays/toasts.

Rows:

- Leading icon tile: 32-40 pt.
- Main label: 16-17 pt.
- Supporting label: 13-15 pt, only when useful.
- Chevron/action icon: semantic secondary icon color.
- Row height: usually 52-64 pt.

Cards:

- Radius: 16-24 pt for app cards, smaller only for dense controls.
- Use semantic surface tokens.
- Do not rely on black text on dark card or white text on light card.
- Pressed state must be visible in both modes.

Buttons:

- Primary action uses `accent` and `onAccent`.
- Secondary action uses surface + textPrimary.
- Destructive action uses semantic destructive tokens: `destructiveFill` + `onDestructive` (white label).
- Icon-only buttons require labels for accessibility.

Notices (banners):

- `VaultInfoBanner(.info/.warning/.error)` — the always-open tinted notice. Use when the whole
  message must be read (a degraded state, a blocked feature, a shared-item explainer).
- `VaultExpandableBanner` — same severity vocabulary, PAINTED not tinted, collapsed to a single
  44pt bar until tapped, with the explanation and ONE action behind the disclosure. Use where a
  warning must be impossible to slide past: the item detail warning (`ItemAttentionBanner`)
  leads with the most severe finding, shows a count when it speaks for several, and keeps the
  sentences plus the fix a tap away.
- ONE banner per screen state, never a stack: three cards with three actions is the button wall
  rule 7 forbids. Rank the findings, lead with the top one, list the rest inside.
- Surfaces differ by shape, and each has its own text contract:
  - `VaultInfoBanner` — soft severity fill, PRIMARY-rank copy, TEXT-rank status token
    (`accentText` / `warningText` / `destructiveText`) on the glyph and action label. Never the
    FILL-rank hue on its own soft fill — it measures as low as 2.48:1.
  - `VaultExpandableBanner` — solid `Variant.fill`, copy and glyphs in `Variant.onFill`. The
    fill is darkened by the minimum that lets white clear **4.5:1** (a banner carries sentences,
    so the 3:1 a two-word button label gets is not enough; the raw Day red measures 3.91), and a
    hue too light for that budget (dark-mode yellow, the mono accent) keeps its color and takes
    the dark on-color instead. Expanded copy sits flush with the chevron, not indented under the
    title.
  - Buttons on a painted banner: primary is `background`-filled with a TEXT-rank label; the one
    quiet secondary uses `Variant.fillQuiet` — the hue stepped AWAY from its on-color. Lightening
    a red fill under white text looks right and measures 3.48:1; deepening it keeps 6.2:1. Both
    are `Radius.sm` rounded rects at `Metric.controlSmall`.
- Toolbar overflow ("…") is chrome, not an accent action: render it at `.iconPrimary`.

### Equal-height inset tile grids

Use `surfaceInset` for the resting tile fill; reserve `surfacePressed` for an actual
interaction state. Small Member grids use `EqualHeightTileLayout`: measure content at
the actual column width, then give every tile in a multi-column section the tallest
intrinsic height across the entire grid, including all six Member tiles. Accessibility
Dynamic Type uses one column with each tile's natural height. Titles and metrics wrap;
do not impose a fixed tile height, truncate text or shrink labels to force alignment.
Member inset tiles use `Radius.md` (14pt), an owner-requested softer shape within the
`Radius.lg` section shell and an intentional exception to concentric child rounding.

## Home Screen Notes From Current Screenshot

Observed problems to fix during UI standardization:

- Utility card has text/icon that can become nearly invisible after theme changes.
- Tab bar icons and labels are too small for the desired visual direction.
- Visible tab labels add clutter and should be removed.
- Icon sizes are inconsistent with the strength of the screen title.
- Some secondary text appears too faint for real content.
- The bottom bar currently reads as a native default tab bar instead of a custom Vaultify control.

Desired result:

- large, clear icon-only bottom navigation
- strong active state
- no visible tab labels
- solid fallback that feels intentional on older iOS
- Liquid Glass control layer on supported iOS
- no invisible text after theme switching

## Home & Watchtower Components (Implemented)

### Home Screen (`Vaultify/Features/Home/`)

Rebuilt to DS spec with folder switcher, quick actions, TOTP quick-view, and "Needs attention" list.

**Components** (`Components/`):
- `HomeHeaderBar` — folder switcher + header controls.
- `QuickActionTile` — tappable action tile (Generator, Settings, etc.).
- `TotpCardView` — TOTP display with 6-digit code + countdown ring.
- `TotpRingView` — circular progress indicator for TOTP countdown.
- `AttentionCell` — item row for "Needs attention" (rotation overdue/soon/stale, weak password).
  Its trailing button reads **Update**: it opens the item editor with the password generator
  already presented, so the fix is one confirmation. An item with no password, or one sealed
  behind Extra Protection, opens the plain editor instead.

**Sections** (from top). Order and visibility are user-editable (`HomeSection` +
`HomeLayoutEditor`); the list below is the DEFAULT, and a saved order always wins:
1. **Profile row** — pinned, never hidden or reordered.
2. **Quick actions** — Add · Security · Generate · 2FA (owner decision 260730: leads the default
   order so the primary actions sit under the thumb on first glance).
3. **Pending shares / approval alerts** — only when there is something waiting.
4. **TOTP quick-view** — show next TOTP without entering detail screen.
5. **"Needs attention"** — rotation reminders + weak passwords (from `RotationStatus`). The
   section title lives INSIDE the card (same anatomy as the "All items" card), not as a grey
   label above it.
6. **Recently used**, **Favorites** — pinned + favorite items.
7. **"All items"** — Space filter as the card's own title, newest first, pinned-first.

**Retired:** `CustomizeHomeScreen`, `UtilitiesSection`, `homeShowRecentlyUsed/Modified` settings. Underlying data (`pinned`, `favorite`, `useCount`) retained.

### Watchtower Screen (`Vaultify/Features/Watchtower/`)

Reshaped with visual strength gauge and issue category drill-down.

**Components:**
- `WatchtowerScoreRing` — 270° gauge on the real 0–1000 audit scale, 1P anatomy: display-size
  figure (`VaultType.scoreDisplay`) centered on the dial, band label UPPERCASE at the arc's lower
  opening, triangle marker FIXED at top center (score is carried by number + band hue, never by
  marker position). Intro replays only on real data moments (`WatchtowerIntroGate` — pull to
  refresh, finished audit, persona switch), never on a tab visit.
- `WatchtowerStrengthCard` — grade DISTRIBUTION bar (`VaultHealth.grades`), 1P layered capsules:
  strongest grade on top, each segment overlapping the one below, deep green → green → amber →
  orange → red via `watchtowerGradeHue`; present-but-tiny grades keep a 10pt sliver. The stack is
  clipped to the bar capsule — layers can never paint outside the card, whatever the animation
  state.
- `WatchtowerComponents` — helper views (category headers, issue rows, 2FA support indicator).
- `TwoFactorCatalog` (`Services/Watchtower/`) — curated "supports 2FA" service hostnames (host-suffix matching, no false-positives).

**Issue Categories** (drill-down from home):
- **Compromised** — HIBP match (plaintext, k-anonymity hash).
- **Reused** — appears in ≥2 items (levenshtein match, configurable threshold).
- **Weak** — low password strength score (≤1 per `PasswordStrength.evaluate`).
- **Missing 2FA** — item has no 2FA code / TOTP, and its hostname matches `TwoFactorCatalog`.

## Token Checklist For Agents

Before changing feature UI, verify:

- `textPrimary`, `textSecondary`, `textTertiary` exist and are live theme-aware.
- `iconPrimary`, `iconSecondary`, `iconDisabled` exist and are live theme-aware.
- `surfaceFloating` and `surfaceFloatingSolid` exist.
- `accent` and `onAccent` are WCAG-tested pairs.
- `separator` works on base, elevated, and floating surfaces.
- Theme switching updates all visible UI immediately.
- No feature screen depends on static theme globals for live colors.

## QA Checklist

Agents must verify these before marking UI work done:

- Light mode screenshot.
- Dark mode screenshot.
- Switch light to dark and dark to light without restarting app.
- No invisible text, labels, icons, badges, or chevrons after switching theme.
- Tab bar has no visible title labels.
- Tab bar icons are optically large and clear.
- Selected tab is obvious without text.
- Touch targets are at least 44 x 44 pt.
- VoiceOver announces every tab label and selected state.
- Dynamic Type does not break screen layout.
- Reduce Transparency uses solid fallback.
- Increased Contrast remains readable.
- Reduce Motion removes moving/bouncy transitions.
- Content is not covered by the floating tab bar.
- Snapshot or visual QA covers at least one small iPhone and one large iPhone.
- Contrast checks pass WCAG thresholds.

## Suggested Migration Plan

Phase 1: Theme safety

- Remove static UI color reads from live-rendered SwiftUI views.
- Route surfaces, text, icons, separators, and accents through live semantic tokens.
- Fix `onAccent` to choose the higher WCAG contrast foreground.
- Add or update contrast tests for built-in themes.

Phase 2: Icon system cleanup

- Audit tab icons for 24 x 24 artboard consistency.
- Add filled/selected variants where needed.
- Normalize stroke weight and optical size.
- Ensure template rendering works in light and dark mode.

Phase 3: Native icon-only tab bar

- Use native `TabView` tab bar with icon-only visual tab items.
- Preserve tab navigation state.
- Keep visible labels hidden while preserving localized accessibility labels.
- Avoid custom tab switching animations, drag-follow, and mesh morphing on selection.

Phase 4: Screen polish

- Migrate Home screen cards, rows, and icon tiles to semantic components.
- Ensure section titles, body text, and metadata use consistent typography roles.
- Remove screen-level one-off color and font choices.

Phase 5: QA and docs

- Run tests and UI previews.
- Capture light/dark screenshots.
- Update changelog or implementation notes if behavior changes.

## Agent Prompt Template

Use this when assigning implementation work:

```text
Read first:
- README.md
- CLAUDE.md
- docs/codebase-summary.md
- docs/design-guidelines.md

Task:
Implement Vaultify native icon-only tab bar per docs/design-guidelines.md.

Constraints:
- Native SwiftUI, iOS 17.3+ target.
- Newer Apple APIs must be guarded with #available.
- No visible tab labels.
- Keep accessibility labels and selected state.
- Use `VaultIcon` with an `Icons` token or an `IconCatalog` token, never a bare symbol name.
- Use live semantic theme tokens only.
- Preserve per-tab navigation state.
- Prefer the native iOS tab bar surface; do not add a custom overlay for the shell.
- Verify theme switching without restart.

Acceptance:
- Light/dark screenshots pass.
- No invisible text/icons after theme switch.
- Tab bar icon-only and minimum 44 x 44 pt hit targets.
- VoiceOver announces tab names and selected state.
- Contrast meets WCAG thresholds.
```

## References

- Apple Design: https://developer.apple.com/design/
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Apple Design Resources and iOS design kit updates: https://developer.apple.com/design/resources/
- WWDC25 Meet Liquid Glass: https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC25 Get to know the new design system: https://developer.apple.com/videos/play/wwdc2025/356/
- Apple SF Symbols design principles: https://developer.apple.com/sf-symbols/
- WCAG 2.2 contrast requirements: https://www.w3.org/TR/WCAG22/

## Resolved Decisions (2026-06-17)

- **Tab naming:** `Home / Items / Watchtower / Search` (accessibility labels only; bar is icon-only).
- **Selected state:** native tab bar selection with app accent tint and filled Polaris icon variants where available.
- **Accent presets:** 7 Design-System presets (blue/indigo/teal/purple/pink/graphite/mono), light + dark hues each; custom RGB removed. Every preset must pass WCAG `onAccent` (`RGBMath.onColor`).
- **Backgrounds:** Flat themed backgrounds only; decorative wallpapers (gradient/pattern/mesh/photo) gated OFF via `WallpaperFeature.decorativeEnabled = false`. Engine code retained; re-enable flag for future advanced theming.
- **Type scale:** DS roles map onto Apple **Dynamic Type** styles (`VaultType`) — keeps accessibility /
  Dynamic Type rather than fixed pixel sizes.
- **Liquid Glass:** use framework-provided native tab bar Liquid Glass on iOS 26+. Keep shell tab switching on
  the native `TabView` path; use custom `glassEffect` only for non-shell custom floating controls.

## Unresolved Questions

- Wire a meaningful Watchtower **badge** on the native tab item once a
  cheap shared issue-count provider exists (today the count is computed inside `WatchtowerScreen`).

### Quiet informational banners

`VaultInfoBanner.subtle()` is the opt-in treatment for contextual notices: semantic
soft/neutral backgrounds, contrast-adjusted foregrounds, `Radius.sm`, and a 44pt action.
Use a warning for an outstanding prerequisite and neutral info for standing guidance.
Neutral info uses the elevated surface token so it stays distinct from the grouped canvas.
Private Email puts standing receive-only guidance below its main content; its verification
action navigates explicitly without wrapping the whole banner in a List disclosure row.
