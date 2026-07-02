---
phase: 7
title: "Credential Exchange Import-Export"
status: pending
priority: P3
effort: "2d"
dependencies: [1, 4]
---

# Phase 7: Credential Exchange Import-Export — STRETCH

## Overview
Adopt the FIDO Credential Exchange flow (`ASCredentialExportManager` / `ASCredentialImportManager`, **iOS 26.0** — verified in `AuthenticationServices.swiftmodule/arm64-apple-ios-simulator.swiftinterface:824,1420,1439` with `@available(iOS 26.0, …)`; these are Swift-only APIs, which is why the SDK researcher report's ObjC-header grep reported them "not found") so users can migrate passwords AND passkeys between Vaultify and other managers (iCloud Keychain, 1Password, …) through the system-mediated, Face ID-gated transfer. No CSV, no plaintext files.

## Requirements
- Functional: export selected vault logins + passkeys as `ASImportableAccount`; import received credentials into the vault (logins → `VaultItem`, passkeys → `PasskeySecret` with private key material).
- Non-functional: `#available(iOS 26, *)` + `#if compiler(>=6.2)` (matches the existing iOS 26.2 save/generate pattern); vault must be UNLOCKED for both directions; imports deduped (rp+userHandle via Phase 1 logic; logins by host+username).

## Architecture
New `CredentialExchangeService` (app target — export/import run in the APP, not the extension) mapping vault models ↔ `ASImportableAccount`/`ASImportableItem` trees. UI hooks inside the existing `Vaultify/Features/ImportExport` screens ("Transfer to another app" / system-initiated import entry).

## Related Code Files
- Create: `Vaultify/Services/CredentialExchangeService.swift` (mapping + manager calls; split mapper file if >200 LOC)
- Modify: `Vaultify/Features/ImportExport/…` (entry points, progress/result UI)
- Modify: `Project.swift` (Info.plist capability keys required for credential exchange — verify exact keys against SDK docs at implementation; likely under `ASCredentialProviderExtensionCapabilities` for import advertising)
- Create: `VaultifyTests/CredentialExchangeMappingTests.swift`
- Modify: `Vaultify/Localizable.xcstrings`

## Implementation Steps
1. **API discovery pass** (budgeted): read `ASImportableAccount`/`ASImportableItem`/`ASImportableCredential` shapes in the swiftinterface (types confirmed present, iOS 26); identify the passkey credential payload fields (credentialID, rpId, userHandle, key material encoding — likely CXF/COSE) and the entitlement/plist requirements. Adjust the mapper design before coding.
2. **Export**: unlocked vault → user picks scope (all / selection) → build `ASImportableAccount` (logins: title/user/password/urls; passkeys: from `PasskeySecret` incl. private key) → `ASCredentialExportManager.exportCredentials` → system UI handles the receiving app + biometric gate.
3. **Import**: implement the import entry (system invokes with an `ASImportableAccount`): map items → dedupe → seal into vault (`VaultRepository.add` / `PasskeyVault.save`) → refresh identities → summary UI (imported/skipped counts).
4. **Round-trip integrity tests**: mapper unit tests both directions incl. passkey private-key byte fidelity (P-256 raw ↔ CXF encoding), unknown-item-type tolerance (skip, count, never crash).
5. Manual: iOS 26 device/sim export → iCloud Keychain, import back; verify imported passkey signs successfully at an RP.
6. Docs: user-facing note in README highlights + `docs/codebase-summary.md`.

## Success Criteria
- [ ] Export lands credentials in another manager via the system flow (passwords + passkeys)
- [ ] Import stores usable credentials (imported passkey signs at an RP); dedupe respected
- [ ] Mapping tests green; ≤17.6/18/26-guard matrix compiles on stable Xcode (`make check`)

## Risk Assessment
- **CXF payload shape unknowns** (private-key encoding, plist keys): step 1 discovery gate — if shapes are unstable in the current SDK, STOP and mark the phase deferred with findings; don't ship speculative mapping.
- **Key material handling**: exported account object holds plaintext secrets in memory during the flow — keep scope minimal, no logging, rely on system mediation; never write intermediates to disk.
- **Effort creep**: hard-boxed at 2 days; the phase is optional for release (plan.md marks it stretch).
