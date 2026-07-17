# GA4 Analytics Engine (Firebase Analytics)

Status: DONE + LIVE (260717) — compile check passed (app + both extensions); extension
binaries verified Firebase-free (nm: 0 FIR classes in both .appex debug dylibs, 7 in the
app); `AnalyticsEventTests` 5/5. `GoogleService-Info.plist` (project loox-63383) added to
`Vaultify/Resources/`; app-level `PrivacyInfo.xcprivacy` added (no tracking,
ProductInteraction not-linked, UserDefaults CA92.1). Runtime-verified on iPhone 16 sim
via log stream: `I-COR000001 Configuring the default app` → engine mirror
(`tutorial_begin`, user props tier/language/sync) → FIRAnalytics `Event logged` →
`Uploading data. Host: app-analytics-services.com`. The single early `I-COR000003` line
is App Measurement's pre-main probe before `App.init` configure — one-shot, benign.
Remaining manual step: App Privacy label (Product Interaction, not linked) at next
App Store submission.

## Goal

Full GA4 integration with a scalable analytics engine: typed event catalog, provider
fan-out (Firebase now, more later), consent toggle, strict no-PII contract.

## Decisions

- **SDK**: `firebase-ios-sdk` pinned `.exact("12.16.0")` via Tuist `packages:`
  (XcodeProj-native SPM). Product **`FirebaseAnalyticsCore`** = full GA4 measurement
  via `GoogleAppMeasurementCore` **without AdSupport/IDFA** (no ATT prompt, matches
  privacy posture). App target ONLY — never the AutoFill/Safari extensions.
- **Engine**: `Vaultify/Analytics/` — `AnalyticsEngine` (MainActor facade, singleton)
  → `[AnalyticsProvider]` fan-out. `FirebaseAnalyticsProvider` + DEBUG
  `ConsoleAnalyticsProvider`. Events are typed `AnalyticsEvent` values from a static
  catalog; DEBUG-asserted against GA4 limits (name/param regex, 40/25/100 caps).
- **Privacy contract** (doc-commented in code): events carry item TYPES, count
  buckets, product IDs, setting states. Never item names, usernames, URLs, search
  terms, passwords, notes. Bulk import wrapped in `runSuppressed` so 500 adds ≠ 500
  events (one `vault_imported` with a count bucket instead).
- **Consent**: `SettingsStore.analyticsEnabled`, default ON (opt-out), toggle in
  Settings → General with disclosure footer (EN+VI). Gates engine + Firebase
  collection (`setAnalyticsCollectionEnabled`).
- **Missing config tolerated**: `FirebaseApp` configures only when
  `GoogleService-Info.plist` is bundled (`Vaultify/Resources/`, picked up by the
  existing glob). Without it the engine runs with Console provider only — forks/CI
  build fine.
- **Screen tracking**: automatic UIKit screen reporting OFF
  (`FirebaseAutomaticScreenReportingEnabled=false`); manual `.analyticsScreen("x")`
  modifier on key screens (SwiftUI-correct names).
- User properties: `subscription_tier`, `app_language`, `icloud_sync`.

## Phases

1. Project.swift: package + product dep + Info.plist key. ✅ when compile passes
2. Engine core files (5) under `Vaultify/Analytics/`.
3. Bootstrap (`VaultifyApp.init`), SettingsStore flag, General settings toggle
   (iOS + Mac pane), xcstrings EN+VI.
4. Call sites: repository CRUD, unlock, onboarding (begin/complete/created/restored),
   paywall funnel, watchtower scan, search submit, generator, language/iCloud/theme
   toggles, import/export, clipboard copy (sensitive flag only), screen views.
5. `VaultifyTests/AnalyticsEventTests.swift` (catalog obeys GA4 limits) +
   `tuist generate` + compile check.
6. Docs: README (honest disclosure), codebase-summary, deployment-guide
   (GoogleService-Info.plist step). Report.

## Validation

- `tuist generate` + workspace compile (app + extensions) per CLAUDE.md.
- Unit test target compiles; analytics tests pass locally when simulator available.
- No Firebase symbol in extension targets (deps unchanged there).

## Risks / rollback

- First SPM resolve downloads Firebase binaries (CI runner needs network — already
  true for match). Rollback = revert Project.swift + delete `Vaultify/Analytics/`.
- User must create the Firebase project + drop `GoogleService-Info.plist` into
  `Vaultify/Resources/` (bundle id `com.bervion.vaultify`) — until then events go
  nowhere (by design).
- App Store privacy label must add "Product Interaction (not linked to identity)"
  at next submission.
