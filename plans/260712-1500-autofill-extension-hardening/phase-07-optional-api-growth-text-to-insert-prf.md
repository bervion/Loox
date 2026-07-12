# Phase 07 — Optional API Growth: Text-to-Insert + Passkey PRF (iOS 18) — DEFERRED

## Context Links

- Audit §4 "Missing / opportunities"
- Capability plist keys: `Project.swift` extension Info.plist (`.extendingDefault`; existing keys incl. `SupportsGeneratePasswordCredentialsWithUI = false` at `Project.swift:190`)
- Entry-point file: `VaultifyAutoFill/CredentialProviderViewController.swift`
- LargeBlob precedent (extension I/O plumbing to copy): `VaultifyAutoFill/PasskeyLargeBlob.swift`, wired in `PasskeyCeremonyView.swift:271-300`
- Field model: `DynamicField` (`VaultifyCore/Models/`), rendered by readers via `ItemSecret.fields`

## Overview

- **Priority**: P3 — next-release candidate, NOT part of the hardening release
- **Status**: deferred (blocked on product decisions — plan.md open questions 2 and 3)
- Two independent iOS-18-gated capabilities. Both are additive: new entry points + plist capabilities, no changes to existing flows. Planned here at design level so scoping is ready when the product decision lands.

## A. Text-to-insert provider (`prepareInterfaceForUserChoosingTextToInsert`)

- Capability: `ProvidesTextToInsert` in the extension's `ASCredentialProviderExtensionCapabilities` (add in `Project.swift` Info.plist dict — Tuist regenerate required). `@available(iOS 18, *)` override; base SDK on the stable CI Xcode already carries iOS 18 — no `#if compiler` fence needed (only 26.x APIs need that).
- Flow: override `prepareInterfaceForUserChoosingTextToInsert()` → host `UnlockGate` → new `TextToInsertView`: item list (reuse read path from phase 3: one store, `SecureBytes` key) → item detail exposing each non-protected-or-revealable `DynamicField` value → tap ⇒ `extensionContext.completeRequest(withTextToInsert:)` (verify exact completion API against the iOS 18 SDK headers on the runner — grep-the-SDK-headers lesson).
- Security posture: this is the FIRST extension surface that hands out arbitrary field values (notes, custom fields) — apply the same rules as the credential list: no inline secret rendering (show labels, reveal-on-tap with `.privacySensitive()`), protected fields require the standard unlocked state (already guaranteed by `UnlockGate`), nothing logged.
- Persona isolation: respect INV-R03 exactly as the create-flow does (`VaultReader+Spaces.swift:30-35` pattern) — never list another persona's items. Reuse `logins`-style filtering; define whether non-login categories appear (product call).
- Localization: every new string EN+VI.

## B. Passkey PRF extension

- Scope: `ASAuthorizationPublicKeyCredentialPRFAssertionInput/Output` handling in assertion requests (iOS 18+), analogous to the existing largeBlob switch in `PasskeyCeremonyView.assertionCredential`.
- Design sketch: PRF output = HMAC-style derivation from a per-credential PRF secret. CTAP2 `hmac-secret` semantics: 32-byte per-credential secret, output = HMAC-SHA-256(secret, salt1[, salt2]). Add optional `prfSecret: Data?` to `PasskeySecret` (`PasskeyModels.swift`) — generated at registration when the RP requests PRF support; sealed under the Vault Key like the private key. Envelope path (silent upgrades) must seal it too (`PasskeyEnvelope`).
- Spec-fidelity risk is high (salt hashing prefix `WebAuthn PRF` + separator, eval vs evalByCredential) — REQUIRES a dedicated research pass against the WebAuthn L3 spec + Apple docs before implementation. Do not implement from memory.
- Migration: existing passkeys have no PRF secret → report PRF unsupported for them (per spec, `enabled: false` at registration only; assertion without stored secret returns no results). No backfill.

## Requirements (when unblocked)

- Both features fully behind `@available(iOS 18, *)`; iOS 17.3 behavior unchanged; stable-Xcode CI compiles.
- Capabilities added in `Project.swift` only (never edit generated project); `tuist generate` after.
- No regression to existing QuickType/passkey/OTP flows (identity store re-sync unaffected).

## Related Code Files (projected)

- `Project.swift` — capability keys
- `VaultifyAutoFill/CredentialProviderViewController.swift` — new overrides
- New: `VaultifyAutoFill/TextToInsertView.swift`; `VaultifyCore/Passkey/PasskeyPRF.swift`
- `VaultifyCore/Passkey/PasskeyModels.swift`, `PasskeyEnvelope.swift`, `PasskeyCeremonyView.swift` — PRF plumbing

## Todo

- [ ] Product decision: text-to-insert in scope? (open question 2)
- [ ] Product decision: PRF priority? (open question 3)
- [ ] PRF spec research pass (researcher agent) before any code
- [ ] Then: split into 2 implementation phases with their own test matrices

## Success Criteria (when unblocked)

- Text-to-insert: field value lands in an arbitrary focused text field on iOS 18+, gated by unlock; nothing offered on iOS 17.
- PRF: interop test against a public PRF-consuming RP (e.g. Bitwarden web vault-style flow or webauthn.io PRF demo) returns spec-correct outputs.

## Risk Assessment

- Text-to-insert widens the data-exfil surface of the extension (any field, any focused input) — mitigated by unlock gate + explicit user tap per value; flag to user during scoping if any category should be excluded (e.g. TOTP secrets: exclude raw secret, offer current code only — mirrors `OneTimeCodeView` never rendering the live code).
- PRF: wrong derivation = silent RP-side breakage that is hard to roll back once RPs store PRF-derived keys. Ship behind a settings toggle initially.

## Next Steps

- Revisit after the hardening release ships and open questions 2-3 are answered by the user.
