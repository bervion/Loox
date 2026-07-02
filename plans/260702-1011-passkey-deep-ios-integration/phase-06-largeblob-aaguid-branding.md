---
phase: 6
title: "largeBlob & AAGUID Branding"
status: completed
priority: P3
effort: "4h"
dependencies: [2]
---

<!-- Done 2026-07-02: largeBlob provider I/O (iOS 18, sealed blob column) + version-agnostic directive; make check + 118 tests pass. AAGUID frozen 9078984A-…; community-registry PR is an external follow-up (documented in docs/codebase-summary.md). -->


# Phase 6: largeBlob & AAGUID Branding — STRETCH

## Overview
Optional polish: support the WebAuthn `largeBlob` extension provider-side (iOS 18 — SDK exposes `ASPasskeyAssertion/RegistrationCredentialExtensionInput.largeBlob`) and submit Vaultify's AAGUID to the community registry so RPs display the provider name/icon. Skippable without blocking release.

## Requirements
- Functional: registration answers largeBlob `supported`; assertion serves `read` and persists `write` blobs (sealed).
- Non-functional: everything `#available(iOS 18, *)`; blob sealed under the Vault Key (interactive ceremonies only — largeBlob is NOT part of the silent path).

## Architecture
Blob = per-credential opaque `Data`, new `PasskeyRecord.largeBlobSealed: Data?` (sealed AES-GCM like the secret). Extension I/O mapped in the ceremony view where the vault key is in hand.

## Related Code Files
- Modify: `VaultifyCore/Passkey/PasskeyModels.swift` (`largeBlobSealed: Data?`)
- Modify: `VaultifyCore/Passkey/PasskeyVault.swift` (blob read/write ops)
- Modify: `VaultifyAutoFill/PasskeyCeremonyView.swift` / `CredentialProviderViewController.swift` (extension input → output mapping, iOS 18 guards)
- Create: registry submission assets under `Design System/` export (SVG light/dark icon) — external PR to `passkeydeveloper/passkey-authenticator-aaguids`

## Implementation Steps
1. Verify exact Swift shapes at implementation time (`NS_REFINED_FOR_SWIFT` on inputs — check the refined Swift API in the swiftinterface before coding; SDK availability already confirmed iOS 18).
2. Registration: if `registrationExtensionInput.largeBlob` requests support → include `ASPasskeyRegistrationCredentialExtensionOutput(largeBlob: .init(isSupported: true))` via the iOS 18 initializer; record capability implicitly (blob column).
3. Assertion: `assertionExtensionInput.largeBlob` — `.read` → unseal + return blob (or empty if none); `.write(data)` → seal + persist, output `didWrite=true` only after successful save.
4. Tests: blob seal/unseal roundtrip, write-then-read across ceremonies (in-memory store).
5. AAGUID registry: export light/dark SVG icons from the Design System, open PR with AAGUID from Phase 1 + name "Vaultify" — document the PR link in `docs/`; no code change.
6. `make check` + `make test`; RP smoke test with a largeBlob demo RP if available (else unit-level only, mark manual step deferred).

## Success Criteria
- [ ] largeBlob write→read roundtrip passes against a test RP or unit harness
- [ ] `didWrite` reported only on durable save; no blob ever stored unsealed
- [ ] Registry PR opened (or explicitly deferred with note); 17.6 build unaffected

## Risk Assessment
- **Ecosystem reality**: few RPs use largeBlob; treat as conformance work, verify low regression surface (guarded code paths only).
- **Refined Swift API mismatch**: budgeted step 1 verification prevents building against wrong shapes; if the output initializer is unavailable pre-iOS 18 fallback path simply omits extension output (current behavior).
