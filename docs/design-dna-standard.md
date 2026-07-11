# Loox Design DNA Standard

**MANDATORY for every agent doing ANY UI work in this repo.** This is the acceptance bar, not
inspiration. A screen that fails a checklist item below is not done. Derived from the Apple
Design Award DNA study (grug, Tide Guide, Tiimo, Structured, (Not Boring) Camera, WWDC25
Liquid Glass) applied to Loox. Companion docs: `design-guidelines.md` (token API contract),
this file (what "good" means and how to verify it).

## The formula

**Top-tier = System familiarity × Product personality.** Native behavior and familiar
interaction patterns carry the structure; identity lives in motion, typography, copy, and
micro-detail. Cover the logo: the screen must still read as Loox, not a generic settings app.

## The 10 DNA rules

### 1. One protagonist per screen
Every screen answers ONE question. Home = "find and use a credential instantly". Item detail =
"use this credential". Settings = "change this behavior". Anything not serving the protagonist
is demoted (smaller, lower, behind a menu) or cut. Before adding a section, name the screen's
protagonist out loud — if the new thing competes with it, it doesn't go above it.

### 2. Glass is for controls, canvas is for content
Liquid Glass / material surfaces only on control layers: bars, floating action clusters,
badges on tinted tiles. Content sits on the canvas. Cards exist only for true semantic
grouping (a set of fields, a list of recipients) — never because a designer didn't know how
to end a section. Prefer spacing + elevation over strokes; scroll content runs behind bars.

### 3. Concentricity — radius is a relationship
Nested rounded shapes use `Radius.concentric(outer:inset:)` (`R_inner ≈ R_outer − inset`).
Never pick a nested child's radius from the scale directly. Standalone shapes use the scale
(`Radius.xs/sm/md/lg/xl/pill`).

### 4. Typography is architecture
Only `vaultType` roles — a raw `.font(.system…)` or `.font(.title2.bold())` in feature code is
a defect. Secrets/codes/card numbers use `Font.vaultCode` (MonoLisa); labels stay SF; never
mono the whole app. OTP renders grouped (`381 942`) as a typographic object, not body text.

### 5. Motion explains spatial relationships (Controlled Reveal)
The product physics is **reveal / conceal**. Every hidden↔visible change uses the shipped
vocabulary (see `design-guidelines.md → Loox Motion Language`): glyph resolve for secrets,
blur-away unlock, contract-in lock, ∞ gate draw while deriving, clipboard morph on copy.
No decorative "wow" animation. Motion NEVER gates or delays a security result. Every effect
collapses to an instant swap under Reduce Motion.

### 6. One-handed ergonomic hierarchy
Frequency map: F0 (every session: search, open item) and F1 (copy password/username, OTP)
live in the thumb zone or as full-row tap targets. F2 (add, edit) may sit higher. F3 (export,
delete, move vault) belongs behind menus. Hit targets ≥ `Metric.hitMin` (44pt) — a small
glyph button gets an invisible padded hit area, never a 20pt tap target.

### 7. Progressive disclosure
Layer A (immediate): title, username, password, OTP. Layer B (contextual): website, notes,
attachments. Layer C (management): history, metadata, tags, delete — behind menus or below
the fold. A normal user should almost never SEE layer C. Destructive actions appear exactly
once per screen, in the menu, with confirmation.

**Action hierarchy — no button walls.** A screen or sheet state shows at most ONE filled
primary action plus at most one quiet secondary (text or tinted style). Three or more stacked
buttons is a defect: rank the actions by the frequency map, keep the top one primary, demote
the rest into a menu, a share sheet, the toolbar, or the next step of the flow. Button size
follows rank — primary is full-width `controlLarge`; a secondary never visually outweighs the
primary; two adjacent buttons never differ in size or style without a rank reason. Completion
screens (link created, share sent, kit generated) are the classic offenders: the user's next
action is almost always exactly one thing — design for that one thing.

### 8. Personality lives in micro-detail — "calm intelligence"
Copy is short, still, confident. Never exclamation marks, never emoji cheerleading, never
em-dashes ("—") in UI strings, and never interpunct separators ("·") — separate ideas with
real layout (two lines, label+value) or real words, not typographic glue. Copy never lies
("Copied" — not "Copied securely"; the clipboard isn't secure). Every string ships EN + VI
together; VI is a first-class rendering (longest labels — design for VI first).

### 9. Physics: Controlled Reveal
"Nothing is exposed before it needs to be." Masked by default, fixed-length masks (never leak
secret length), reveal is local and deliberate, conceal is instant. New surfaces holding
secrets must justify any default-visible value.

### 10. Search is a superpower, not a text field
Zero-state works (recents + quick filters). Query grammar understands local operators
(2fa/weak/reused/passkey/categories, EN+VI, diacritic-insensitive keywords) that only narrow
the already-scoped pool. A recognized keyword must never make results worse than plain text —
zero-result operator readings fall back to literal search. No AI, no network in search.

## Haptics vocabulary

One physical event = one haptic, from the SERVICE layer, never doubled by a view.

| Event | Haptic |
| --- | --- |
| Copy to clipboard | `Haptics.success` (fired by `ClipboardService` — views never add another) |
| Destructive confirm, auth failure | `Haptics.error` |
| Risky state entered (e.g. reveal extra-protected) | `Haptics.warning` |
| Selection / toggle / minor action | `Haptics.tap` |
| Scroll, navigation, appear | none |

## Multi-device acceptance matrix

A screen passes only if it renders correctly in ALL of:

- **Widths**: iPhone SE (375pt) and Pro Max (430pt) — no truncated VI labels, no squeezed
  grids; if 4 don't fit, use 2×2; test with the LONGEST localized string, which is usually VI.
- **Dynamic Type**: default, XL, and accessibility XXL — text scales without clipping;
  `minimumScaleFactor` only as a last resort and never below 0.7; layout reflows (grids →
  fewer columns) rather than shrinking text into illegibility.
- **Appearance**: light AND dark — no white-on-white / invisible-after-theme-switch; semantic
  roles only (`themedForeground`, `theme.color(role)`), never raw `.white/.black/.gray`.

  **Documented exemptions** (do not re-flag in reviews): camera/QR/favicon surfaces and literal
  light-dark preview swatches; the fixed decorative quick-action glyph tints (soft-chip
  style since 260711 — labels use text roles); the Settings icon badge tiles
  (`SettingsIconBadge` — white glyph on fixed system-Settings hues, user-granted 260711);
  SF Symbols for Apple-platform notions Polaris has no honest glyph for (the `icloud`
  family wherever the iCloud feature appears — Settings badge, Sync screen, passkey
  backup badge) and for Polaris glyphs that distort at badge scale (`envelope.fill`
  for Private Email; both user-granted 260711);
  native UISwitch/system-control chrome (the OS draws it); ambient shadows built from black
  opacity (that is how `Elevation` works by design); proportional avatar/tile corner radii that
  scale with the tile size (a size-relative pattern, not a magic number); SF Symbols inside the
  PAYMENT CARD context only (user-granted 260711 — `creditcard` etc. read better there; brand
  identification uses the SELF-DRAWN generic mark tiles in `Assets.xcassets/CardBrands`
  (user-approved 260711), never an actual third-party logo asset).
- **Accessibility**: Reduce Motion (instant swaps), Reduce Transparency (solid fallbacks),
  VoiceOver (meaningful labels; decorative views hidden).
- **Locales**: EN and VI both rendered and eyeballed.

## The adversarial protocol (how to review a screen)

For every screen, answer in writing — "it looks fine" is not an answer:

1. **Protagonist**: what is this screen's one job? Does the first glance serve it? What here
   competes with it, and why hasn't that been demoted?
2. **Every text**: read each string aloud in EN and VI. Is it calm, honest, shorter than it
   could be? Does it use "·", "—", "!"? Does VI fit at SE width?
3. **Every control**: can a thumb hit it one-handed? Is its hit box ≥44pt? Is its purpose
   obvious without the label? Does it give feedback (visual + correct haptic)?
4. **Every space and shape**: is each padding a `Space` token? Each radius from the scale or
   `concentric`? Does anything look pinched, flared, or floating unanchored?
5. **Every state**: empty, one item, many items, loading, error, locked/gated — does each
   state look intentional, or does one of them expose the layout's scaffolding (duplicate
   sections, stranded rows, dead ends)?

File the answers per screen in the active plan's report; fixes reference the failing check.
