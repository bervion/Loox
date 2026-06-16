# Changelog

## [1.2.0] - 2026-06-17

### Added
- Standardize UI with token system and native tab bar
- adopt Icon Composer app icon and brand mark

### Fixed
- theme-consistent UI, WCAG accent contrast, reactive surfaces

### Changed
- ```
- add standardized home theme demo screenshots


## [1.1.2] - 2026-06-14

### Added
- honor Reduce Transparency + document theme subsystem
- custom theme editor + .vaultheme import/export (Phase 06 UI)
- migrate buttons to themed style + theme secure field; fix dark-theme scheme
- theme ItemDetail + Generator screens (app-wide theming complete)
- apply themed components app-wide
- themed component library + procedural pattern wallpapers
- wallpaper behind Items & Watchtower lists (floating cards)
- animated mesh wallpaper (CAKeyframeAnimation morph) + triggers
- Appearance settings UI (theme/accent/wallpaper/auto-night/text size)
- mesh renderer/math, settings mutators, .vaultheme codec + tests
- wallpaper engine + apply to lock & onboarding
- theme the AutoFill extension + share Color(rgb:) in core
- theme engine core — shared model, store, accent recolor, auto-night, migration
- News-style search — searchable on TabView + Tab(role: .search)
- dedicated Search tab circle on iOS 18 + icon-only tab bar
- nav redesign — Home/Items/Watchtower/Search tabs + pin/archive
- foundation for nav redesign — pinned/archived/useCount + icons
- space badges, header filter, and smart search
- default "My Vault" space, Settings entry, refine Home Spaces UX
- folder/tags in CSV+backup, CloudKit folder sync, EN/VI i18n
- Spaces and tags UI — editor, pickers, Home dashboard
- folders (Spaces) and tags data model + repository

### Fixed
- force window interface style so sheets follow the theme
- live label updates in sheets + theme-aware glowing patterns
- sanitize dark-primary+auto-night (fixes dark labels); theme picker grid
- theme every list row app-wide (pixel-perfect cell harmony)
- theme list/form cells to harmonize with the theme (Telegram parity)
- legible themed placeholder; migrate surfaces app-wide; theme crossfade
- drop private UIView.animationDurationFactor() in mesh morph
- standard Search tab and retuned tab icons
- minimize search into a floating button via searchToolbarBehavior (iOS 26)
- detach search tab — Tab(value:role:.search) with no title/image
- standard iOS 26 search tab — drop programmatic selection so role .search detaches
- drop tab-bar appearance override that broke the iOS 26 Liquid Glass bar
- align Home dashboard rows with item cards
- dashboard cards use Buttons so List adds no disclosure chevrons
- show items on Home grouped by category under the dashboard

### Changed
- migrate signing to shared bervion-ios-certificates match repo
- migrate text colors to themedForeground (tinted/custom precision)
- refine plan — Telegram-faithful CPU mesh + AutoFill theming
- plan to port Telegram theme + wallpaper engine
- add memory entry for VaultifyTests unit-test target
- use SVG sources for Polaris icons
- add Vietnamese for tag title format string
- document folders and tags; plan artifacts
- add unit-test target and organization tests


## [1.1.1] - 2026-06-14

### Added
- add app-theme selection step before biometrics
- app-icon splash, launch screen, and lock-screen logo

### Fixed
- background-only launch screen to stop square-logo flash
- evaluate biometrics when enabling unlock so Face ID actually triggers

### Changed
- Vietnamese for new onboarding strings; mandate localization
- declare exempt encryption to skip ASC compliance prompt


## [1.1.0] - 2026-06-14

### Added
- add fastlane match + GitHub Actions TestFlight pipeline
- enable AutoFill Credential Provider entitlement on app target
- add passkey support to the AutoFill extension
- publish login identities to ASCredentialIdentityStore
- add AutoFill credential provider extension (passwords)
- extra field protection, attachments, and Vietnamese localization

### Fixed
- auto-select newest Xcode on runner for project format 110
- resolve concurrency, deprecation, and asset-symbol warnings

### Changed
- add README and project CLAUDE.md (dev workflow, Tuist, release)
- generate Xcode project with Tuist
- Xcode project tweaks (app category, extension debug scheme)
- add shared schemes for Vaultify app and AutoFill extension
- extract VaultifyCore shared layer for AutoFill reuse
- add Xcode .gitignore and untrack per-user xcuserdata
- update app icon assets
- Implement native SwiftUI rewrite of Vaultify iOS app
- Initial Commit
