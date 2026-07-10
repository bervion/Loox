# Shared-component requests (for Phase 1 / orchestrator — components are frozen, W2 phases cannot edit)

## From Phase 5 (Item Detail + Passkeys)

**Request:** a compact/inline themed button style for secondary actions placed next to a row
label (e.g. `LocatedInSheet`'s "Move" button, next to the current Space's folder badge).

**Why:** `ThemedProminentButtonStyle` / `ThemedTintedButtonStyle` / `ThemedDestructiveButtonStyle`
(`DesignSystem/Components/ThemedButtonStyles.swift`) all force `.frame(maxWidth: .infinity)` —
full-width block buttons. There is no themed style for a small inline pill button, so
`LocatedInSheet` currently falls back to native `.buttonStyle(.bordered).tint(env.theme.active
.color(.accent))`, which works (WCAG-compliant tint, system-accessible sizing) but bypasses the
DS button-style layer entirely — a "one-off style inside a feature screen" per
`docs/design-guidelines.md`'s non-negotiable rules.

**Suggested shape:** `ThemedCompactButtonStyle` (or similar) — same `theme.accent`/
`theme.controlBackground` semantics as `ThemedTintedButtonStyle`, but sized to content
(`Space.s4` horizontal padding, `Space.s2` vertical, `Radius.sm`) instead of `maxWidth: .infinity`,
with a `Metric.hitMin`-floor on the tap target for short labels.

**Not blocking:** left as `.bordered` for now (Phase 5 does not own `DesignSystem/Components/*`);
low severity, deferred.

## From Phase 9 (Appearance + About)

**Request:** a `VaultType` role (or a separate `Font.vaultDisplayNumeral` helper) for large
decorative numerals — e.g. `AboutView.promiseCard`'s "1 / 2 / 3" badge numbers, currently
`.font(.system(.largeTitle, design: .rounded)).fontWeight(.heavy)` inline (fixed this pass from a
non-scaling fixed-pixel size, but still a raw `.font(.system(...))` call site, not routed through
`vaultType`). `Typography.swift`'s existing roles are all `SF`/default-design; there's no rounded,
heavy, oversized "watermark numeral" role, and `ItemThumbnail.swift`'s monogram-letter font
(`.font(.system(size: size * 0.42, weight: .semibold, design: .rounded))`, proportional to its
container) suggests this "rounded decorative glyph" need recurs elsewhere too.

**Suggested shape:** add a `case displayNumeral` (or similar) to `VaultType` →
`.system(.largeTitle, design: .rounded).weight(.heavy)`, so both this and any future oversized
decorative digit/glyph route through the same token instead of each screen hand-rolling the
`.system(.largeTitle, design: .rounded)` + `.fontWeight(.heavy)` pair.

**Not blocking:** the current inline call is Dynamic-Type-scalable (uses `.largeTitle` text style,
not a fixed point size) so it already meets the accessibility bar; only the "not routed through
`vaultType`" grep-cleanliness point remains. Low severity, deferred to Phase 1/15.
