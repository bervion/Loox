---
name: vaultify-safari-web-extension-plan
description: Safari Web Extension plan (260712-1500) — 3rd appex, MV3 background PAGE not SW, identity+CC fill, G1/G2 device gates block everything
metadata:
  type: project
---

Plan `plans/260712-1500-safari-web-extension/` (6 phases, ~44h). New appex `com.bervion.vaultify.safari` "Loox", MV3.

**Why:** identity + credit-card fill are impossible via ASCredentialProvider — web ext is the only iOS hook. Passwords/passkeys/OTP stay with Credential Provider; extension NEVER renders inline credential UI (1P precedent).

**How to apply:**
- Background = non-persistent background PAGE, never MV3 service worker (iOS ≥17.4 permanently kills SW — forums 758346).
- Two BLOCKING device gates in P1: G1 = Face ID via BiometricKeyStore from headless SafariWebExtensionHandler (popup-initiated only); G2 = manifest.json/_locales layout under Tuist `.folderReference` (verify appex root via `/tmp/vaultify-dd/*uild/Products/.../PlugIns/`). Nothing proceeds until both PASS.
- Security invariant: only cmd `getFillPayload` ever returns field values; single item, explicit tap, https-only, visibility checks, iframe deny (P5 allowlist: Stripe/GPay), CC decrypt at fill moment, last-4 in popup, nothing sensitive in browser.storage, origin from tabs API only.
- Double-save-prompt gate (P4/G4): native-side OS ≥26.2 check → `status.capabilities.nativeSave` suppresses extension save overlay.
- Two localization systems in one target: xcstrings (native) + `_locales/en|vi` (web) — both mandatory.
- No vault schema change anywhere → rollback = revert commits; P1 rollback = remove target block from Project.swift.
- Related: [[vaultify-autofill-faceid-createlogin-plan]] (unlock precedent), [[vaultify-unit-tests]] (router/reader test pattern).
