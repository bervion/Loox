---
title: "iPad + Mac multiplatform — sidebar, menu bar, keyboard, CloudKit sync"
description: "Expand Loox (Vaultify) from iPhone-only to iPad + native macOS: adaptive sidebar, menu bar Quick Access, keyboard shortcuts, CloudKit sync enabled."
status: pending
priority: P2
branch: "main"
tags: [multiplatform, ipad, macos, cloudkit, ui]
blockedBy: []
blocks: []
created: "2026-07-04T11:00:14.727Z"
createdBy: "ck:plan"
source: skill
---

# iPad + Mac multiplatform — sidebar, menu bar, keyboard, CloudKit sync

## Overview

Take the iPhone-only app to iPad + **native macOS** (SwiftUI multiplatform, not Catalyst),
one multiplatform target. Deliver: iPad/Mac adaptive **sidebar** (NavigationSplitView),
macOS **menu bar Quick Access** (1Password-style), **keyboard shortcuts/commands**, and
**CloudKit sync enabled** so multi-device is actually useful.

Source of truth: `plans/reports/brainstorm-260704-1751-ipad-mac-multiplatform-sidebar-menubar-sync-report.md`.
**User-locked decisions (do NOT reverse):** native macOS (multiplatform target) · enable CloudKit
sync this round · scope = all four capabilities · phasing iPad-first · 1 shared multiplatform target.

## Phasing → ship milestones

- **v1.13** = Phase 1 + 2 + 3 (user confirmed keeping sync in v1.13, validation session 1). iPad sidebar
  + macOS platform + sync with QR/Emergency-Kit key provisioning. ⚠️ P3 is heavier than first scoped
  (pairing ceremony + HPKE + Emergency-Kit import + 5 LWW fixes) → highest-risk milestone; needs
  multi-device real-hardware QA. Do NOT ship "multi-device sync works" until a 2nd device round-trips a decrypt.
- **v1.14** = Phase 4 + 5 → Mac app (Mac App Store, sandboxed) + menu bar Quick Access (read-only) +
  in-app keyboard shortcuts. macOS AutoFill = password + passkey + **OTP** (macOS 15); save-password
  unavailable on macOS. Global hotkey cut this round.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Platform Abstraction & Multiplatform Target](./phase-01-platform-abstraction-multiplatform-target.md) | Code-complete (iOS+iPad+macOS compile clean, 133 tests pass, review PASS; pending on-device macOS QA) |
| 2 | [iPad Adaptive Sidebar](./phase-02-ipad-adaptive-sidebar.md) | Code-complete (iOS+macOS compile, 133 tests pass, review PASS; pending on-device iPad QA) |
| 3 | [CloudKit Sync Enablement](./phase-03-cloudkit-sync-enablement.md) | Code-complete (LWW fixes + QR/HPKE pairing + recovery-envelope join; 147 tests, review findings fixed; ship-gated on 2-device hardware QA) |
| 4 | [Mac Shell & Menu Bar Quick Access](./phase-04-mac-shell-menu-bar-quick-access.md) | Pending |
| 5 | [Keyboard Shortcuts & Commands](./phase-05-keyboard-shortcuts-commands.md) | Pending |

## Dependency graph

```
P1 (foundation — blocks all)
├─ P2 iPad Sidebar      (needs P1)
├─ P3 CloudKit Sync     (parallel; only needs entitlements, largely independent of P1)
└─ P4 Mac Shell         (needs P1)
      └─ P5 Keyboard    (needs P2 + P4)
```

- P3 can run in parallel with P1/P2 (sync code already exists; work is provisioning + wiring + QA).
- P2 and P4 both consume the same adaptive sidebar built in P2 (Mac reuses regular-size-class layout).

## Key grounded facts (from scout)

- iPhone-only today: all 3 targets `destinations: [.iPhone]`, `TARGETED_DEVICE_FAMILY = "1"`.
- Nav = custom `MainTabView` (`Vaultify/Features/Main/`), 4 tabs, shared `vaultNavigationDestinations()`.
- **UIKit coupling moderate**: 21/208 files `import UIKit`; VaultifyCore shared touches UIKit in only
  3 files (`AppTheme.swift`, `ColorHex.swift`, `Mesh/MeshGradientRenderer.swift`).
- **Sync engine EXISTS but is NOT multi-device-ready** (red-team corrected): `CloudSyncService.swift`
  does CKContainer push/pull + whole-record LWW-by-`updatedAt`, gated by `VAULTIFY_ICLOUD`. It was
  written for a single device. Enabling it for a *second* device exposes **net-new work**, not a flag flip:
  - **Vault Key never syncs** → a 2nd device cannot decrypt pulled blobs (see P3 §Key Provisioning). CRITICAL.
  - LWW correctness bugs (delete tombstone / pin / archive not bumping `updatedAt`; single-query pull
    truncation; wall-clock skew; `markSynced` clears `dirty` mid-flight). See P3 amendments.
  - First-sync seed duplication (two default identities / two "My Vault" folders). See P3.
  So P3 = **key-provisioning design + sync-correctness fixes** + enable + provision + wire + QA.
- Passkey CloudKit sync stays **deferred** (only `VaultItem` + `VaultFolder` sync) — do not add.

## Cross-plan notes

- `260702-1011-passkey-deep-ios-integration` (in-progress): passkeys. No hard block; keep passkey
  CloudKit sync deferred here to stay consistent.
- `260625-2020-autofill-faceid-create-login` (pending): iOS AutoFill. P4 adds a **separate macOS**
  AutoFill extension target — different platform, no file conflict.

## Constraints (non-negotiable)

- API ceiling iOS 17.6 / macOS 15; guard newer APIs with `#available`. CI uses stable Xcode.
- Every new user-facing string localized **EN + VI** in `Localizable.xcstrings`.
- Token-driven design system; no hardcoded visual constants. Polaris SVG icons, not SF Symbols.
- Never add iCloud entitlement without provisioning (launch crash) — keep `VAULTIFY_ICLOUD` gate honest.
- `tuist generate` after any file/target/`Project.swift` change; build the workspace (avoid word "build" in paths).

## Open questions — RESOLVED (Validation Session 1, 2026-07-04)

1. ✅ **Vault Key provisioning = QR device-pairing + Emergency Kit fallback.** A trusted device (iOS is
   source of trust) scans the NEW device's QR; the Vault Key is HPKE-sealed to the new device's ephemeral
   key and transferred (reuse the existing `VaultKeyBundle` Curve25519_SHA256_ChachaPoly envelope infra
   from the iOS-18 passkey work). Fallback: new device enters the Recovery Key or imports the Emergency
   Kit PDF → unwraps the recovery-KEK-wrapped Vault Key. Key never leaves any device as plaintext. See P3.
2. ✅ **iCloud container + CloudKit capability = already provisioned in the portal.** P3 just adds the
   entitlement (iOS + macOS) + `VAULTIFY_ICLOUD` compile flag.
3. ✅ **macOS deployment = 15 Sequoia.** OTP autofill (`ASOneTimeCodeCredential`) enabled, not deferred.
4. ✅ **Distribution = Mac App Store → App Sandbox is MANDATORY.** Reinforces keychain data-protection +
   App-Group container fail-loud; global hotkey is out (needs Accessibility, incompatible with sandbox).
5. ✅ **Menu bar Quick Access = read-only (search + copy).** No quick-create; create/edit stays in the main window.
6. ✅ **Global system-wide hotkey = CUT this round.** Keep menu-bar click + in-app ⌘ shortcuts
   (⌘F/⌘C/⌘N/⌘L/⌘,) — those satisfy "shortcuts like 1Password" without Accessibility. Revisit later if a
   Developer-ID build is ever added.

## Red Team Review

### Session — 2026-07-04
**Findings:** 20 (20 accepted, 0 rejected) · all evidence-backed with file:line.
**Severity breakdown:** 7 Critical, 8 High, 5 Medium.
Reviewers: Security Adversary, Failure Mode Analyst, Assumption Destroyer.
Disposition: user away → applied all accepted per best judgment (amendments add tasks/decision-points,
no user-locked feature silently cut). Finding #1 fix (Vault Key provisioning) recorded as
DECISION-PENDING (recommended: sync encrypted keybundle) — awaiting user confirm.

| # | Finding | Sev | Disp | Applied To |
|---|---------|-----|------|------------|
| 1 | Vault Key never syncs → 2nd device can't decrypt | Critical | Accept | P3 §Key Provisioning |
| 2 | Delete tombstone doesn't bump `updatedAt` → resurrection | Critical | Accept | P3 |
| 3 | First-sync duplicates default identity + "My Vault" | Critical | Accept | P3 |
| 4 | macOS AutoFill: save unavailable / OTP needs macOS 15 / NSViewController rewrite | Critical | Accept | P4 |
| 5 | Multiplatform target embeds iOS-only ext → macOS won't link | Critical | Accept | P1 |
| 6 | macOS keychain missing `kSecUseDataProtectionKeychain` | Critical | Accept | P1 |
| 7 | `SharedConfig.containerURL` silent fallback masks macOS misconfig | High | Accept | P1 |
| 8 | Pin/archive changes dropped by LWW gate | High | Accept | P3 |
| 9 | Single-query pull truncates large vaults | High | Accept | P3 |
| 10 | LWW on device wall-clock → skew drops edits (use changeTag) | High | Accept | P3 |
| 11 | `markSynced` clears `dirty` mid-flight → lost edit | High | Accept | P3 |
| 12 | Clipboard auto-expiry gone on macOS (`NSPasteboard`) | High | Accept | P1/P4/P5 |
| 13 | Menu-bar residency bypasses auto-lock → vault stays decrypted | High | Accept | P4 |
| 14 | Global hotkey forces Accessibility / breaks sandbox | High | Accept | P1/P5 |
| 15 | Theme forcing assumes per-window UIKit (macOS `NSApp.appearance` is global) | High | Accept | P1 |
| 16 | "Zero-knowledge" overclaim: `useCount`+folder appearance plaintext | Medium | Accept | P3 |
| 17 | `UIApplication` no-op guard = feature loss (Open Website, keyboard dismiss) | Medium | Accept | P1 |
| 18 | iPad Stage Manager size-class flip loses detail selection | Medium | Accept | P2 |
| 19 | Effort P1/P4 undercounted; P3 not truly parallel (shares Project.swift) | Medium | Accept | plan/P1/P3 |
| 20 | UIKit surface undercounted (usage w/o import); EN+VI strings unbudgeted | Medium | Accept | P1/P2/P3/P4 |

### Whole-Plan Consistency Sweep
- Reconciled the stale "sync code already complete → flip a flag" claim (Key grounded facts + P3) with
  Finding #1/#2/#3/#8-11 → P3 now scoped as key-provisioning + correctness fixes, not enablement only.
- Milestone note updated: v1.13 sync is conditional on the Vault Key provisioning decision.
- Effort/parallelism note (Finding #19): P3 shares the `Project.swift` iCloud-entitlement edit with P1 →
  not fully parallel; serialize the entitlement change. P1/P4 effort re-flagged in phase amendments.
- Localization (Finding #20): `Localizable.xcstrings` added to P2/P3/P4 Related Code Files below.
- No unresolved contradictions remain in the written plan. Open design decisions (#1 mechanism, macOS
  14/15, sandbox, hotkey) are tracked in Open Questions, not contradictions.

## Validation Log

### Session 1 — 2026-07-04
Verification pass skipped: `## Red Team Review` already carries file:line-verified evidence (no
`[UNVERIFIED]` tags remain). 7 critical decision-points interviewed; all resolved.

| # | Decision | Choice | Propagated to |
|---|----------|--------|---------------|
| 1 | Vault Key → 2nd device | **QR device-pairing (HPKE, reuse Curve25519 envelope) + Emergency-Kit import** | P3 §Key Provisioning |
| 2 | iCloud container/capability | **Already provisioned** — just add entitlement + `VAULTIFY_ICLOUD` | P3 |
| 3 | macOS deployment | **macOS 15 Sequoia** (OTP autofill enabled) | P1, P4 |
| 4 | Distribution | **Mac App Store → App Sandbox mandatory** | P1, P4, P5 |
| 5 | Quick Access scope | **Read-only (search + copy)** | P4 |
| 6 | Sync phasing | **Keep P3 in v1.13** (accept heavier first milestone) | plan milestones |
| 7 | Global hotkey | **Cut** — keep menu-bar click + in-app ⌘ shortcuts | P5 |

**Impact notes:**
- Key provisioning reuses existing HPKE envelope (`VaultKeyBundle` Curve25519_SHA256_ChachaPoly, added
  for iOS-18 silent passkey upgrades) — a real head-start, but pairing UI + Emergency-Kit import + LWW
  fixes make P3 the heaviest, highest-QA phase. New-user-first-on-Mac just creates a fresh vault (no
  pairing needed); pairing only applies when adding a device to an existing vault.
- macOS 15 baseline removes the P4 OTP `#available` hedge — OTP autofill is in scope. Save-password
  credential API is still macOS-absent → drop `SupportsSavePasswordCredentials` from the macOS plist.
- Mac App Store = sandbox → global hotkey is technically out anyway; decision #7 is self-consistent.
  Sandbox makes the keychain `kSecUseDataProtectionKeychain` + App-Group container fail-loud fixes
  non-optional.

### Whole-Plan Consistency Sweep — Validation Session 1
- Milestone block: reconciled to v1.13 = P1+P2+P3 (user kept sync in v1.13); removed the "conditional/may
  slip" hedge, kept the risk note.
- Open Questions: all 6 marked RESOLVED with the chosen answers.
- P3 §Key Provisioning: "DECISION PENDING (sync keybundle)" superseded by QR-pairing + Emergency-Kit
  (see phase-03 propagation). No stale "sync keybundle via CloudKit" recommendation should remain.
- P1 deployment: macOS 14 → **15**; add mandatory App Sandbox entitlements.
- P4: OTP hedge removed (macOS 15 baseline); Quick Access fixed to read-only.
- P5: global hotkey + `GlobalHotKey.swift` removed from scope; in-app + menu-bar shortcuts retained.
- No unresolved contradictions remain. Plan is implementation-ready pending the noted real-hardware QA.
