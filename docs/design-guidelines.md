# Vaultify Design Guidelines

Last updated: 2026-06-16  
Audience: AI agents, designers, iOS engineers  
Platform: Native iOS SwiftUI, deployment target iOS 17.6+

## Purpose

This document is the visual and interaction source of truth for Vaultify. Agents must use it before changing UI, design tokens, navigation, tab bar, icons, typography, or theme behavior.

Vaultify should feel Apple-native, calm, private, fast, and strong. The reference direction is Apple system apps, Telegram-level polish, and a minimal Threads-like bottom navigation fallback when advanced glass materials are unavailable.

The product must not feel like generated UI assembled screen by screen. Every surface, icon, label, and state should come from a shared design language.

## Non-Negotiable Rules

- Read `README.md`, `CLAUDE.md`, `docs/codebase-summary.md`, and this file before UI work.
- Use native SwiftUI patterns compatible with iOS 17.6 unless newer APIs are guarded with `#available`.
- Do not use SF Symbols directly in app UI. Use Polaris PDF/SVG icon assets through the existing icon system.
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
| `separator` | Hairlines and dividers |
| `shadowAmbient` | Soft outer shadow |

### Contrast Rules

- `textPrimary` on every background/surface: minimum 4.5:1.
- `textSecondary` on every background/surface: minimum 4.5:1 when it is real content.
- `textTertiary`: use only for metadata; still aim for 3:1 minimum.
- `accent` used as text/icon: minimum 3:1 for icons, 4.5:1 for text.
- `onAccent` must be selected by comparing black and white contrast against `accent`, not by simple brightness threshold.
- Placeholder text must not be used as the only label.
- Disabled text can be below 4.5:1 only when the disabled state is obvious and nonessential.

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
| Numeric amount | existing mono amount style | role-specific | Money and aligned numbers |

Rules:

- Do not make important labels smaller than 15 pt.
- Do not use tiny tab labels; the tab bar is icon-only.
- Do not mix many weights on one screen.
- Prefer system dynamic type styles where possible.
- Support Dynamic Type without overlapping controls.
- Use monospace amount typography only for financial amounts.

## Icon System

Vaultify uses Polaris icons from vector assets. Agents must make Polaris icons behave like a custom SF Symbols family.

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

The Vaultify tab bar must be custom, icon-only, floating, and minimal.

The tab bar should look like a native Apple control layer, not a Material tab bar and not a labeled bottom navigation bar.

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
- Content must reserve enough bottom inset so the tab bar never covers rows, buttons, or scroll content.
- The selected tab must be visually obvious without relying on text.
- Badges are allowed only for meaningful alerts; use dots or compact counters.
- Use light haptic feedback when selection changes.
- Use reduced-motion fallback for users who request it.

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

Base dimensions for iPhone portrait:

| Token | Value |
| --- | ---: |
| Bar horizontal inset | 20-24 pt |
| Bar bottom offset | 10-14 pt above safe area |
| Bar height | 58-64 pt |
| Bar corner radius | height / 2 |
| Button hit area | 56 x 48 pt minimum |
| Selected indicator | 44-48 pt wide, 42-46 pt high |
| Icon visual size | 25-27 pt active, 24-26 pt inactive |
| Badge dot | 7-8 pt |
| Content bottom padding | tab bar height + safe area + 24-32 pt |

Small iPhone adjustments:

- Keep touch target at least 44 x 44 pt.
- Reduce horizontal inset before reducing icon size.
- Do not reintroduce visible labels.

iPad adjustments:

- Keep bar compact; do not stretch icons across the full width.
- Max bar width around 430-520 pt.
- Center the floating bar.

### Visual States

Inactive tab:

- icon color: `iconSecondary`
- no background or a nearly invisible hover/pressed state
- opacity must not be the main contrast strategy

Active tab:

- icon color: `accent` or `iconPrimary`, depending on selected indicator contrast
- selected indicator uses `accentSoft` or a neutral selected fill
- selected indicator can be a soft circle/pill behind the icon
- icon may use a filled variant
- no visible text label

Pressed state:

- scale 0.96-0.98
- selected fill slightly deepens
- animation must feel native, not bouncy or playful

Badge state:

- dot or compact counter on top trailing of the icon hit area
- badge color must pass non-text contrast against the bar surface
- badge must not resize the tab item layout

### Motion

Default:

- selection indicator moves with a short spring
- icon color fades over 160-220 ms
- pressed scale returns quickly

Suggested animation:

- duration: 180-260 ms
- spring: smooth, low bounce
- no excessive blur, glow, rotation, or long elastic movement

Reduced Motion:

- no moving indicator travel
- use crossfade or immediate state change
- no scale bounce

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

## Tab Bar Implementation Guidance

Current app uses native `TabView` in `Vaultify/Features/Main/MainTabView.swift`. For the requested icon-only visual language, agents should move toward a custom tab container.

Recommended structure:

- `MainTabView`: owns selected tab and tab content.
- `VaultTabBar`: renders floating icon-only control.
- `VaultTabButton`: renders each tab item and accessibility state.
- `VaultTabBarBackground`: chooses Liquid Glass or fallback material.
- `VaultTabItem`: enum with icon asset names, accessibility keys, and ordering.

Implementation constraints:

- Keep per-tab state alive.
- Hide any native tab bar if a custom overlay is used.
- Do not place labels visually under icons.
- Do not hardcode strings in tab item views.
- Do not use SF Symbols.
- Use Polaris assets for icon rendering.
- Use semantic theme tokens for all colors.
- Use safe-area-aware bottom positioning.
- Add bottom padding to scrollable root content.
- Keep tab bar independent from feature screens.

Suggested layering:

```text
Root container
  Tab content area
    Home navigation stack
    Items navigation stack
    Watchtower navigation stack
    Search navigation stack
  Floating tab bar overlay
    Liquid Glass / solid fallback background
    Icon-only tab buttons
```

Do not place the tab bar inside every feature screen.

## Screen Composition

Root screens:

- Use a strong screen title.
- Keep top actions small and icon-based.
- Use section titles consistently.
- Use cards only when grouping or affordance is needed.
- Keep content aligned to a shared horizontal grid.
- Reserve bottom padding for the floating tab bar.

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
- Destructive action uses semantic destructive tokens.
- Icon-only buttons require labels for accessibility.

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

Phase 3: Custom tab bar

- Replace visible native tab labels with custom icon-only floating tab bar.
- Preserve tab navigation state.
- Add Liquid Glass path with availability guard.
- Add solid fallback path for older iOS and accessibility settings.
- Add haptic, selected, pressed, badge, and VoiceOver states.

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
Implement Vaultify icon-only floating tab bar per docs/design-guidelines.md.

Constraints:
- Native SwiftUI, iOS 17.6+ target.
- Newer Apple APIs must be guarded with #available.
- No visible tab labels.
- Keep accessibility labels and selected state.
- Use Polaris icon assets, not SF Symbols.
- Use live semantic theme tokens only.
- Preserve per-tab navigation state.
- Add solid fallback when Liquid Glass is unavailable or Reduce Transparency is enabled.
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

## Unresolved Questions

- Confirm exact Liquid Glass API names from the local Xcode SDK before implementation; keep all usage behind availability guards.
- Confirm final tab naming: `Home/Items/Watchtower/Search` or `Vault/Items/Watchtower/Search`.
- Confirm whether selected tab should use a circular indicator or a compact pill indicator. Recommendation: compact pill for stronger Apple/Threads feel.
