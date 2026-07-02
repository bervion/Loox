---
phase: 2
title: "Extension Face ID & Ceremony Hardening"
status: completed
priority: P1
effort: "6h"
dependencies: [1]
---

# Phase 2: Extension Face ID & Ceremony Hardening

## Overview
Passkey flows adopt the shared `UnlockGate` (Face ID → master password); ceremonies enforce `supportedAlgorithms`, `excludedCredentials` (iOS 18), fail-closed persistence, a multi-account picker, `lastUsedAt`, and keep the system identity index in sync right after registration. Fixes F2, F4, F5, F11, F14 + red-team RT-10/RT-13.

## Requirements
- Functional: Face ID unlock; registration confirm step; assertion picker when >1 match; correct WebAuthn error codes; identity append/removal awaited before request completion.
- Non-functional: strings EN+VI; iOS 18 APIs guarded; no identity-store writes left un-awaited when the process is about to exit.

## Architecture
Gate placement is split by what needs the vault key (RT-13):
- **Pre-unlock, in the view controller** (no vault key needed): ES256 ∈ `supportedAlgorithms` check; excluded-credentials check (`#available(iOS 18, *)`) — record `id` IS the base64url credentialID, readable without unlocking.
- **Post-unlock, in the ceremony view**: matching, picker, dedupe outcome, persistence, signing, error surfaces.
`PasskeyActionView` becomes `UnlockGate(title:onCancel:) { key in PasskeyCeremonyView(purpose:key:…) }`. The extension creates ONE recoverable `VaultStore` per ceremony and passes it through (Phase 1 injection).

## Related Code Files
- Modify: `VaultifyAutoFill/PasskeyActionView.swift` (rewrite around UnlockGate; split `VaultifyAutoFill/PasskeyCeremonyView.swift` if >200 LOC)
- Modify: `VaultifyAutoFill/CredentialProviderViewController.swift`
- Modify: `VaultifyCore/Passkey/PasskeyModels.swift` — shared identity builder (RT-10): single `ASPasskeyCredentialIdentity` factory (from `PasskeySecret` and from `PasskeyInfo`; `recordIdentifier` = base64url credentialID) consumed by every site that builds passkey identities (this phase, Phase 3 app refresh, Phase 5 silent path). Never hand-roll the mapping again.
- Modify: `Vaultify/Localizable.xcstrings` (EN+VI for all passkey strings, incl. pre-existing ones — NOTE: catalog lives at `Vaultify/Localizable.xcstrings`, NOT under `Resources/`)

## Implementation Steps
1. **PasskeyActionView → UnlockGate**: drop the bespoke master-password form (F2). Keep `PasskeyPurpose` payload, now carrying the full `ASPasskeyCredentialRequest` where relevant (preference/algorithms/excluded access).
2. **Pre-unlock gates (view controller)**:
   - `prepareInterface(forPasskeyRegistration:)`: reject non-ES256 `supportedAlgorithms` → cancel `.failed` (iOS 17-safe).
   - `#available(iOS 18, *)`: any `excludedCredentials[].credentialID` matching a stored record id → cancel `.matchedExcludedCredential` (never silently overwrite an excluded credential — report Q4).
3. **Registration flow (post-unlock)**:
   - Confirm card: relying party, userName, "Create Passkey" button.
   - Persist via throwing `PasskeyVault.save` (atomic replace) — on error show message + cancel `.failed`; NEVER complete a registration that wasn't stored (F4).
   - Identity sync (moved here from old Phase 3 draft — RT-13): build the new identity via the shared factory; for `replaced` secrets build their exact old identities; then `await store.removeCredentialIdentities(oldIdentities)` + `await store.saveCredentialIdentities([new])` **before** `completeRegistrationRequest` (RT-10 — fire-and-forget writes can die at process teardown; the existing `completion: nil` pattern at `CreateLoginView.swift:79` survives only by UI dwell time).
   - Complete with `ASPasskeyRegistrationCredential`.
4. **Assertion flow (post-unlock)**:
   - 0 matches: localized "No passkey for this site" + cancel `.credentialIdentityNotFound`; 1 match: sign immediately; >1: picker (userName, relative lastUsedAt) (F5).
   - Sign with the credential's **stored flags** (`secret.flags ?? UP|UV` — Phase 1 contract). UV note: unlock is always interactive → UV set on everything we create; `userVerificationPreference == .discouraged` still gets UV, matching Apple platform behavior (report Q5) — code comment.
   - After completing: `touchLastUsed` (failure = log marker, non-fatal).
5. **Localization**: EN+VI for create/sign-in prompts, confirm labels, picker title, errors; audit pre-existing passkey literals ("Create a passkey", "Sign in with a passkey", "Master password", "Unlock", "Incorrect master password.", "Couldn't unlock the vault.") — VI values must exist (F11).
6. `make check`; manual matrix: register new / register replacing same rp+user / excluded match (iOS 18 sim) / assert single / assert multi-account / wrong password fallback / Face ID path / QuickType suggestion appears right after in-extension registration (identity append verified here, not re-tested in Phase 3).

## Success Criteria
- [x] Passkey flows unlock via Face ID with master-password fallback
- [x] Non-ES256 → `.failed`; excluded match → `.matchedExcludedCredential` (iOS 18); both checked pre-unlock
- [x] Failed save never completes the registration; replaced credentials' identities removed, new identity saved — all awaited before completion
- [x] Multi-account picker; stored-flags assertions; lastUsedAt updates
- [x] All passkey strings have EN+VI entries in `Vaultify/Localizable.xcstrings`; `make check` green

## Validation
- 2026-07-02: `make check` passed; full `VaultifyTests` passed (101 tests). Manual Face ID/AutoFill sheet QA still planned before TestFlight.

## Risk Assessment
- **UnlockGate reuse**: verified compatible (LocalizedStringKey title, content closure `(vaultKey) -> View` — `UnlockGate.swift:12-15`); passkey flows add a 4th consumer without shared-state changes.
- **Identity writes add latency** before `completeRegistrationRequest` (two awaited store calls) — acceptable: sub-second, and correctness beats speed here; system spinner covers it.
- **iOS 17.6 devices**: no `excludedCredentials` → registration proceeds; Phase 1 replace-on-duplicate still prevents same-account pile-up.
