# Phase 7 — Watchtower + Generator: Findings

Scope: 10 surfaces across `Vaultify/Features/Watchtower/*` (`WatchtowerScreen`,
`WatchtowerScoreRing`, `WatchtowerStrengthCard`/`WatchtowerStrengthBar`,
`WatchtowerCategoryScreen`, `WatchtowerComponents` — `PressableSurfaceStyle`, `CategoryRow`,
`IconTileBadge`, `CountBadge`, `WatchtowerIssueRow`) and `Vaultify/Features/Generator/*`
(`GeneratorScreen`, `PasswordGeneratorSheet`, `PasswordGeneratorView`), per
`reports/phase-00-surface-registry.md` Phase-7 rows. Method: `docs/design-dna-standard.md`
adversarial protocol Q1-5 + the 6 audit greps.

Protagonists: Watchtower = "what should I fix, in order"; Generator = "produce a strong value
and use it now."

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| `WatchtowerScreen` (content ordering, header) | WatchtowerScreen.swift | Ring first (hero), "To fix" list ordered Compromised→Reused→Weak→2FA, HIBP toggle demoted to bottom — nothing competes with "what to fix next" | copy calm, no `!`/`—`/`·`; header "Add Item" menu is byte-identical to `ItemsScreen`'s already-passed pattern (Phase 4) | Add-menu 44pt hit target — pass (matches Phase-4 precedent) | tokens throughout | **empty-vault state (0 items) fell through to `issueSection` with zero rows — a hollow "To fix" card (header + hairline card, no content)**, because `allClear` required `analyzedCount > 0` and no other branch caught `analyzedCount == 0` | added a distinct `emptyVault` check + `emptyVaultView` (icon + "Add a password to see your vault's security score.") ahead of the `allClear`/`issueSection` branch | high | fixed |
| `WatchtowerScreen.runHIBP` (breach detail string) | WatchtowerScreen.swift:361 | n/a (data, not UI text per se, but rendered verbatim in `WatchtowerIssueRow`) | **`detail: "Seen \(count) times in breaches"` was a plain Swift string interpolation — never routed through `appString`/`String.LocalizationValue`, so it always rendered in English regardless of the in-app language, and had no catalog entry at all (not even EN)** | n/a | n/a | only appears once pwned items exist | wrapped in `appString(...)`; new key added to strings manifest (EN+VI) | high | fixed |
| `WatchtowerScoreRing` (gauge fill/needle/label) | WatchtowerScoreRing.swift | 270° hero gauge, counts up then settles | band label "Fairly secure"/"Needs attention"/"At risk" calm, EN+VI present | n/a (decorative Canvas) | **the safety-gradient (red→amber→green) was three FIXED hex triples (`dangerRGB`/`warnRGB`/`safeRGB`) baked into the file — not routed through `ThemeRole`, so a custom accent/dark-mode theme's actual `destructive`/`warning`/`success` never reached the ring; `dangerRGB` happened to equal the *light* theme's `destructive` (0xE5484D) exactly, confirming this was copy-pasted from the theme and never wired live** — exactly the risk called out in the phase brief | rewrote `safetyColor` to blend `theme.destructive`→`theme.warning`→`theme.success` via `RGBMath.blend` (same math the theme engine itself uses for accent recolor); band **label** text now uses the discrete `theme.color(band.role)` instead of the continuous blend, so it always matches its own 50/80 thresholds exactly | high | fixed |
| `WatchtowerScoreRing` (VoiceOver) | WatchtowerScoreRing.swift | n/a | n/a | VoiceOver: accessibility label read only the number ("Security score: 82"), never the qualitative band ("Fairly secure"/"Needs attention"/"At risk") a sighted user sees right below it | n/a | n/a | VoiceOver users missed half the information sighted users get | `accessibilityLabel` now appends `Text(band.label)` | medium | fixed |
| Reduce Motion (ring + strength bar) | WatchtowerScoreRing.swift, WatchtowerStrengthCard.swift | n/a | n/a | n/a | n/a | Reduce Motion → both already render the settled/final value instantly (`animating=false` short-circuits the `TimelineView`; `WatchtowerStrengthBar.grow()` sets `shown = value` directly) | verified per cluster hotspot — no change needed | none | — | pass |
| `WatchtowerStrengthCard`/`WatchtowerStrengthBar` (fill color) | WatchtowerStrengthCard.swift | "Overall password strength" progress readout | doc comment literally says "Solid success fill portion" | n/a | fill capsule was a raw hex (`Color(red: 0x22/255,…)`) instead of the theme role its own comment names | routed the fill capsule through `env.theme.active.color(.success)`; the 8-stop illustrative spectrum (the unfilled remainder, a fixed DS legend, not a per-item status) intentionally left as-is — it mirrors the reference design 1:1 and is not the thing the phase brief flagged | medium | fixed |
| `CategoryRow` (title truncation) | WatchtowerComponents.swift | one row per issue category, tap → drill-down | **the longest title is EN, not VI, here: "Set up two-factor authentication" (33 chars) vs VI "Bật xác thực 2 lớp" — `lineLimit(1)` on the title, combined with the icon tile + count badge + chevron eating ~120pt of the row, clips the EN string at SE (375pt) width even at default Dynamic Type** | icon tile / count badge / chevron all token-sized, row ≥ `Metric.rowHeight` | n/a | n/a | English title clipped mid-word at SE width | `lineLimit(1)` → `lineLimit(2)` on the title only (subtitle stays 1 line); row height is a min-height so it grows gracefully | medium | fixed |
| `PressableSurfaceStyle` nested in `ThemedCard(cornerRadius: Radius.lg)` | WatchtowerScreen.swift (`issueSection`), WatchtowerComponents.swift | cluster hotspot: verify concentricity after ThemedCard's default 16→20 bump | n/a | n/a | `CategoryRow`'s own pressed-background is a flat rectangle (`cornerRadius: 0`), nested inside the outer `Radius.lg` card | n/a | **verified, not a defect**: `ThemedCard` clips its *entire* content (rows + background) to the outer rounded rect in one `.vaultCornerRadius(cornerRadius)` pass, so the first/last row's flat corners are cropped to the card's curve automatically — no explicit concentric radius needed on the row itself | none | — | pass |
| `CategoryRow`/`CountBadge` micro-padding | WatchtowerComponents.swift:121, WatchtowerScoreRing.swift:231 | n/a | n/a | n/a | `.padding(.vertical, 3)` / `.padding(.top, 2)` — off the 4pt `Space` grid | n/a | grep-technically a violation, but this exact micro-nudge pattern (2–6px, not a `Space` multiple) is already pervasive and previously accepted across multiple **done** phases (`Home`, `ItemEditor`, `Unlock`, `Onboarding`) for baseline/kerning alignment, not layout spacing — fixing only these 2 sites would diverge from an app-wide convention, not resolve one | left as-is (documented convention, cross-phase, not unique to this phase) | low | deferred (documented convention) |
| `WatchtowerCategoryScreen` | WatchtowerCategoryScreen.swift | drill-down list for one category | k-anonymity `infoNote` calm, honest, EN+VI present | rows are system `List` rows (≥44pt) | `VaultColors.surface`/`.accent` — theme-resolved wrappers, not raw color | empty (0 issues — screen only reachable when count>0, so N/A)/1/many rows all render correctly | none | — | — | pass |
| `PasswordGeneratorView` output card (copy affordance) | PasswordGeneratorView.swift | tap value → copy, "Copied" flash | copy honest ("Copied", not "Copied securely") | copy row full-width tappable | **reinvented the clipboard-morph glyph by hand (`PolarisIcon(copied ? .copyDone : .copy)` swap, no crossfade) instead of the shared `CopyMorphIcon` primitive that `ItemDetail`'s `DetailFieldRow`/`BottomCopyPasswordCluster` already use for the identical interaction** (DNA rule 5: "clipboard morph on copy... don't reinvent") | replaced with `CopyMorphIcon(copied:size:)` (keeps the existing accent-flash background/"Copied" text swap, which is a deliberate, different-from-ItemDetail treatment for the primary generator output) | medium | fixed |
| `PasswordGeneratorView` copy toast | PasswordGeneratorView.swift | transient "Copied Password" confirmation | — | — | **hand-rolled an exact duplicate of the shared `Features/Components/CopyToastOverlay` component** (same icon, text, padding, material, elevation, transition — verbatim) instead of reusing it; its own `.animation(.spring(duration:0.3))` also never read `accessibilityReduceMotion` | replaced the local `copyToast` view with `CopyToastOverlay()` (removes ~14 duplicated lines); animation now gated `.vault(.spring(duration:0.3), reduceMotion:)` | medium | fixed |
| `PasswordGeneratorView` "Use Password" header button | PasswordGeneratorView.swift | feed the generated value back to the item editor and dismiss | "Use Password" a11y label fine, EN+VI present | **the confirm action fired zero haptic** — its sibling "Regenerate" button explicitly calls `Haptics.tap()` before its action, but "Use Password" called `onUse?(output); dismiss()` with no feedback at all (DNA protocol Q3: "does it give feedback (visual + correct haptic)?") | `Haptics.tap()` added before `onUse?(output)` | medium | fixed |
| `PasswordGeneratorView` accent-flash + reset timing | PasswordGeneratorView.swift:151,239-246 | n/a | n/a | n/a | `.animation(.easeOut(duration: 0.18), value: copied)` (no Motion token, no Reduce-Motion gate) and the 1.2s-sleep-then-`withAnimation(.easeOut(duration:0.3))` reset | n/a | grep-technically raw/ungated, but **byte-identical** to `ItemDetail/DetailFieldRow`'s already-passed copy-flash pattern (same 0.18/0.3 durations, same ungated `.animation`) — a deliberate, already-accepted micro-interaction outside the Controlled-Reveal vocabulary (color flash feedback, not reveal/conceal motion), not a fresh Generator-specific defect | left as-is (matches accepted cross-phase convention) | low | deferred (documented convention) |
| Slider haptics (Length/Words) | PasswordGeneratorView.swift | drag-to-set length/word-count | n/a | `Haptics.selectionTick()` (throttled ≤25Hz) while dragging + one `Haptics.tap()` "commit" on release — two distinct physical events (continuous drag vs. finger-lift), not a double-fire of the same event | n/a | length extremes (8/64, 3/10, 4/12) all reflow correctly in a `Form`, no fixed frames | none | — | — | pass |
| PIN mode (no strength meter) | PasswordGeneratorView.swift | n/a | n/a | n/a | n/a | verified intentional: `if mode != .pin { PasswordStrengthMeter(...) }` — a strength score on a 4-12 digit PIN would be noise | none | — | — | pass |
| `SecretColoring`/`Font.vaultCode` reuse | PasswordGeneratorView.swift | n/a | n/a | n/a | digit/letter/symbol coloring + monospace readouts (output value, slider counters) | n/a | verified: both already established, reused 1:1 from `ItemDetail`/`Unlock`/`ItemEditor` (done phases) — not reinvented | none | — | — | pass |

## Out-of-scope finding (flagged, not fixed — file ownership)

**`Vaultify/Services/Watchtower/PasswordAudit.swift:75`** — `detail: "Used by \(counts[password]!)
items"` has the exact same defect as the `WatchtowerScreen.runHIBP` one fixed above (plain Swift
string interpolation, never localized, zero catalog entry — confirmed missing via
`Localizable.xcstrings` grep). **Not fixed here**: `Services/Watchtower/` is not `Watchtower/*`/
`Generator/*` under `Features/` and is absent from `reports/phase-00-surface-registry.md` (it's
non-View logic, like the `UserActivityMonitor` exemption) — out of this phase's file ownership.
Flagging for the orchestrator/Phase 15: the "Reused passwords" category (visible whenever any two
items share a password — a common, not edge-case, state) always shows this raw English string to
VI users. Recommend a small follow-up task the same shape as this phase's own fix
(`appString("Used by \(count) items")` + one manifest entry).

## 6 audit greps — final state (owned files, post-fix)

```
1. SE-width / GeometryReader / minimumScaleFactor / lineLimit(1): all `.frame(width:)` sites are
   either Metric.hitMin (44pt tokens) or proportional (GeometryReader-scaled ring/bar, or a
   caller-supplied `size` on IconTileBadge — the documented "proportional tile" exemption).
   lineLimit(1) remaining: issue-row item title (user data, acceptable truncation), Generator's
   output value (long generated secret, acceptable — truncating a visible preview isn't a
   Controlled-Reveal masking concern). CategoryRow title raised to lineLimit(2) (fixed above).
2. Typography `.font(.`: only `.font(.vaultCode(...))` sites remain — the correct MonoLisa token
   for the score number, generator output, and slider counters (verified established convention,
   not reinvented). Zero raw `.font(.system…)`/`.font(.title2.bold())` etc.
3. Radius: all `RoundedRectangle(cornerRadius:)` use `Radius.md/xs` tokens or a caller-supplied
   token parameter; `IconTileBadge`'s `size * 0.28` is the documented proportional-tile exemption.
4. Spacing `.padding(`: 2 numeric literals remain (`.padding(.top, 2)`, `.padding(.vertical, 3)`) —
   reviewed and left per the cross-phase micro-nudge convention (see findings table).
5. Hit targets: header Add-menu (44pt, matches Phase-4 precedent) — pass. No new sub-44pt tappable
   glyphs found.
6. Haptics: 4 call sites in Generator (Regenerate=tap, Use Password=tap [newly added], slider
   selectionTick/prepareSelection/tap on drag+release) — vocabulary-correct, no doubling. Copy
   action fires zero explicit haptic in either file (`ClipboardService.copy` is the sole source of
   `Haptics.success` for both Watchtower's item-detail hop and Generator's output row) — correct
   per vocabulary ("views never add another").
```

## Raw-color grep: reviewed, one fixed, one documented exemption

- `WatchtowerScoreRing.swift` fixed hex safety-gradient → now theme-role blended (see findings
  table, high severity).
- `WatchtowerStrengthCard.swift` fill capsule → now `theme.color(.success)` (fixed); the 8-stop
  spectrum array is a fixed illustrative legend matching the DS `StrengthBar.jsx` reference 1:1,
  intentionally not theme-reactive (documented, not a defect).
- `VaultColors.surface`/`.accent` (WatchtowerCategoryScreen, Generator slider tint) — semantic
  theme-resolved wrappers already used app-wide, not raw SwiftUI colors.
