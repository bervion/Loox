---
title: "Safari Web Extension (Loox for Safari)"
description: "3rd appex target: iOS Safari MV3 web extension for identity + credit-card fill, signup assist, save prompts; passwords/passkeys stay with Credential Provider"
status: pending
priority: P2
effort: 44h
branch: main
tags: [safari-web-extension, appex, tuist, autofill, identity-fill, credit-card-fill]
created: 2026-07-12
---

# Safari Web Extension — Loox for Safari

Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` (cited as "report §N").

## Scope (locked)

- New appex `com.bervion.vaultify.safari`, display name "Loox", MV3, **non-persistent background PAGE — NOT service worker** (iOS ≥17.4 SW permanently-killed bug, report §2).
- Net-new value: Safari toolbar presence, **Identity fill**, **credit-card fill**, custom-field detection, signup assist, save prompt pre-iOS-26.2. Passwords/passkeys/OTP stay with Credential Provider; extension NEVER renders inline credential UI for standard login fields (1P precedent, report §4).
- v1 includes inline menu + signup assist, phased so inline overlay lands after popup-driven fill works.
- macOS Safari extension: deferred, note only (report §8 P6) — web bundle is reusable; new macOS appex target later, keep `.when([.ios])` on the iOS embed.

## SECURITY INVARIANT (threads through every phase)

Vault Key & bulk vault NEVER cross native→JS. Only per-item field values, only on explicit user tap. HTTPS-only fill; visibility/focus checks; cross-origin iframe fill denied (until Phase 5 gate); origin from `browser.tabs` (trusted), never content-script-reported; CC number decrypted only at fill moment, last-4 masked in popup, nothing sensitive in `browser.storage`. (report §3, §7)

## Phases

| # | Phase | File | Status | Effort | Blockers |
|---|-------|------|--------|--------|----------|
| 1 | Tuist target + skeleton + device gates G1/G2 | [phase-01](phase-01-tuist-target-and-extension-skeleton.md) | code complete — device gates G1/G2 pending (user) | 6h | — |
| 2 | Unlock bridge + popup read path | [phase-02](phase-02-unlock-bridge-and-popup-read-path.md) | pending | 6h | P1 (G1+G2 PASS) |
| 3 | Fill engine: classifier + identity + card fill | [phase-03](phase-03-fill-engine-identity-and-credit-card.md) | pending | 10h | P2 |
| 4 | Signup assist + generated password + save prompt | [phase-04](phase-04-signup-assist-and-save-prompt.md) | pending | 8h | P3 |
| 5 | Inline menu + iframe CC + iPad | [phase-05](phase-05-inline-menu-and-iframe-cc.md) | pending | 10h | P4 |
| 6 | Security review + hardening + release readiness | [phase-06](phase-06-security-review-and-hardening.md) | pending | 4h | P5 |

## Device-QA gates (blocking)

- **G1 (P1, BLOCKING)**: Face ID via `BiometricKeyStore.retrieve` from headless `SafariWebExtensionHandler` on device, popup-initiated. Fallback locked in P1.
- **G2 (P1, BLOCKING)**: `manifest.json` + `_locales/` discovered by Safari when packaged via Tuist folder-reference resource. Verify appex layout before any web-layer work.
- **G3 (P2)**: per-site permission flow + `tabs`-derived origin correct on device.
- **G4 (P4)**: no double save prompt on iOS 26.2+ (native `SupportsSavePasswordCredentials` already ON, `Project.swift:187`).
- **G5 (P5)**: inline menu on top-20 site sample; Stripe-style iframe CC behind per-frame origin check.

## Key dependencies

- Existing plumbing (verified): App Group `group.com.bervion.vaultify` + shared keychain group (`VaultifyCore/SharedConfig.swift:8,18`), `BiometricKeyStore.retrieve(reason:)` (`VaultifyCore/Keychain/BiometricKeyStore.swift:54`), host matching `matchesAutoFill` (`VaultifyCore/Models/VaultItem.swift:131`), `.card`/`.identity` templates (`VaultifyCore/Models/ItemCategory.swift:62-77`), `PasswordGenerator.generate` (`VaultifyCore/PasswordGenerator.swift:42`), `VaultWriter.createLogin` (`VaultifyCore/VaultWriter.swift:22`).
- Signing/CI: new bundle id + App Group + keychain-sharing in portal; fastlane match profile regen before release (runbook: `docs/deployment-guide.md`). Dev builds run on automatic signing meanwhile.
- No vault schema change anywhere → rollback per phase = revert commits; P1 rollback = delete target block + dependency from `Project.swift`, `tuist generate`.

## File ownership (no overlap)

P1: `Project.swift`, `VaultifySafari/**` (new). P2: `VaultifySafari/**`, `VaultifyCore/WebExtensionReader.swift` (new), popup JS. P3: content-script JS (`field-classifier.js`, `fill-engine.js`). P4: `signup-detector.js`, `save-overlay.js`, `VaultifySafari` save handler. P5: `inline-menu.js`. `Localizable.xcstrings` + `_locales/` edited serially per phase (orchestrator-owned convention).
