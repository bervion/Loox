# Changelog

## [1.47.0] - 2026-07-30

### Added
- gauge Watchtower kiểu 1Password, và Cần chú ý biết mật khẩu lộ / trùng (#189)


## [1.46.0] - 2026-07-30

### Added
- Quick Actions lên đầu Home, và banner cảnh báo cho từng item (#188)


## [1.45.1] - 2026-07-29

### Fixed
- keep shake-to-lock armed once you navigate anywhere (#187)


## [1.45.0] - 2026-07-29

### Added
- restore Polaris icons, widen the duotone picker, and ring the password strength (#186)


## [1.44.0] - 2026-07-29

### Added
- SF icon system, crash reporting, unlock hardening, and passkey sync diagnostics (#185)


## [1.43.2] - 2026-07-28

### Fixed
- tutorial spotlight, tour motion, and the private-email confirmation flow (#184)


## [1.43.1] - 2026-07-28

### Fixed
- release hardening for the iOS and iPad launch (#183)

### Changed
- update gitignore


## [1.43.0] - 2026-07-27

### Added
- add Japanese, and align sidebar and identity rows with the vault (#182)
- move Quick Actions into the sidebar and add a Settings row (#181)

### Changed
- update docs


## [1.42.0] - 2026-07-27

### Added
- one decision per side, identity at accept, and a usable shared passkey (#180)

### Changed
- update docs


## [1.41.1] - 2026-07-27

### Fixed
- anchor bottom CTAs, unify onboarding accent, unlock Level-2 with Face ID (#179)


## [1.41.0] - 2026-07-26

### Added
- keyword-only Search, pushable filtered lists + detail polish (#178)

### Changed
- the stable Quick View error copy is now the browser wording (#177)


## [1.40.0] - 2026-07-26

### Added
- Extra Protection UX overhaul — setup, protect, reveal, turn off + ciphertext leak fixes (#176)
- full-screen camera, warm-up cover, and live code formatting (#173)
- continuous logo choreography across privacy, lock, and wink (#174)

### Fixed
- simulator janitor actually reclaims orphans (#175)
- iPhone hub grid regression, password-form reveal UX, dead AutoFill row (#170)
- leaving a share must prove the zone delete landed (#172)
- scope App Attest key state per backend, bind marker to key id (#171)


## [1.39.0] - 2026-07-23

### Added
- iPad welcome landing polish and system-default sidebar (#169)
- iPad standardization — permanent sidebar, readable-width flows, Mac-reusable width system (#168)


## [1.38.0] - 2026-07-23

### Added
- iCloud-style plan quota tiles, service status dots, and offline-first capability hardening (#167)
- production quality gates, deterministic UI-test seam and isolated CI/release workflows (#134)

### Fixed
- small-screen UI defects and Vietnamese localization audit (#166)
- persist the deliberate lock so force-quit cannot bypass slide-to-confirm (#144)

### Changed
- retire the agent-governance layer, keep the test gates (#165)
- run the quality gates for the develop integration branch (#145)
- run all pull-request and policy jobs on the self-hosted vaultify-ci runner (#138)
- record proven pull-request check names for the required-check rollout (#137)


## [1.37.4] - 2026-07-20

### Fixed
- keep both Home layers resident so the edit-mode toggle animates opacity only (#133)


## [1.37.3] - 2026-07-20

### Fixed
- resolve edit-mode hitch vs Done tap by removing the header overlap (#132)


## [1.37.2] - 2026-07-20

### Fixed
- keep Home header above the layout editor so Done stays tappable (#131)
- raise LargeTypeView tap animation to 150ms threshold (#129)

### Changed
- remove B4 merge-gate test file
- b4 merge gate (#128)
- harden pr-notify verify step (#120)
- verify Dev-Quality PR review triggers Rex (#119)
- fix pr-notify workflow startup failure
- add Dev-Quality PR review workflow


## [1.37.1] - 2026-07-18

### Fixed
- fail closed when the upload assertion is unavailable


## [1.37.0] - 2026-07-17

### Added
- GA4 engine with typed event catalog and consent toggle

### Fixed
- include .pdf extension in exported kit filename

### Changed
- update docs


## [1.36.1] - 2026-07-17

### Fixed
- grant tier from the in-hand purchase and unblock the success path

### Changed
- update docs


## [1.36.0] - 2026-07-17

### Added
- VaultPasskey CloudKit plane and honest backup badge
- sealed records carry folder-parity sync metadata

### Fixed
- layered TestFlight detection with diagnostics
- review hardening for the sync plane
- recovery envelope reaches iCloud independently of item sync
- per-grant owner reads, foreign-grant protection, loud passkey failures
- keep auto-lock touch tracking alive on pushed screens

### Changed
- passkey sync plane in codebase summary, plan status, audit follow-up
- passkey CloudKit sync plan
- audit report for restore, share-passkey, and auto-lock fixes


## [1.35.1] - 2026-07-17

### Fixed
- TestFlight resolves beta purchase access directly


## [1.35.0] - 2026-07-17

### Added
- purchases carry the billing token and attach
- entitlement payloads ride the three service clients
- entitlement attach client, billing token and lease state

### Fixed
- stable layer order for the edit-mode cross-fade


## [1.34.0] - 2026-07-16

### Added
- paywall hero plays the brand reveal once
- ink Max identity in light UI, purple-pink aurora in dark
- cosmic nebula Max identity and heaviest brand weight
- MAX badge identity and per-plan paywall tinting
- plan landing hero plays the brand reveal once
- plan landing pages and paywall polish per reference
- custom acquisition paywall in the iCloud+ idiom
- Loox row title follows the current tier
- open purchase surfaces in beta environments
- contextual over-quota gates behind the launch flag
- membership hub redesign with tier header, member seal and usage grid
- paywall on the native subscription store
- Loox tier contract, StoreKit 2 entitlements and launch flag

### Fixed
- layout editor enters edit mode as one animated beat
- owner-tuned seal reveal timing
- seal ring localizes in-app and the reveal is visible
- balanced membership header lockup
- seal coverage matches the reference stamp
- seal reads as two balanced stamp arcs
- subscriber seal matches the iCloud+ stamp
- Loox row title keeps the regular body weight
- dark aurora readability and a tighter CTA lockup
- link colors read as links; policy links scroll with content
- Max identity retuned to the aurora formula
- benefit badges and a glass trial pill
- restore button matches the CTA height exactly
- paywall cards and CTA match the iCloud+ reference

### Changed
- backend entitlement proposal v4 after third review round
- backend entitlement proposal v3 for Cloudflare
- record live App Store Connect subscription group
- Loox membership V1 client summary and execution plan


## [1.33.0] - 2026-07-16

### Added
- Share-a-Space ceremony + enable per-grant transport
- replace-safe re-share + Space membership executor
- settings-style icon tiles + inline device list with real model names
- per-grant Family transport + live-membership reconciler behind a flag
- publish device on the sync path so peers appear without opening Devices
- Devices registry (list-only) over CloudKit private zone
- Family members list (first slice) + resolve family/devices ADRs
- Apple-Account-style hub with Personal Information, Payment cards, and Loox

### Fixed
- hide the empty top nav bar on iOS 26 so the chip-bar header stays flush
- force light until the user picks a theme; stop foreground carousel flip
- flush chip-bar header (no large title) + auto-scroll the selected chip
- open Notifications via the navigator to stop tab-bar reveal delay

### Changed
- update codex
- update docs
- execution-ready plans for family full-group and devices key-rotation
- record red-team blocker for space fan-out
- security designs + threat models for family group and devices revoke


## [1.32.0] - 2026-07-15

### Added
- customizable section layout and transparent tab headers


## [1.31.0] - 2026-07-15

### Added
- group-card redesign for quick actions and items
- glass filter trough + smart browse sections
- always-on Telegram-style scope filter + keyboard dismissal
- pin the scope filter above the search field (Telegram-style)
- branded language-switch transition on the UIKit shell
- UIKit navigation shell for compact iOS
- Backup child screen; fix two mid-sentence VI casings
- reusable item-type picker bottom sheet
- full-bleed empty state with a custom swirl mark
- duotone type-icon avatars with selectable style
- duotone FontAwesome icon set for the Space picker
- first-launch empty state + periodic auto-audit

### Fixed
- softer selected chip + pin results to the top
- selected filter chip uses adaptive grey for contrast
- native scope selector instead of a custom bottom bar
- native Save button + loading ellipsis on language switch
- re-resolve Settings/General nav titles on language switch
- re-localize pushed screens in place, without resetting navigation
- pop navigator-pushed detail on self-dismiss; relocalize pushed screens
- reliably raise the search keyboard on cold launch
- persist the custom avatar icon across loads
- apply custom avatar icon, relabel Default, even menu glyphs
- scope the audit to credentials only
- resolve remaining test-target warnings
- resolve compiler and CI warnings

### Changed
- remove the quick-filter zero state
- Save button reads as a filled accent action
- mark UIKit nav shell Phase 1-3 runtime-verified
- update UIKit nav shell plan status
- full-screen pushes hide the tab bar app-wide
- hide tab bar on push (Mail/News/Telegram idiom)
- Revert tab-bar hide on Settings; keep it visible for a smooth pop
- native iOS switches instead of the app-wide custom style
- i18n(settings): shorten VI AutoFill row to 'Tự động điền mật khẩu'
- hide the tab bar while Settings is pushed
- Security child screen, native switches, localized pickers
- Apple-style pushed screen, SF icons, child pickers
- vertically center the type-row chevron
- close the type sheet via a toolbar button, not text
- native iOS close button on the item-type sheet
- drop the picker logo below the close button
- refine the item-type picker sheet
- type/custom avatars fill the frame without a badge tile
- drop the seeded Loox Account login
- gitignore .agentkit local tooling
- gitignore local .claude tooling, keep shared agent-memory
- borderless inset-grouped cards, unify radius to md
- adaptive screen gutter, fixed card interior padding


## [1.30.0] - 2026-07-13

### Added
- one onboarding concept across every step
- Apple-style create-password step
- 'Want to start fresh?' jumps straight into vault creation
- neutral black default controls, brand-only colors, canvas convention
- dots avatar reveals its rings when the profile screen opens
- Loox dots avatar as the default profile mark
- brand animation finale and a consistent pinned CTA across onboarding
- theme previews in onboarding, light-first default, full-width save
- mode-driven swirl loading indicator (reveal / loop / dismiss)
- Telegram-style rounded QR rendering app-wide
- play the Loox swirl once on appear, then freeze (no infinite loop)
- Loox swirl brand animation on the restore QR and recovery screens
- restore via bottom-sheet chooser, header nav, and PDF key import
- refine Emergency Kit card interactions and warning placement
- redesign the Emergency Kit step to the concept card + gated continue
- use the brand lockup across all onboarding step headers
- brand lockup (symbol + wordmark) inline in the create-password header
- black primary unlock button in the AutoFill extension
- neutral black primary buttons and simplify create-password title
- roll the new brand into welcome, splash, lock, privacy and unlock
- add QR code to item share invite

### Fixed
- memoji ghosting — hide the poster once the video renders
- localized, sentence-case copy-toast labels
- recovery-key label centres with the copy glyph, which confirms copies
- opaque disabled Continue on the password step
- restore sheet uses the native sheet chrome (no side gaps)
- grouped-gray canvas behind onboarding form steps
- unlock flourish plays the real brand animation's opening act
- native iOS back button, swirl nearer the header, cleaner emanation
- dismiss keyboard on scroll or tap-outside in the recovery key screen
- PDF import picker opens and accepts files; dashed drop-zone UI
- remove duplicate dismiss declaration in RestoreMethodSheet
- restore sheet uses VaultSheetScaffold so the close X sits in the header
- restore sheet uses solid gray bg and a plain (uncut) close X
- memoji poster fallback and drop audio track on welcome landing

### Changed
- refresh the memoji-gray clip and poster
- biometric step uses the looping dots mark with the SF biometry glyph
- after a successful save only Continue remains
- save-kit button drops its download glyph; VI label sentence-cased
- kit note glyph swaps to the duotone hand-holding-medical mark
- emergency-kit step polish
- password info glyph swaps to the duotone handshake mark
- lighter secondary text (#949497) on the Day theme
- pinned CTAs ignore the keyboard; more air around the step logo
- password info glyph swaps to the duotone door-open mark
- duotone brand pair corrected to #009BFF over #94D5FF
- dots mark heads every onboarding step; native back on password
- duotone brand icons in the restore option boxes, top-aligned
- restore sheet swirl hugs the header, air moves below it
- welcome carousel gap reverted; more air below the restore link
- welcome restore link uses the brand link blue; roomier carousel gap
- restore sheet polish (roomier swirl, smaller title, glass close)
- Apple-Account-style restore sheet
- welcome carousel keeps a soft shadow via a cardOnWhite elevation
- brand link blue #0065F4 for text links and link buttons
- accent text rank floors at 3:1 so links stay near the brand blue
- white core disc inside the avatar rings; flat Apple-style cards
- card-white disc behind the dots avatar so it lifts off gray canvases
- update accent expectations for the #009DFF rebrand
- rebrand blue to #009DFF, avatar dots to #61C0FF
- dots avatar matches the measured Apple Account mark
- shorter unlock act with a smooth glide to centre
- neutral black login arrow on the lock screen password field
- neutral black tab bar highlight (Apple-style)
- set autoNight explicitly in the system-following resolution test
- primary buttons are welcome-style pills (capsule, content width)
- sentence-case button labels, lighter CTA weight, welcome spacing
- QR guide is the full sentence with the settings path highlighted inline
- QR pairing guide as breadcrumb chips, clearer title spacing, refined error
- dots emanate from the logo edge; loop flows without a held beat
- dispersal is a smooth scale + rotate + fade, not a particle scatter
- dispersal is a measured particle scatter with a lingering fade
- loop never stops turning and spills past the frame while fading
- loop is one full breath per cycle, per-ring swirl phases
- match the reference video's measured motion law in reveal and loop
- loop swirls out from the logo with a gentle spiral, not uniform rings
- swirl radiates out from centre with even fade and gentle rotation
- match reference swirl exactly (4 rings x 24 dots, half-step interleave)
- 4-band interleaved swirl with roomy centre gap and varied dot sizes
- denser spiral swirl with size-graded dots (closer to the reference)
- solid 'or' rule and Loox symbol above the recovery key title
- merge restore options into one flat grouped card with per-option badges
- soft-green saved state on the Emergency Kit save button
- make the Emergency Kit save button and key box border red
- use lightweight breathing symbol for the privacy shield
- rebrand logo, drop the infinity mark
- note welcome landing redesign in codebase summary


## [1.29.0] - 2026-07-13

### Added
- redesign first-run welcome landing

### Changed
- update logo


## [1.28.0] - 2026-07-13

### Added
- per-site kill switch, token-mirrored palette, and save-overlay hardening
- run the Safari extension on iPad and package all content scripts
- inline identity and card menu with allowlisted payment-frame fill
- signup assist with generated password and save-login overlay
- identity and card fill engine with popup-authorized payload flow
- unlocked session with auto-prompt popup unlock
- Face ID unlock bridge and origin-scoped popup item list
- add Safari web extension appex with MV3 skeleton and native echo bridge
- extension-safe KDF profile for the key bundle with opportunistic re-wrap
- hold the Vault Key in locked SecureBytes end to end
- recipient safety-code verification gate before first use
- honest invite copy, badge for ready shares, faster accept detection
- local banner when a share is ready for the ceremony
- silent push when recipient publishes acceptance profile

### Fixed
- only summon the inline menu on a trusted user focus
- harden signup-assist save flow against renderer abuse
- check SecretGuard on the raw card number before digit stripping
- bind fill delivery to the popup-displayed origin and harden the message hub
- reject off-screen and ancestor-opacity fields at fill moment
- harden extension unlock session and popup item matching
- lift alert bindings out of body to satisfy the type-checker
- sign approval assertions with honest presence flags
- finish store-helper rename in passkey list entry point
- honest UP/UV flags for conditional registrations
- recoverable store on read paths instead of fatalError
- keep push-triggered share status checks read-only
- marker-before-pin ordering and keychain-backed backfill flag
- keep app alive until silent-push CloudKit work finishes
- conflict-safe participant profile publish across devices

### Improved
- one VaultStore per extension presentation
- gate owner request scans behind a push-driven dirty flag

### Changed
- update docs
- safari web extension summary, release runbook, and device QA checklist
- sign the Safari appex in the match pipeline
- protocol fuzz suite for the native message router
- mark safari inline-menu phase code complete, device gate G5 pending
- record signup-assist hardening and explicit G4 device-QA gates
- mark safari signup-assist phase code complete, device gate pending
- update docs
- record safari web extension phase 1 status and packaging findings
- pin acceptance-status, scan-gate, merge, and verify-gate decisions


## [1.27.1] - 2026-07-12

### Changed
- update icon


## [1.27.0] - 2026-07-12

### Added
- text-rank accent across components and picker rank preview
- Controlled Contrast — accent text rank and WCAG fill guard
- Vault Audit flow with Security tab
- incremental known-leak checker
- sealed audit persistence with CloudKit sync
- explainable 1000-point scoring engine
- integrity and hygiene rules
- pattern-aware password strength engine
- rule engine core with stable finding fingerprints
- strength drill-down, working category taps, persona scope, gated intro
- private-email bubble on focused credential fields

### Fixed
- switch track guards against its own knob
- copy feedback on profile rows, canonical email and audit glyphs
- single-line finding rows in the issue groups
- align audit screens with the design DNA standard
- profile row survives empty states, VI Space term unified as nhom
- quick-action tiles blank after persona switch on iOS 26

### Changed
- update logo
- update reviewer agent memory
- Vietnamese strings and docs for Vault Audit
- vault audit upgrade plan and review report


## [1.26.1] - 2026-07-11

### Fixed
- DNA-standard security subscreens and honest iCloud/mail glyphs
- item-row status line, search recents card, forwarding inbox detail


## [1.26.0] - 2026-07-11

### Added
- iOS-style colored icon badges
- dedicated phone kind with phonePad and decode fallback

### Fixed
- private email screen reads addresses-first, stronger soft surfaces
- calmer avatar camera badge, identity icons, 44pt rows, bar-glyph sizes
- Space switcher reads as a control, not a section label


## [1.25.0] - 2026-07-11

### Added
- floating chip tab bar for pre-iOS-26
- 1Password-style gauge choreography with 1000-scale readout

### Fixed
- never start CloudKit sync inside the XCTest host
- Loox brand avatar on detail and black tile in light mode
- reliable entry formatting, brand mark tiles, scanner reticle
- remember the explicit All Spaces filter choice
- drop doubled Space.s4 padding on status card rows

### Changed
- lower iOS deployment target to 17.3
- quiet quick-action tiles


## [1.24.0] - 2026-07-11

### Added
- full payment card treatment with brand detection, formatted entry, and camera scan
- deferred follow-ups, device feedback fixes, extension space assignment, and private email integration
- codify the design DNA standard and drop interpunct separators from UI copy
- Controlled Reveal design pass across copy, item detail, home, search, and unlock
- concentric radius helper, glyph-resolve text, copy-morph icon, recently-used scoped query
- flow completion pass across core screens per new design reference

### Fixed
- recipient row drops the duplicate active badge and the list gains an inline share row
- title never derives from a secret, plus font and layout corrections from device review
- detail forwards-to line drops the status text
- private email rows match the reference design
- adversarial sweep finale with recovery-join hierarchy, theme ring accent, and consolidated QA deliverables
- adversarial sweep wave 2 batch 3 across sharing, personas, profile, shell, and autofill
- adversarial sweep wave 2 batch 2 across home, search, watchtower, generator, settings, and appearance
- adversarial sweep wave 2 batch 1 across onboarding, unlock, items, folders, item detail, and editor
- shared primitive sweep for token purity and reveal-button hit target
- identity strip to top, gate recently-used on vault size, quick actions as 2x2 pills

### Changed
- surface registry for the adversarial UI sweep and ownership gap fixes
- app feature map and design DNA audit report


## [1.23.0] - 2026-07-09

### Added
- passkey parity in edit-share + recipient in-app display

### Fixed
- show item passkeys in share config regardless of live key
- regenerate stale participant escrow instead of failing forever

### Changed
- log passkey relying-party match in share config (DEBUG)
- add DEBUG share-handshake diagnostics


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
