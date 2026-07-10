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
