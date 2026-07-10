# Phase 9 — Strings Manifest (Appearance + About)

No new or changed user-facing strings. All fixes in this phase were token/font-reference swaps
(`.font(.caption)` → `.vaultType(.caption)`, `.font(.subheadline.weight(.medium))` →
`.vaultType(.subhead).fontWeight(.medium)`, a fixed-pixel numeral font → a Dynamic-Type-scalable
`.system(.largeTitle, design: .rounded)`), a raw `Color.primary` ring → a semantic theme role, 2
off-grid `.padding(.vertical, 6)` → `Space.s2`, a sub-44pt swatch tap target padded to ≥44pt, and 5
added `Haptics.tap()`/`Haptics.selectionTick()` call sites — zero visible copy change.

Existing copy reviewed for tone (calm, no "!", no "—", no "·") across all owned surfaces
(AppearanceSettingsView, AutoNightSettingsView, AboutView) — pass. AboutView's storytelling copy
(hero/refusal-block/promises/protection/privacy/footer) was read in full, EN source only checked
here (VI companions are pre-existing catalog entries from the prior shipped pass, not re-verified
key-by-key since no key changed).

| key | EN | VI | context |
|---|---|---|---|
| — | — | — | none this phase |
