# Changelog

## [1.7.0] - 2026-07-02

### Added
- backup-status badge + favicon on passkey detail
- credential exchange mapper + service (iOS 26.1, dormant)
- largeBlob extension support (iOS 18) + AAGUID registry note
- add management and silent upgrades
- deepen ios passkey integration

### Changed
- add phase 1-5 implementation review report
- mark chunk 2 complete
- cover backup and envelope hardening


## [1.6.0] - 2026-06-25

### Added
- import otpauth:// setup links (verification-code provider)
- 2FA one-time-code AutoFill (iOS 18+)

### Changed
- extract shared UnlockGate from the three flows


## [1.5.0] - 2026-06-25

### Added
- native save + strong-password generation (iOS 26.2+)
- Face ID unlock + create-login in extension
- mask secret field when unfocused, drop reveal eye toggle
- profile screen, syncable avatar, removal gate UI
- onboarding step seeds the default identity
- single-active default-identity invariant
- add synced default-identity + avatar columns and identity fields

### Fixed
- only show save prompt at form submission

### Changed
- journal — Face ID + create-login session lessons
- journal — sync schema reversal lesson
- document identity & profile in codebase-summary
- mark phase 4 complete; plan done
- mark phase 3 complete
- mark phases 1-2 complete; finalize sync-gate decision
- identity & profile plan with red-team/validate reports


## [1.4.1] - 2026-06-19

### Added
- Implement shake to lock and refine auto-lock UX


## [1.4.0] - 2026-06-19

### Added
- redesign item header + dark-mode neutral tint


## [1.3.1] - 2026-06-18

### Added
- adopt native Tab(role:.search) and fix header localization
- redesign empty-vault state with accent-soft lock emblem

### Fixed
- lock instantly on background to avoid lock-screen jump on return

### Changed
- SF font for emergency-kit and regenerate-kit views
- use SF everywhere, drop monospaced typeface


## [1.3.0] - 2026-06-18

### Added
- Liquid-Glass header action cluster (search/add/more) + ic_page_add
- strength card animates in sync with the gauge (no delay)
- TimelineView-driven gauge — reliable spin intro + safety colours
- 1Password-style animated score gauge + hero reveal
- rebuild Home tab to the Design System spec
- reshape to Design System — ScoreRing, strength card, issue categories
- password-rotation reminders with local notifications
- simplify to Design System palette — 7-preset accent, flat backgrounds

### Fixed
- smaller native large title, Watchtower quick-add +, Items collapse header
- scrollable rows, native large-title collapse, tighter HIBP spacing
- ticks on their own layer (never vanish) + fill-coloured needle
- triangle needle in the ring interior + animated tick sweep
- visible needle marker, ticks on top of fill, spring swing
- use grouped background on canvas screens so cards stand out
- match Home layout so the list aligns with the large title
- icon-tile badges for categories/tags/archive rows; align list to gutter
- Add buttons present an item-type menu instead of forcing login
- add missing VI (strength a11y label, HIBP description); normalize catalog format

### Changed
- improve UI
- one reusable VaultScreenHeader for all tabs + real Polaris page-add
- Threads-style fixed headers — moderate title, no collapse, consistent
- session entry for DS theme + Home/Watchtower work
- mark all 8 phases complete
- sync CLAUDE.md + guidelines + codebase-summary to DS theme/Home/Watchtower
- mark phases 1-3 + 6 complete; cook progress + M1 follow-up
- add DS Home/Watchtower + theme-simplify plan


## [1.2.1] - 2026-06-18

### Changed
- update design


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
