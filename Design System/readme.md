# Vaultify Design System

Visual + interaction source of truth for **Vaultify** — a secure, Apple-native iOS password manager (logins, cards, identities, secure notes) in the spirit of 1Password, with Telegram-style live theming and a Threads-style minimal bottom bar.

Vaultify should feel **Apple-native, calm, private, fast, and strong**. Low visual noise, clear hierarchy, confident spacing, strong contrast, predictable navigation, native motion, restrained decoration. It is a secure utility — not a marketing page.

- **Platform:** native iOS SwiftUI, iPhone only, deployment target iOS 17.6+. This web design system is the visual specification + a clickable recreation engineers build against.
- **References:** Apple HIG, 1Password (structure), Telegram (theming + utility density), Threads (floating icon-only bottom bar).
- **Icons:** Shopify **Polaris** icon set (the product explicitly uses Polaris, not SF Symbols).

## Sources provided
- A detailed written **Vaultify Design Guidelines** document (pasted by the user) — the source of truth this system encodes.
- **No codebase or Figma file was attached.** Token values, the component set, and the UI kit are derived from the guidelines + Apple HIG conventions. If/when the SwiftUI repo (`README.md`, `CLAUDE.md`, `docs/codebase-summary.md`, `Vaultify/Features/Main/MainTabView.swift`, theme/token files) is shared, reconcile names against it.

---

## Content fundamentals (copy & tone)

Vaultify ships **bilingual EN + VI**; the UI kit demonstrates Vietnamese as primary (the user's language). Tone is **quiet, reassuring, precise** — never playful, never alarmist.

- **Voice:** plain, direct, human. Short labels. "Mở khoá kho của bạn" / "Unlock your vault", not "Welcome back, let's get you in!".
- **Person:** address the user as *bạn / you*; the app speaks about *your* vault, *your* items.
- **Casing:** sentence case for body and buttons ("Mở khoá", "Khoá kho ngay"). Section headers are short ALL-CAPS labels ("YÊU THÍCH", "BẢO MẬT"). Screen titles are nouns ("Kho", "Giám sát", "Tìm kiếm").
- **Numbers:** counts are concrete and small ("Tất cả · 9", "1 mục trong rò rỉ dữ liệu"). Avoid vanity stats. Money and codes use tabular monospace.
- **Security copy:** state facts, give the next action. "Mật khẩu bị lộ — 1 mục trong rò rỉ dữ liệu" → tappable fix. Never scare, never blame.
- **No emoji.** No exclamation-heavy marketing. No filler.
- **Example labels:** `Trang chủ/Home`, `Mục/Items`, `Giám sát/Watchtower`, `Tìm kiếm/Search` (these are accessibility labels only — the tab bar shows no text).

---

## Visual foundations

- **Color:** semantic-token driven (see `tokens/colors.css`). Light is `:root`; dark is `[data-theme="dark"]`. Never hardcode raw colors or use `.white/.black/.primary/.secondary` on themed surfaces — always a semantic token. `onAccent` is chosen by WCAG contrast vs the accent, not by brightness. Increased-contrast (`[data-contrast="more"]`) and reduced-transparency are first-class.
- **Accent & live theming:** default accent is a refined blue (`#2563eb` light / `#4c8dff` dark). Six presets (`blue, indigo, teal, purple, pink, graphite`) swap via `[data-accent="…"]` — Telegram-style. Theme + accent live on a top wrapper so **every surface re-tints instantly with no restart and no light/dark desync** (a key requirement — demonstrated in the UI kit).
- **Type:** Apple system faces — **SF Pro Text / SF Pro Display** for UI, **SF Mono** for secrets, codes and amounts (tabular figures). Compact iOS hierarchy: large title 34 · screen title 28 · section 19 · body 17 · subhead 15 · footnote 13 · caption 12. Important labels never below 15. Don't mix many weights.
- **Spacing:** 4pt grid (`--space-1..10`); default screen gutter 16. Content width capped ~430 (iPhone portrait).
- **Radii:** xs 6 · sm 10 (buttons, fields, tiles) · md 14 (grouped lists) · lg 20 (cards) · xl 28 (sheets) · pill (tab bar, capsules).
- **Elevation:** soft, ambient, **never glowing**. hairline (0.5px separator), elevation-1 resting, elevation-2 menus, elevation-3 floating tab bar / sheets. Cards are hairline-bordered or lightly shadowed surfaces, generous rounding, no colored left-border accents.
- **Backgrounds:** flat semantic surfaces. Light: white base, `#f2f2f7` grouped. Dark: true black base, `#1c1c1e` cards. **No decorative gradients as primary language** (the only gradient is the neutral stage behind the device mock).
- **Liquid Glass:** reserved for the navigation/control layer (tab bar, floating toolbars, sheets) — never on content cards, list rows, or as decoration. Translucent `surface-floating` with blur; **solid `surface-floating-solid` fallback** for older iOS / reduce-transparency. The web `TabBar` mirrors both paths.
- **Motion:** short, low-bounce, Apple-native. 140ms fades, ~200–260ms transitions, a low-bounce spring for the tab indicator. Press = subtle scale (0.97) + deepened fill. All durations collapse under `prefers-reduced-motion`.
- **Hover/press:** touch-first. Press deepens the fill (`--accent-press`) and scales down slightly; rows/controls show `--surface-pressed`. No hover-dependent affordances.
- **Imagery:** there is essentially none — favicons/item glyphs are Polaris icons in tinted tiles. Quiet and iconographic.

---

## Iconography

Vaultify uses the **Shopify Polaris** icon set, made to behave like a custom SF Symbols family:

- **Source:** loaded from the unpkg CDN (`@shopify/polaris-icons@7.13.0/dist/svg/<Name>.svg`). No icon binaries are vendored; the set is CDN-available and the `Icon` component fetches + inlines each SVG once (cached), recoloring via `fill` so a single **semantic color token drives the glyph** (works in real browsers, screenshots, and exports alike).
- **Component:** `<Icon name="lock" size={22} color="var(--icon-secondary)" />`. Pass a **semantic name** (mapped in `components/core/Icon.jsx` → `ICON_MAP`: `home, items, watchtower, search, login, card, identity, note, email, copy, view, hide, edit, delete, add, refresh, settings, lock, unlock, success, alert, warning, chevron.*` …) or any raw Polaris file stem (`name="LockMajor"`).
- **Sizing:** inline 20–22, tab 24–27, utility tiles 22–26. Tab icons have filled variants where Polaris provides them (`home.fill`, `items.fill`).
- **Icon-only controls** always carry an accessibility label (`IconButton` requires `label`).
- **Emoji / unicode icons:** not used.
- **Substitution flagged:** Polaris has **no biometric glyph**. The Face ID mark on the unlock screen is a small custom-drawn SVG (the one place we draw an icon) — see CAVEATS. Status-bar cellular/wifi/battery are device-chrome drawn in the frame, not app icons.

---

## Index / manifest

**Global CSS** — consumers link `styles.css` only:
- `tokens/colors.css` — palette + light/dark + contrast scopes
- `tokens/accents.css` — 6 accent presets (live theming)
- `tokens/typography.css` — families, weights, scale, role helpers
- `tokens/spacing.css` — 4pt spacing, radii, control sizing, tab-bar layout
- `tokens/elevation.css` — shadows + motion (durations/easing)
- `tokens/base.css` — reset, reduced-transparency fallback

**Components** (`components/core/`, namespace `window.VaultifyDesignSystem_*`):
`Icon`, `IconTile`, `Button`, `IconButton`, `Card`, `Row`, `SectionHeader`, `Field`, `Switch`, `SegmentedControl`, `Badge`, `StrengthMeter`, `TabBar`. Each has `.d.ts` (props) and most a `.prompt.md` (usage). Card HTML per group renders in the Design System tab.

**UI kit** (`ui_kits/ios-app/`): interactive iPhone recreation — `index.html` orchestrates Unlock → Vault (Kho) → Item detail → Watchtower → Items → Search → Appearance, with live theme/accent controls. Screen files: `UnlockScreen.jsx`, `VaultHome.jsx`, `ItemDetail.jsx`, `Watchtower.jsx`, `Appearance.jsx`, plus `kit-components.jsx` (local primitive mirrors) and `app.jsx`.

**Specimen cards** (`guidelines/*.card.html`): Colors, Type, Spacing, Brand (icons) — the Design System tab.

**Generated, do not edit:** `_ds_bundle.js`, `_ds_manifest.json`, `_adherence.oxlintrc.json`.
