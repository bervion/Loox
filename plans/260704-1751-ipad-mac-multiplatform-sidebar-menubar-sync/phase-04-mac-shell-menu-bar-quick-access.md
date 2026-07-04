---
phase: 4
title: "Mac Shell & Menu Bar Quick Access"
status: pending
priority: P2
effort: "5-7d + on-device QA"
dependencies: [1, 2]
---

# Phase 4: Mac Shell & Menu Bar Quick Access

## Overview

Give the Mac app a native shell: proper window sizing/toolbar, a **menu bar (status bar) icon**
with a 1Password-style **Quick Access** popover (search + copy password/TOTP without opening the
main window), and a **macOS AutoFill Credential Provider** extension so Safari/apps autofill on Mac.

## Requirements

- Functional: `MenuBarExtra` shows the Loox icon in the macOS status bar; clicking opens Quick Access.
- Functional: Quick Access = search field + result list; ⏎/click copies password (or TOTP) to clipboard,
  auto-clears like in-app. Requires unlock (Touch ID) if vault locked.
- Functional: macOS AutoFill extension fills passwords/passkeys/OTP in Safari + apps.
- Functional: Main window has a native macOS look (sidebar from P2, toolbar, min window size).
- Non-functional: Quick Access respects auto-lock; never exposes secrets while locked.
- Non-functional: EN + VI; theme/light-dark correct on macOS.

## Architecture

**Scene composition** (`VaultifyApp.swift`):
```
WindowGroup { AdaptiveRootView() }              // main window (sidebar)
#if os(macOS)
MenuBarExtra("Loox", image: …) { QuickAccessView() }.menuBarExtraStyle(.window)
Settings { MacSettingsView() }                  // ⌘, native settings
#endif
```

**Quick Access** (`Vaultify/Features/QuickAccess/` — new, macOS-first, reuse core):
- Lightweight search over the same `VaultRepository` in-memory cache; rows = title + host + copy actions.
- Locked state → Touch ID unlock inline (reuse `UnlockGate`/`BiometricAuth` from core).
- Copy via `PlatformPasteboard` (P1) with auto-clear; success uses the existing copy-toast pattern.
- **Read-only scope (Validation Session 1): search + copy only.** No quick-create in the popover;
  create/edit stays in the main window. <!-- Updated: Validation Session 1 — Quick Access read-only -->

**macOS AutoFill extension** (new target `VaultifyAutoFillMac`):
- Separate `product: .appExtension`, `destinations: [.mac]`, sources `VaultifyAutoFillMac/** + VaultifyCore/**`.
- macOS supports `ASCredentialProviderViewController` (AppKit host) — port the iOS extension's
  view-controller logic; share ceremony/passkey/reader/writer code already in `VaultifyCore`.
- Shared Keychain Access Group + App Group entitlements on the macOS bundle (mirror iOS).
- Reuses `CredentialIdentityService.refresh` publication from the app.

**Window chrome**: min size, `.windowResizability(.contentSize)`, native toolbar; privacy shield on
window-resign (`NSApplication` active state) — the P1 `PlatformAppearance` hook.

## Related Code Files

- Create: `Vaultify/Features/QuickAccess/QuickAccessView.swift`, `QuickAccessSearchModel.swift`,
  `QuickAccessRow.swift`
- Create: `VaultifyAutoFillMac/` (macOS AutoFill extension: `CredentialProviderViewController.swift`,
  entitlements, Info.plist) — logic ported from `VaultifyAutoFill/`, ceremonies shared via `VaultifyCore`
- Create: `Vaultify/Features/Settings/MacSettingsView.swift` (native `Settings` scene)
- Modify: `Vaultify/App/VaultifyApp.swift` (`MenuBarExtra` + `Settings` scenes under `#if os(macOS)`)
- Modify: `Project.swift` (new macOS extension target + embed in macOS app; entitlements)

## Implementation Steps

1. Add `MenuBarExtra` + `Settings` scenes (macOS) in `VaultifyApp`; status-bar Loox icon asset.
2. Build Quick Access popover (search + copy + inline Touch ID unlock) reusing repo/core.
3. Scaffold `VaultifyAutoFillMac` extension target in `Project.swift`; port iOS CredentialProvider VC
   to AppKit host; wire shared Keychain group + App Group; `tuist generate`.
4. Native window chrome (min size, toolbar, resizability) + privacy shield on window resign.
5. On-device Mac QA: menu bar copy, Safari password/passkey/OTP autofill, lock/unlock, theme.

## Success Criteria

- [ ] Loox icon appears in the macOS menu bar; Quick Access opens, searches, copies password + TOTP.
- [ ] Quick Access requires Touch ID when the vault is locked; never shows secrets while locked.
- [ ] macOS AutoFill fills a password + a passkey + an OTP code in Safari on a real Mac.
- [ ] Main window: native toolbar, sensible min size, privacy shield when window resigns active.
- [ ] EN + VI, correct theme/light-dark on macOS.

## Risk Assessment

- **macOS AutoFill + menu bar CANNOT be verified on the simulator** (bike-shed trap like the dormant
  Credential Exchange) → requires a real Mac; gate the milestone on device QA.
- **App Sandbox + App Group container** must be validated on macOS (P1 flags this) or the extension
  can't read the shared sealed vault file → verify container access before wiring the extension.
- **Menu bar background lifetime**: if Quick Access must work while the main window is closed, the app
  needs to stay resident (`LSUIElement`/activation policy) — depends on Open Question 4; default keeps
  the main app running, no separate login-item agent unless confirmed.
- **Global hotkey** to summon Quick Access from anywhere is Phase 5; keep P4 to the menu-bar click.

## Red Team Amendments (2026-07-04)

- **[Critical #4] "Port the iOS AutoFill VC" is a rewrite + hits missing macOS APIs.** Verify before
  scoping:
  - `SupportsSavePasswordCredentials` / `completeSavePasswordRequest`
    (`VaultifyAutoFill/CredentialProviderViewController.swift:102,110,124`, `Project.swift:140`) is
    **unavailable on macOS** (iOS 26.2 / visionOS only) → won't compile. Drop it from the macOS
    Info.plist; macOS AutoFill = **password + passkey only**.
  - `ASOneTimeCodeCredential` / `ProvidesOneTimeCodes`
    (`CredentialProviderViewController.swift:49`, `Project.swift:136`) requires macOS 15 — **satisfied:
    deployment is macOS 15 (Validation Session 1)**, so OTP autofill IS in scope. No `#available` hedge.
    <!-- Updated: Validation Session 1 — macOS 15 baseline, OTP autofill in scope -->
    macOS AutoFill scope = **password + passkey + OTP** (only save-password stays dropped).
  - macOS `ASCredentialProviderViewController` is an **`NSViewController`** (iOS is `UIViewController`)
    → the host + `UIHostingController` embedding is a from-scratch AppKit VC, not a port.
  → Re-scope: split macOS AutoFill into its own sub-phase with its own estimate (5-7d undercounts).
- **[High #13] Menu-bar residency breaks the lock-on-background model.** Auto-lock + repo-clear are
  driven only by `scenePhase == .background` (`RootView.swift:54-87`). A resident macOS app with just
  its window closed may never deliver `.background` → the decrypted `VaultRepository` cache Quick Access
  searches stays populated for the whole login session → anyone at the Mac reads every password with no
  Touch ID. **Fix:** add a macOS-native idle/auto-lock driver independent of `scenePhase` (inactivity
  timer + lock on window-resign / `NSApplication` resign / screen-lock notification), and make Quick
  Access re-check `session.state` (not just repo contents) on every open. Blocking criterion: "after the
  auto-lock interval with the window closed, Quick Access demands Touch ID."
- **[High #12] macOS clipboard has no OS expiry** (see P1 amendment) → Quick Access copy must use the
  concealed-pasteboard + survive-termination clear, not an in-process `Task`. Do not claim iOS parity.
- **[Critical #6] Extension keychain sharing** needs `kSecUseDataProtectionKeychain` + hardened-runtime
  entitlements (P1) or the macOS ext cannot read the shared biometric Vault Key.
- **[Medium #20]** Add `Localizable.xcstrings` (Quick Access states, copy toasts, inline-unlock prompts) — EN + VI.
- **[#19]** Re-estimate; the AppKit AutoFill VC + sandbox container debugging + real-Mac QA loops are the
  heaviest, least-costed items.
