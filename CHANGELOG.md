# Changelog

## [1.22.3] - 2026-07-09

### Fixed
- retry recipient profile publish instead of burning breadcrumb


## [1.22.2] - 2026-07-08

### Fixed
- refresh signed documents from app lifecycle, not a feature screen
- reliable share accept detection + pending visibility


## [1.22.1] - 2026-07-08

### Fixed
- set assertionRequired=true to unhide GA for general users

### Changed
- update docs


## [1.22.0] - 2026-07-08

### Added
- one-shot field-scoped browser handoff ("Open on Computer")

### Fixed
- accept a decoded QR anywhere in the camera frame
- domain picker invisible until relaunch; add default-domain row

### Changed
- update docs
- prod rollout plan, staging drill results, BE finalize handoff
- re-sync frozen vectors to BE canonical base64url
- document Loox Quick View + plan and design artifacts


## [1.21.0] - 2026-07-07

### Added
- bind shorten to App Attest (LOOX-APP-ATTEST-SHORTEN-LINK-V1)
- signed auxiliary-domain registry client (LOOX-DOMAIN-REGISTRY-V1)
- sign the alias namespace — LOOX-RELAY-AUTHZ-V2 client
- shorten-link scaffold, gated on backend shorten_token
- per-alias mail-domain namespace via trusted registry

### Changed
- registry client live, vexla.app aux domains, V2 + shorten-assertion state
- auxiliary domains + shorten-link scaffold in codebase summary


## [1.20.0] - 2026-07-07

### Added
- attestationRequired=true (ASSERTION_MODE go-live) + drop debug logs


## [1.19.3] - 2026-07-07

### Fixed
- reset App Attest key namespace to break stale-key mismatch

### Changed
- log assertion clientDataHash + keyId (DEBUG) for parity triage


## [1.19.2] - 2026-07-07

### Fixed
- drop App Attest key when register fails after attestKey


## [1.19.1] - 2026-07-07

### Fixed
- destination-required lockstep + 403 UX + assertion diagnostics


## [1.19.0] - 2026-07-07

### Added
- destination ownership verification client (DEC-DST-01 B1)
- kind-7 beginDestinationVerification command + frozen parity
- transcript V2 binds one_time + relay capacity/rate taxonomy
- App Attest assertion on relay control mutations

### Fixed
- auto-poll pending destination verification

### Changed
- restore Xcode String Catalog canonical format + ignore settings.local.json
- mark Phase B1 done in plan
- Phase B destination-verification plan (B1 backbone / B2 deep-link)
- BE coordination — normalize/migration decisions + Phase C parity confirmation
- BE go-live work order + mark Phase A done
- client-authenticity audit, BE proposal, and Phase A plan


## [1.18.0] - 2026-07-06

### Added
- adopt BE LOOX-CAP-MANIFEST-V1 contract + service-state probes
- UI state system, Online Features settings, retired review, AutoFill snapshot
- signed manifest core — verify, cache, anti-rollback, fail-safe dormancy
- capability core — resolver, per-service breakers, structured operator signals
- map alias_cap_reached to dedicated user copy
- offer written-back private email as alternative username
- typed error copy + bounded silent retry (nonce replay, stale epoch)
- forwarding-inbox management UI + journal-free resumable bulk rotation
- create-login private email — suggest, provision on tap, bind on save
- first-class ForwardingInbox model + 0..N reusable addresses
- rename alias surfaces to Private Email + pause/delete confirmations
- real destination email + alias management (2-call create, write-back, detail)
- P4B iOS client — activate aliases on live relay + erase gate
- per-persona profile card — Profile/avatar follow active persona
- hard Space<->persona partition (fail-closed, INV-R03)
- surface active persona in Profile + Home header
- P4A relay principal — P256 owner key, signed commands, escrow (iOS)
- P3 local email alias model (no backend, relay-gated)
- P2 persona context + AutoFill isolation (INV-R03)
- P1 persona core — model, sync, seed/invariants, switcher
- P0 space hardening — persistence, primary resolver, scoped search

### Changed
- Xcode catalog normalization (re-sorted, no content change)
- record C4 BE-contract adoption in capability plan
- mark private-email gap roadmap G1-G6 shipped (PR #44-#49)
- persona-Space hard partition plan marked done
- P4A relay principal plan marked done
- P3 local alias model plan marked done
- P2 persona context + AutoFill plan (P2.1-P2.4) marked done
- P1 persona core plan (P1.1-P1.3) marked done
- persona/spaces/relay proposal V3 (locked) + P0 space hardening plan


## [1.17.0] - 2026-07-06

### Added
- shared-vault hardening V2.1 — online gate, per-device seal, capability v2 (TOTP/passkey ask-each-time + hand-over) (#33)
- enable App Attest registration + shadow-mode assertions

### Changed
- shared-vault hardening V2.1 — patch per security review


## [1.16.1] - 2026-07-05

### Fixed
- add Loox Link sources missing from the loox link commit

### Changed
- loox link quick share, passkey supersede, shared-vault hardening v2


## [1.16.0] - 2026-07-05

### Added
- implement loox link


## [1.15.0] - 2026-07-05

### Added
- realtime value propagation, per-recipient management with update mode and live capability editing, leave-share fix (#30)
- V1.2 — shared items as first-class read-only vault items (#29)
- explain first-share-needs-link on the waiting screen
- recipient publishes rendezvous pointers in participant profile — owner auto-invites repeats from its own zone
- in-app invite-inbox diagnostics panel (DEBUG)
- rendezvous auto-invite pipeline — inbox arm, sealed drop, reconciler, accept prompt
- signed, sealed, expiring invite envelope kernel
- public-db invite rendezvous transport spike
- Shared with Me as a system space in the Items Spaces list
- single-confirm pairing — recipient auto-pins, owner activates with one tap
- iMessage compose with the recipient pre-filled
- universal-link invites via public-database rendezvous
- encrypted display envelope + associated-domains entitlement
- revocation and share management
- recipient shared-item UX and request state machine
- owner approval ceremony with boundary-aware TOTP issuance
- owner share-config UI
- CKShare control-plane transport services
- control-plane crypto kernel
- approval transport plumbing + push pipeline separation

### Fixed
- QA round 4 — approved-code copy/large-type, drop TOTP reveal option, notifications-screen presenter arbitration, pending dots, Home approval row (#32)
- QA round 3 — field order, website dedup, TOTP row parity, requester identity, auto-dismiss ceremony, restore/revoked handling, notification history, drop Home search icon (#31)
- resolve rendezvous recipient from accepted-share participants — email lookup returns no userRecordID pre-acceptance
- rendezvous delivery — notification prompt for recipients, schema bootstrap before subscription, drop retry while waiting
- apply review findings — invite alert lifecycle, seen-on-response dedup, cold-launch link buffer, U7 metadata cross-check
- stop answered approval requests resurfacing until TTL expiry
- alert only on ApprovalRequest creation, not every zone write
- present approval sheet when inbox filled before shell appears
- route invite universal links through the scene delegate
- confirm invite acceptance to the user; revoke deletes the invite record
- unblock recipient navigation and owner waiting screen
- invite-link hardening from review
- make approval responses idempotent against CloudKit retries
- surface recipient verification failures with the failed check

### Changed
- reviewer agent memory
- self-explanatory resolver skip log for QA
- record pre-acceptance userRecordID finding
- sharing V1.1 invite tier in codebase summary
- V1.1 phases 3-5 complete, review findings resolved
- phase 4 kernel status
- sync V1.1 phase statuses
- sharing v1.1 plan — opaque invite rendezvous, universal link, shared-with-me space
- phase 8 automated gates done + two-device QA runbook
- describe Approval Mode sharing; correct the iCloud enablement note
- phase 7 revocation sync-back
- phase 6 recipient UX sync-back + review report
- phase 5 approval ceremony sync-back + review report
- phase 4 share-config UI sync-back + review report
- approval-mode sharing plan, gate verdict, phase reports
- extract zone-delta cursor + single-flight helper


## [1.14.1] - 2026-07-05

### Fixed
- set aps-environment per configuration (production for release)

### Changed
- update fastlane


## [1.14.0] - 2026-07-05

### Added
- redesign Profile into Identity and Payment sections
- Home profile row, Loox wordmark header, Space switcher in All section
- printable Emergency Kit PDF with scan-to-recover
- unified Mac header band spanning list and detail columns
- three-column Mac shell with toolbar search and suggestions
- native macOS Settings window with sidebar navigation

### Fixed
- reset foreground auto-lock timer on any user activity
- search and New Item join the system unified toolbar
- header band is the Mac window's top chrome; detail gets its own header
- search suggestions keyed to query, not field focus
- Mac shell polish — toolbar search, white detail, Space dropdown
- macOS Settings — dead band, broken pickers, action buttons
- grouped form style on macOS — no more centered gray slabs

### Changed
- add EN/VI localizations for new profile and emergency-kit strings
- item detail header, editor Space pill, passkey border
- add localize


## [1.13.0] - 2026-07-04

### Added
- near-real-time sync via silent CloudKit push
- multi-device CloudKit sync with vault-key provisioning
- iPad/Mac adaptive sidebar (NavigationSplitView)
- compile for iPad + macOS via platform-abstraction shim layer

### Fixed
- join-flow password step reads as vault-received, not new-vault
- pull via zone-changes delta fetch instead of CKQuery
- macOS/iPad UI conformance — sheets, buttons, sidebar
- launch crash — disable SwiftData's automatic CloudKit mirroring

### Changed
- fix some issue sync data


## [1.12.0] - 2026-07-04

### Added
- login editor redesign, UI state restoration, and detail polish
- generator UX overhaul, MonoLisa secret typography, Large Type reader


## [1.11.0] - 2026-07-04

### Added
- title + description under the logo, lock icon in the field
- pre-fill identity email + welcome note, tag starter items
- collect email + seed a branded "Loox Account" item
- make restoring trashed/archived items discoverable

### Fixed
- update IdentitySeedTests for the new make(...) signature


## [1.10.0] - 2026-07-03

### Added
- in-app shortcut to enable Loox for AutoFill
- present the QR scanner full-screen
- brand the AutoFill unlock + recovery screens

### Fixed
- consistent logo sizes + instant unlock transition


## [1.9.0] - 2026-07-03

### Added
- redesign first-run flow with Loox branding


## [1.8.0] - 2026-07-02

### Added
- brand the welcome step with the Loox logo mark
- swap app icon and brand logo to Loox artwork
- rebrand to Loox (display) / Loox Password (full name)
- redesign Emergency Kit step

### Fixed
- About screen shows the Loox wordmark instead of the shield glyph
- render the Loox wordmark aspect-fit instead of a forced square
- copy toast in onboarding + compact kit header + confirm card
- hero titles fit small screens via shared step header
- saved-login title uses bare domain, not the full URL

### Changed
- update launch screen


## [1.7.1] - 2026-07-02

### Fixed
- retry Face ID in UnlockGate instead of stranding on password form


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
