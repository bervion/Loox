---
phase: 1
title: "Platform Abstraction & Multiplatform Target"
status: code-complete (pending on-device macOS QA)
priority: P1
effort: "3-4d"
dependencies: []
---

# Phase 1: Platform Abstraction & Multiplatform Target

## Overview

Make the codebase compile for **macOS** (and iPad) from one shared SwiftUI multiplatform target.
Introduce a thin cross-platform shim layer so the ~21 UIKit-coupled files build on AppKit, then
add the `.mac` / `.iPad` destinations in `Project.swift`. Delivers a Mac app that launches to the
existing UI (unpolished) — the foundation every later phase builds on.

## Requirements

- Functional: App target builds & runs on iPhone, iPad, and macOS 15 from a single target.
- Functional: Biometric unlock works on macOS (Touch ID via `LAContext`).
- Non-functional: iPhone build byte-for-byte behavior unchanged (no regressions).
- Non-functional: No hardcoded platform checks scattered — centralize in a `Platform/` shim module.

## Architecture

**Shim module** (`Vaultify/Platform/` — new): typealias + small wrappers behind `#if canImport(AppKit)`.

- `PlatformImage` = `UIImage` (iOS) / `NSImage` (macOS). Wrap the 10 `UIImage` sites
  (avatars `AvatarImage`, favicons, `MeshGradientRenderer`, `MainTabView.tabImage`). Provide
  `PlatformImage.fromData`, `.pngData()`, downscale helper used by `AvatarImage.downscaledJPEG`.
- `PlatformColor` = `UIColor` / `NSColor`. `VaultColors` dynamic-color sites (6 files) get a
  `dynamic(light:dark:)` factory that maps to `NSColor(name:dynamicProvider:)` on macOS.
- `PlatformPasteboard` — wraps `UIPasteboard.general` / `NSPasteboard.general` for `ClipboardService`
  (auto-expiring clipboard must still clear on macOS; macOS has no expiry API → schedule a clear task).
- `PlatformHaptics` — `Haptics.*` become no-ops on macOS (`#if os(iOS)` guard inside existing methods).
- App lifecycle: `UIApplication` (5 files — privacy shield, scene phase, open settings) → guard
  `#if os(iOS)`; provide macOS equivalents where meaningful (window resign for privacy shield via
  `NSApplication` / scenePhase), no-op the iOS-only bits (`ASSettingsHelper`, LaunchScreen storyboard).
- `overrideUserInterfaceStyle` / `UIWindow` (ThemeStore forcing appearance) → macOS uses
  `NSApp.appearance = NSAppearance(named:)`.

**VaultifyCore shared (3 files)** — guard UIKit:
- `AppTheme.swift`, `ColorHex.swift`: `#if canImport(UIKit)` import UIKit `#else` import AppKit.
- `Mesh/MeshGradientRenderer.swift`: renders `PlatformImage`; CPU-only (no Metal) already, so only
  the `UIImage`/`CGContext` surface needs the typealias.

**Tuist `Project.swift`**:
- App target `destinations: [.iPhone, .iPad, .mac]`, `deploymentTargets: .multiplatform(iOS: "17.6", macOS: "15.0")`.
  <!-- Updated: Validation Session 1 — macOS 15 Sequoia (was 14) for OTP autofill parity -->
- `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad; macOS ignores).
- Keep `SWIFT_OBJC_BRIDGING_HEADER` (Argon2 C compiles on macOS — reference C is portable; verify KAT).
- `INFOPLIST_KEY_NSFaceIDUsageDescription` retained. **macOS entitlements file is MANDATORY (Mac App
  Store target → App Sandbox required):** `com.apple.security.app-sandbox`, App Group
  `group.com.bervion.vaultify`, Keychain sharing group `…com.bervion.vaultify.shared`, iCloud/CloudKit
  container, hardened runtime. <!-- Updated: Validation Session 1 — MAS distribution ⇒ sandbox mandatory -->
  Sandbox makes the `kSecUseDataProtectionKeychain` + container-fail-loud fixes below non-optional.
- `UILaunchStoryboardName` stays iOS-only (macOS ignores the key).
- Tests target stays iPhone for now (macOS test host later).

## Related Code Files

- Create: `Vaultify/Platform/PlatformImage.swift`, `PlatformColor.swift`, `PlatformPasteboard.swift`,
  `PlatformHaptics.swift`, `PlatformAppearance.swift`
- Create: `Vaultify/Vaultify-macOS.entitlements` (App Group + Keychain group + sandbox)
- Modify: `Project.swift` (destinations, deployment, device family, macOS entitlements)
- Modify: `VaultifyCore/Theme/AppTheme.swift`, `Theme/ColorHex.swift`, `Theme/Mesh/MeshGradientRenderer.swift`
- Modify: the ~18 app-layer UIKit files (AvatarImage, favicon, `ClipboardService.swift`, `Haptics.swift`,
  `MainTabView.tabImage`, ThemeStore appearance forcing, privacy-shield/scene-phase in `RootView.swift`)

## Implementation Steps

1. Create `Platform/` shim module with typealiases + wrappers; unit-safe, no behavior change on iOS.
2. Migrate VaultifyCore's 3 UIKit files to `#if canImport(UIKit)/#else AppKit`; verify Argon2 KAT on macOS.
3. Sweep app-layer UIKit sites → shim calls; guard iOS-only APIs with `#if os(iOS)`.
4. Edit `Project.swift`: add `.iPad` + `.mac` destinations, multiplatform deployment, `1,2` device family,
   macOS entitlements; `tuist generate`.
5. Resolve macOS compile errors iteratively (expect: PhotosPicker OK; `UIViewControllerRepresentable`
   camera/QR scanner → `#if os(iOS)` fallback "scan on iPhone" on macOS for now).
6. Verify iPhone + iPad simulator + macOS all compile & launch to existing UI; Touch ID unlock on Mac.

## Success Criteria

- [x] `tuist generate` + workspace compile succeeds for iPhone, iPad, and macOS (app + embedded iOS ext) — BUILD SUCCEEDED on both `generic/platform=iOS Simulator` and `generic/platform=macOS`.
- [ ] Mac app launches to onboarding/lock/unlocked using the current (pre-sidebar) UI. — **pending on-device run** (compiles; not launched — needs signing/real Mac).
- [ ] Touch ID unlock works on macOS; master-password fallback works. — **pending real Mac hardware**.
- [x] Argon2 KAT passes (crypto suite green in the 133-test run; C is portable — macOS runtime KAT still to confirm on device).
- [x] iPhone behavior unchanged — iOS BUILD SUCCEEDED with zero errors; all 133 unit tests pass; code review PASS (every iOS `#if` branch maps to the original UIKit call).
- [x] No raw `UIKit` symbol left un-guarded that breaks the macOS build — macOS compiles clean.

### Implementation notes (2026-07-04)
- Shim layer: `VaultifyCore/Platform/` (`PlatformImage`, `PlatformColor` — shared into both targets) + `Vaultify/Platform/` (`PlatformPasteboard`, `PlatformAppearance`, `PlatformHaptics` folded into `Haptics.swift`, `PlatformTextInput`, `PlatformNavigation`). Typealiases live in Core (not `Vaultify/Platform/` as first drafted) because `MeshGradientRenderer`/`ColorHex` are Core files compiled into the extension too.
- macOS surface was **materially larger than estimated** (red-team "P1 undercounted" confirmed): beyond the ~24 UIKit files, macOS also required cross-platform shims for `navigationBarTitleDisplayMode` (24 files), toolbar placements (`.topBarTrailing`/`.topBarLeading`/`.navigationBar`), `.listStyle(.insetGrouped)`, `fullScreenCover`, `.keyboardType`/`.textInputAutocapitalization`/`.textContentType`, plus guarding 3 iOS-only subsystems (CoreMotion shake-to-lock, Credential Exchange [macOS-26 API], Liquid Glass [macOS-26]) and `editMode`/`EditButton`.
- Deferred to macOS-shipping phases: `MacClipboardGuardian` NSImage-scale (avatar 2× on Retina, matters once CloudKit sync lands — P3) and `MainActor.assumeIsolated` observer robustness (both macOS-only, non-blocking). H1 (clear-on-resign wiping paste) fixed.
- iCloud entitlement intentionally OMITTED from `Vaultify-macOS.entitlements` (added in P3 behind `VAULTIFY_ICLOUD`).

## Risk Assessment

- **Camera/QR scanner is iOS-only** (`UIViewControllerRepresentable`) → macOS gets a graceful
  "add 2FA from iPhone / paste otpauth URI" fallback; do not block the build on it.
- **Dynamic `NSColor` provider** semantics differ from `UIColor` trait resolution → verify theme +
  light/dark flip on macOS matches iOS; the derived-token computed colors should carry over unchanged.
- **App Sandbox on macOS** may block App Group container path → confirm shared vault file still
  reachable (needed later for macOS AutoFill ext in P4); test read/write early.
- Mitigation: land P1 behind no user-visible macOS distribution until P2 polishes layout.

## Red Team Amendments (2026-07-04)

Accepted findings that reshape this phase. Add these as explicit tasks/criteria:

- **[Critical #5] Condition the iOS AutoFill extension embed per-platform.** The app target embeds
  `VaultifyAutoFill` unconditionally (`Project.swift:72-73`) and that ext is `destinations:[.iPhone]`
  (`Project.swift:117`). A single multiplatform target applies its dependency graph to the macOS slice
  too → macOS won't link an iOS-only appExtension. Use Tuist `TargetDependency` platform **conditions**
  (`.target(name:condition: .when([.macos]))` etc.): iOS ext on iOS destinations, macOS ext (P4) on
  `.mac`. Add this Project.swift change to the file list — it is currently missing.
- **[Critical #6] Set `kSecUseDataProtectionKeychain = true` on ALL `SecItem` queries.** macOS defaults
  to the legacy file keychain, which does not honor `kSecAttrAccessGroup` sharing or
  `.biometryCurrentSet`/`…ThisDeviceOnly` like iOS. Without this the biometric key + shared-group access
  break on Mac. Sites: `VaultifyCore/Keychain/BiometricKeyStore.swift:33-49,52-77`,
  `KeychainStore.swift:11-60`. Guard so iOS behavior is unchanged. Add macOS hardened-runtime +
  keychain-sharing entitlements.
- **[High #7] Fail loud on macOS when the App-Group container is nil.** `SharedConfig.containerURL`
  silently falls back to `URL.applicationSupportDirectory` (`SharedConfig.swift:57-68`), which hides a
  macOS entitlement misconfig and silently partitions the vault from the AutoFill ext. On macOS, assert
  / surface an error instead of falling back. Verify `containerURL` resolves to the shared group path.
- **[High #12] Clipboard auto-expiry is a SECURITY guarantee, not a nice-to-have.** iOS uses
  `UIPasteboard.expirationDate` (OS clears even if app is killed — `ClipboardService.swift:18-24`).
  `NSPasteboard` has no expiry API. `PlatformPasteboard` on macOS must: mark the item
  `org.nspasteboard.ConcealedType` (exclude from history/Universal Clipboard) AND clear via a mechanism
  that survives app termination (clear-on-resign + clear-on-terminate), not just an in-process `Task`.
  Treat this as a Security Consideration; do not claim iOS parity.
- **[High #15] Theme forcing needs a macOS spike before "no behavior change" is claimed.** `ThemeStore`
  iterates `UIApplication.shared.connectedScenes` and sets per-window `overrideUserInterfaceStyle`
  (`ThemeStore.swift:82`). macOS has no `connectedScenes`; `NSApp.appearance` is **app-global** and
  dynamic colors resolve against `NSAppearance` (not `UITraitCollection`). Spike the theme-force +
  dynamic-color round-trip on macOS (light/dark flip, no invisible text) as a P1 task.
- **[Medium #17] Enumerate each `UIApplication` site with a real macOS replacement — no blanket no-op.**
  `sendAction(resignFirstResponder)` keyboard-dismiss (`ItemEditorScreen.swift:286`,
  `NameStepView.swift:89`, `CreateMasterPasswordView.swift:92`) → `NSApp.keyWindow?.makeFirstResponder(nil)`;
  `UIApplication.shared.open` "Open Website" (`DetailFieldRow.swift:130`) → `NSWorkspace.shared.open`.
  A no-op guard here is a functional regression, not cosmetic.
- **[Medium #20] Re-run the UIKit sweep by SYMBOL USAGE, not `import UIKit`.** Real count is ~24 imports /
  ~230 files, and several files use UIKit types with NO import via SwiftUI re-export:
  `UIImpactFeedbackGenerator` (`TotpCardView.swift:81`), `UIImage` (`ProfileAvatarView.swift:29`),
  `UIGraphicsImageRenderer`/`UIImage` (`MainTabView.swift:105-108`). Also `AppTheme.swift` uses UIKit
  only in a doc comment → VaultifyCore real UIKit files = 2 (`ColorHex.swift`, `MeshGradientRenderer.swift`),
  not 3. Grep by type symbol to find every macOS compile break.
- **[Medium #19] Re-estimate: 3-4d undercounts** the sweep + Argon2 macOS KAT + sandbox container debug +
  3-platform compile/launch. Note: P3's iCloud-entitlement `Project.swift` edit collides with this
  phase's Project.swift work → serialize (P3 is not fully parallel).
