---
name: vaultify-design
description: Use this skill to generate well-branded interfaces and assets for Vaultify, the secure Apple-native iOS password manager, either for production or throwaway prototypes/mocks. Contains design guidelines, color & type tokens, Polaris iconography, and a full iOS UI kit (vault, item detail, watchtower, unlock, live theming).
user-invocable: true
---

Read the `readme.md` file within this skill first, then explore the other files.

Vaultify is a calm, private, Apple-native iOS password manager. Build with: semantic color tokens (never raw colors), SF Pro / SF Mono type, the 4pt spacing grid, Polaris icons (recolored via tokens — never SF Symbols, never emoji), soft ambient elevation, restrained native motion, and a custom icon-only floating tab bar. Liquid Glass is for the control layer only. Support light, dark, increased contrast, reduced transparency, reduced motion — and live theme/accent switching with no desync.

Key files:
- `styles.css` → links every token file (`tokens/*.css`).
- `components/core/*` → reusable primitives (Button, Row, IconTile, Field, Switch, TabBar, StrengthMeter, Badge, Icon, …) with `.d.ts` + `.prompt.md`.
- `ui_kits/ios-app/` → interactive iPhone recreation; read these for full-screen composition patterns.
- `guidelines/*.card.html` → foundation specimens (colors, type, spacing, icons).

If creating visual artifacts (slides, mocks, throwaway prototypes), copy assets/tokens out and produce static HTML the user can view. If working on production SwiftUI code, copy the rules and tokens here to design as an expert in this brand, and reconcile token names against the app's theme files.

If invoked without guidance, ask what the user wants to build, ask a few focused questions, then act as an expert Vaultify designer who outputs HTML artifacts or production-ready guidance.
