# Strings manifest — Phase 3 (Home protagonist)

New/changed user-facing strings introduced by `HomeScreen.swift`. Coordinate with the P1
owner of `Localizable.xcstrings` — this phase does not edit that file directly.

| Key (EN source) | EN | VI |
|---|---|---|
| `Recently Used` | Recently Used | Sử dụng gần đây |

## Context
- Section header for the new `recentlyUsedSection` in `HomeScreen.swift`, rendered via
  `homeSectionHeader(title: LocalizedStringResource("Recently Used").inAppLocalized)`.
- Sits between "Needs Attention" and "Favorites" in the reordered scroll — surfaces items by
  `lastUsedAt` (use-time), fed by `env.repository.recentlyUsed(folder:limit:)`.
- No other new strings were introduced in this phase — `profileRow`'s subtitle text was moved
  to an accessibility label only (already-localized `personaSubtitle` string, unchanged), and
  the quick-action labels ("Add Item", "Generate Password", "2FA Codes", "Watchtower") are
  pre-existing strings reused as-is.
