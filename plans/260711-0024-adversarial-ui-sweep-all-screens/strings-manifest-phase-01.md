# Phase 1 — Strings Manifest (Shared Primitives)

No new or changed user-facing strings. All fixes in this phase were token/font-reference swaps
(e.g. `.font(.headline)` → `.vaultType(.headline)`, default-size literal → existing `Metric` constant)
with zero visible/textual change — nothing to append to `Localizable.xcstrings`.

Existing copy reviewed for tone (calm, no "!", no "—", no "·") across all 40 owned surfaces: pass.
The one pre-existing catalog string referenced by two components in scope (`GlyphResolveText`,
`SpoilerText`) — "Hidden value" — was verified already present with an EN source and a VI
translation ("Giá trị ẩn").

| key | EN | VI | context |
|---|---|---|---|
| — | — | — | none this phase |
