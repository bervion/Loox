# Phase 5 findings — Item Detail + Passkeys

17 findings across 16 owned surfaces (+ `SharedAccessGateView`, present in `ItemDetail/` but
missing from the phase-00 16-count — included here for completeness), 15 fixed (4 high, 7
medium, 4 low), 2 deferred (shared-component gap, cross-phase haptics gap). Compile green
(app + AutoFill extension). No new/changed user-facing strings — every fix is code/logic
(color, font, spacing, radius, haptics, hit-target); `strings-manifest-phase-05.md` is empty
by design.

Confirms phase brief's expectation: ItemDetail's Controlled-Reveal-owned surfaces
(`DetailFieldRow`, `BottomCopyPasswordCluster`, `ItemDetailScreen`'s reveal/copy paths,
`SharedAccessGateView`) pass clean — the regressions found live in the OLDER, untouched-by-
that-pass files (`ProtectedFieldRow`, `AttachmentFieldRow`, `LocatedInSheet`, `LargeTypeView`)
plus the Passkeys cluster (never touched by Controlled Reveal at all).

## Findings

| Surface | Protocol Q(1-5) | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|
| TOTPFieldRow (`CountdownRing`) | Q4 tokens | `progressColor` "plenty of time" branch returns raw `Color.accentColor` (asset-catalog static), not the live theme accent — ring shows the wrong/stale color after switching one of the 7 accent presets | `env.theme.active.color(.accent)` | High | Fixed |
| AttachmentFieldRow | Q4 tokens | Leading icon tile fill + glyph use raw `Color.accentColor` — same live-theme desync as above | `env.theme.active.color(.accent)` | High | Fixed |
| ProtectedFieldRow | Q3 controls/feedback | Extra-Protection reveal (Level-2 or custom code) crosses the "risky state" boundary the phase brief names explicitly, but fired no haptic at all | `Haptics.warning()` in `revealLevel2(with:)` and `revealCustom(_:)` success paths | High | Fixed |
| ItemPasskeysSection / SharedItemPasskeysSection | Q4 tokens, Q2 (n/a) | Card overlay used raw `Color.black`/`Color.white` strokeBorder (no documented exemption applies — not a preview swatch); also the only cards on this screen with no `.elevation()`, inconsistent with `fieldsCard`/`sharingSection`/`trashCard` on the same `ItemDetailScreen` | Removed raw-color border, added `.elevation(.level1)` to match the screen's own card convention (also drops the now-unused `colorScheme` env var) | High | Fixed |
| DetailFieldRow / ProtectedFieldRow / AttachmentFieldRow | Q3 hit target | "•••" field menu trigger is a 30×30pt circle — below `Metric.hitMin` (44pt); same pattern already fixed elsewhere in the app (`EditorFieldRow`'s scan-QR button) | Wrapped each with `.frame(width: Metric.hitMin, height: Metric.hitMin).contentShape(Rectangle())`, visual circle unchanged | Medium | Fixed |
| ItemDetailScreen (Move to Trash / Delete Permanently / Leave Share) + PasskeyDetailSheet (Delete Passkey) | Q3 feedback | Destructive confirmations fired no haptic — vocabulary maps "destructive confirm" to `Haptics.error` | Added `Haptics.error()` at the top of each confirm-button action (4 sites) | Medium | Fixed |
| AttachmentFieldRow, ProtectedFieldRow, ProtectFieldSheet, CodePromptSheet, LocatedInSheet, LargeTypeView | Q4 typography | ~15 raw `.font(.body/.caption/.caption2/.subheadline/.footnote/.title3.bold)` sites instead of `.vaultType`/`Font.vaultCode` | Converted to `.vaultType(...)` roles; the Large-Type OTP pill's live code now uses `.vaultCode(.title3, weight: .semibold)` to match `TOTPCodeView`'s canonical OTP treatment (OTP = typographic object, rule 4) | Medium | Fixed |
| AttachmentFieldRow | Q4 tokens | `meta.name` `Text` had no `.themedForeground()` — fell back to raw system `.primary`, out of step with custom (tinted/Night) themes | Added `.themedForeground()` | Medium | Fixed |
| ItemDetailScreen (tags row) | Q4 spacing | Tag chip used raw `10`/`6`/`8` instead of the 4pt grid, diverging from the `FilterChip` sibling's `Space.s3`/`Space.s2` pill padding | Matched `FilterChip`'s padding/spacing tokens | Low | Fixed |
| ItemDetailScreen (loading / not-found states) | Q4 spacing | Raw `.padding(.top, 120)` / `.padding(.top, 80)` | Composed from `Space` tokens: `Space.s10+Space.s9+Space.s2` (=120), `Space.s9+Space.s7` (=80) — exact, no visual change | Low | Fixed |
| LocatedInSheet ("No Space" placeholder tile) | Q4 radius | `RoundedRectangle(cornerRadius: 8)` magic number at a 30pt tile — sibling `FolderBadge`/`CategoryBadge` derive radius as `size * 0.28` | `cornerRadius: 30 * 0.28` (documented proportional-tile exemption, matches sibling exactly) | Low | Fixed |
| ItemDetailScreen (`shareRow`/`actionRow`) | Q4 spacing/typography | `padding(.vertical, 12/14)`, `HStack(spacing: 12)` raw numerics; `actionRow`'s label `Text` had no `.vaultType` | Normalized to `Space.s3`; added `.vaultType(.body)` | Low | Fixed |
| LocatedInSheet ("Move" button) | Q6 ergonomic | `.buttonStyle(.bordered).tint(...)` instead of a themed style — but `.themedTinted/.themedProminent/.themedDestructive` are all full-width block styles, unsuitable for this compact inline pill; no themed compact/inline button style exists | Not changed — filed to `reports/shared-component-requests.md` (needs a `ThemedCompactButtonStyle` or equivalent) | Low | Deferred |
| DetailFieldRow (Reveal/Conceal menu item), header pin/favorite toggles | Q3 feedback | No `Haptics.tap()` on toggle — vocabulary maps "selection/toggle" to `.tap` | Not changed — this is a pre-existing, app-wide pattern (same gap on Home's pin/favorite, not unique to Phase 5); fixing only here would be inconsistent without a coordinated pass. Flagged for Phase 15's consolidated haptics audit | — | Deferred |
| SharedAccessGateView | Q1 protagonist, Q5 states | Walked all 6 states (not-granted/device-scoped, authorized, offline, verifying, unavailable+Try Again, revoked) — each renders a distinct, intentional card; `content()` is only ever evaluated inside `.authorized` (`@ViewBuilder` laziness — INV-01 confirmed, not touched); decorative icons already `accessibilityHidden` via `PolarisIcon` itself | none | — | Pass |
| DetailFieldRow / BottomCopyPasswordCluster / ProtectedFieldRow / LargeTypeView (copy paths) | Q3 feedback | Verified no view fires its own copy haptic — every path routes through `env.clipboard.copy(...)`, which is the sole `Haptics.success()` call site (`ClipboardService.swift`); zero doubling found | none | — | Pass |
| AttachmentFieldRow ("EXT, size" line) | Q2 copy | Phase brief flagged a `·` interpunct hotspot here — already resolved (renders `"\(ext), \(size)"`, comma not middot); confirms the earlier Controlled-Reveal-adjacent cleanup already landed | none | — | Pass |
| PasskeyDetailSheet (Delete Passkey copy) | Q2 copy | "This permanently destroys the private key and cannot be undone." — honest, no `!`/`—`/`·`, matches phase brief's exact ask | none | — | Pass |
| ItemDetailScreen / PasskeysScreen / PasskeyDetailSheet | Q1 protagonist, Q7 layer | Destructive "Move to Trash" appears once, in the "…" menu (Layer C); Passkeys empty state, quarantine banner, and grouped-by-site list are each intentional, no stranded layout | none | — | Pass |

## 6 audit greps (final state, `Vaultify/Features/ItemDetail` + `Vaultify/Features/Passkeys`)

1. **SE-width/Dynamic Type** (`frame(width:`/`GeometryReader`/`minimumScaleFactor`/`lineLimit(1)`): all remaining hits are icon/badge tiles (30/44/26/9pt fixed glyph containers, not text) or intentional truncation (`lineLimit(1)` + `.truncationMode`); one `GeometryReader` is the password-row frame-reporting preference key (layout-neutral). Clean.
2. **Typography** (`.font(.` not `.vaultCode`): 0 remaining (was ~15).
3. **Radius** (`cornerRadius:` numeric): 1 remaining — `LocatedInSheet`'s `30 * 0.28`, the documented proportional-tile exemption (matches `FolderBadge`/`CategoryBadge`). Clean.
4. **Spacing** (raw numeric `.padding(`): 0 remaining (was 6).
5. **Hit target** (small tappable glyphs < 44pt): 0 remaining — all three "•••" menu triggers now carry a padded 44×44 hit frame around the 30pt visual circle.
6. **Haptics** (cross-checked against vocabulary, no doubling): copy paths all single-fire via `ClipboardService`; risky-reveal now fires `.warning`; destructive confirms now fire `.error`; `LargeTypeView`'s cell-mark keeps its existing `.tap`. Two gaps knowingly deferred (toggle `.tap`, compact-button component) — see table above.

## Deferred / cross-phase notes

- Shared-component request filed (`ThemedCompactButtonStyle` for inline pill actions) — see `reports/shared-component-requests.md`.
- Reveal/Conceal + pin/favorite toggle haptics: app-wide gap, not Phase-5-specific; recommend Phase 15 sweep it once across all phases rather than partial per-phase fixes.
- Dynamic Type AX-XXL on `DetailFieldRow`'s trailing cluster (strength badge + countdown ring + copy glyph + menu, `HStack(spacing: 10)`): static-analysis only this session (no simulator screenshot capability used) — no fixed frame blocks text growth except the icon glyphs (which don't scale by design); assessed low risk, added to the Phase 15 manual device-QA checklist rather than guessed at blind.

**Status:** DONE
**Summary:** 16 owned surfaces (+1, `SharedAccessGateView`) reviewed against the adversarial
protocol; 15 findings fixed (4 high — live-theme-color desync ×2, missing risky-reveal
haptic, raw-color/inconsistent card treatment; 7 medium — hit targets, missing destructive
haptics, raw typography, missing themedForeground; 4 low — spacing/radius tokens), 2 deferred
(shared-component gap, cross-phase toggle-haptic gap). SharedAccessGateView's 6-state gate and
INV-01 (secrets never render pre-authorization) verified unchanged — presentational-only, no
gating logic touched. Compile green (app + AutoFill extension, `tuist generate` + `xcodebuild`
Debug/iOS Simulator). No `Localizable.xcstrings` changes needed.
