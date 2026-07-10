# Phase 13 — Main shell + Mac surfaces

**Status**: pending · **Wave**: W2 · **Owns**: `Main/*`, `Vaultify/App/RootView.swift` (route transitions + PrivacyShield — presentational only, NEVER alter lock/wipe logic), `Vaultify/App/VaultifyApp.swift` (review-light) (16 surfaces).
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
The shell = "get me to the right tab/space without thinking". It frames every screen; its defects are
felt everywhere.

## Cluster hotspots
- **MainTabView / VaultTabBar / VaultTabBarBackground / VaultTabItem**: native `TabView`, icon-only, outline↔
  filled on active; iOS 18+ Search `role: .search`; iOS 17.6 classic `.tabItem` fallback. Verify tab
  VoiceOver labels localized EN+VI (icons carry no visible label); active-state contrast in light+dark; no
  raw colors; glass only on the bar (rule 2). Do NOT restore custom shell overlay (CLAUDE.md: latency).
- **AdaptiveRootView / VaultShellBehaviors**: route + size-class switching; verify Privacy Shield (App
  Switcher material + logo) fades correctly and hides content; UI-state restoration path presentational-safe.
- **Mac surfaces** (`MacRootView / MacSidebarList / MacItemListColumn / MacHeaderBar / VaultSidebarList /
  VaultSidebarView`): sidebar + column + header. Verify tokens (not raw colors) on Mac chrome, keyboard/hover
  states legible, header controls ≥44 equivalent, and they compose the SAME feature screens (no forked visual
  language). Mac is secondary — flag but don't over-invest; SE/Pro-Max iPhone parity is the priority.
- iOS 26 Liquid Glass: any custom glass guarded `#if compiler(>=6.2)` + `#available(iOS 26,*)` with
  material/solid fallback; never glass on content rows.

## Deliverables / Todo
`reports/findings-phase-13.md` · `strings-manifest-phase-13.md` · fixes.
- [ ] Protocol answers (14). [ ] 6 greps. [ ] Tab VoiceOver labels EN+VI. [ ] Active-tab contrast light/dark.
- [ ] Privacy Shield hides content. [ ] Mac chrome token-clean. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; tab bar labels localized + accessible; no raw colors in shell/Mac chrome; glass
guarded; EN+VI. Risk: shell changes affect the WHOLE app + prior latency lesson (Med×High) — do NOT reintroduce
custom overlay/indicator motion; keep native TabView; presentational token fixes only.
</content>
