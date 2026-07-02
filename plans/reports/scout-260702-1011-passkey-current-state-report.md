# Scout: Passkey Current State — Vaultify

Date: 2026-07-02 | Branch: main (clean, v1.6.0) | Scope: passkey feature completion, deep iOS integration

## Current architecture (what exists & works)

| File | Role | State |
|---|---|---|
| `VaultifyCore/Passkey/WebAuthn.swift` (115 L) | ES256/P-256 register + assertion, minimal CBOR, COSE EC2 key, none-attestation, signCount=0 | Solid core |
| `VaultifyCore/Passkey/PasskeyModels.swift` (41 L) | `PasskeySecret` (sealed payload: rp, userName, userHandle, credID, privKeyRaw, counter, createdAt) + `PasskeyRecord` SwiftData model (id=base64url credID, sealed, createdAt) + base64url helper | OK |
| `VaultifyCore/Passkey/PasskeyVault.swift` (36 L) | save / all / matching(rp, allowedIDs) over VaultStore, AES-GCM under Vault Key | Works, gaps below |
| `VaultifyAutoFill/CredentialProviderViewController.swift` (235 L) | `prepareInterface(forPasskeyRegistration:)`, `prepareCredentialList(for:requestParameters:)`, passkey branch in `prepareInterfaceToProvideCredential`; also passwords/OTP/save/generate | Ceremonies work end-to-end |
| `VaultifyAutoFill/PasskeyActionView.swift` (62 L) | Master-password-only unlock for passkey flows | Predates UnlockGate |
| `VaultifyAutoFill/UnlockGate.swift` (94 L) | Shared Face ID→master-password gate used by fill/save/OTP flows | NOT used by passkey flow |
| `Vaultify/Services/CredentialIdentityService.swift` (57 L) | Publishes ASPasswordCredentialIdentity + (iOS 18) ASOneTimeCodeCredentialIdentity on `VaultRepository.reload()`; `replaceCredentialIdentities` then re-add OTP | No passkey identities |
| `Project.swift:121-135` | Extension capabilities: ProvidesPasswords/Passkeys/OneTimeCodes + iOS 26.2 save/generate | ProvidesPasskeys already true |
| `VaultifyCore/Store/VaultStore.swift` | ModelContainer(ItemRecord, PasskeyRecord, FolderRecord); LWW sync for ItemRecord only | PasskeyRecord not synced |

## Findings (gaps / bugs)

- **F1 — No passkey identities in `ASCredentialIdentityStore`.** `CredentialIdentityService.refresh(items:)` builds only password+OTP identities (`CredentialIdentityService.swift:14,42`). Passkeys never appear on QuickType; direct `prepareInterfaceToProvideCredential` passkey path unreachable in practice. Biggest deep-integration gap.
- **F2 — No Face ID in passkey flows.** `PasskeyActionView` is master-password only; UnlockGate (Face ID) exists and is used by the other three flows.
- **F3 — No in-app passkey management UI.** Zero references under `Vaultify/Features/`. Users can't view/delete passkeys.
- **F4 — Registration ceremony gaps** (`CredentialProviderViewController.swift:144-148,182-193`): ignores `supportedAlgorithms` (must verify ES256 ∈ list), ignores `excludedCredentials` (iOS 18) + `matchedExcludedCredential` error, ignores `userVerificationPreference`, `try? PasskeyVault.save` swallows failure then STILL completes → RP holds credential we never stored (orphan). No dedupe: re-register same rp+userHandle piles up records.
- **F5 — Assertion picks `matches.first`** (`:169-174`): wrong account when a site has 2+ passkeys; no picker. No `lastUsedAt` tracking.
- **F6 — `VaultStore.eraseAll()` doesn't delete `PasskeyRecord`** (`VaultStore.swift:33-37`) — "Erase Vault" leaves passkey ciphertexts behind. Bug.
- **F7 — Missing BE/BS flags** (`WebAuthn.swift:15-17`): vault-backed (backup-able, optionally synced) passkeys should set BE(0x08)|BS(0x10) consistently on BOTH registration and assertion (industry practice: 1Password/Bitwarden set BE=1).
- **F8 — No iOS 18 automatic passkey upgrades** (`performPasskeyRegistrationWithoutUserInteractionIfPossible` not overridden).
- **F9 — `PasskeyVault.save` uses `VaultStore()`** (fatalError init) inside extension; recoverable init exists and is used elsewhere (`VaultStore.swift:19-22`).
- **F10 — Zero AAGUID** (`WebAuthn.swift:13`): spec-legal; non-zero + community registry lets RPs show "Vaultify" name/icon.
- **F11 — Localization:** no passkey strings have VI translations (xcstrings grep empty); extension literals ("Create a passkey", …) auto-extract EN-only → per project CLAUDE.md a bug.
- **F12 — No tests** for WebAuthn/CBOR/passkey store (VaultifyTests has none).
- **F13 — Docs stale:** `docs/codebase-summary.md:78` still lists passkeys as "Deferred".
- **F14 — Registration in extension doesn't append identity** to ASCredentialIdentityStore (contrast: `CreateLoginView.swift:75-79` does for passwords).
- **F15 — PasskeyRecord not in CloudKit sync** paths (ItemRecord only). iCloud is compile-gated OFF → defer, but document (enabling sync later silently skips passkeys).

## User decisions (2026-07-02, AskUserQuestion)

- **D1 — Scope: EXPANSION.** Everything: F1–F14 + PRF/largeBlob investigation + Credential Exchange + AAGUID registry. (F15 documented, deferred with iCloud gate.)
- **D2 — Auto-upgrade: envelope key.** HPKE-style write-only key: extension seals new passkeys with a public key (no unlock needed); reads still require vault unlock. Keeps zero-knowledge read model. Enables truly silent iOS 18 upgrades (no biometric prompt in silent path).
- **D3 — UI: attach-to-login.** Passkeys display inside matching login items (rpId ↔ `autofillHost` suffix match) + standalone Passkeys screen for orphans/all (Settings entry).

## SDK availability (verified in iPhoneSimulator27.0.sdk headers/swiftinterface)

- iOS 17.0: all core passkey provider APIs (requests, credentials, ASPasskeyCredentialIdentity, replaceCredentialIdentities generic, ASSettingsHelper.openCredentialProviderAppSettings).
- iOS 18.0: `excludedCredentials`, `matchedExcludedCredential`, `performPasskeyRegistrationWithoutUserInteractionIfPossible`, assertion/registration `ExtensionInput/Output` (largeBlob), `requestToTurnOnCredentialProviderExtension`.
- iOS 26.0: `ASCredentialExportManager` / `ASCredentialImportManager` / `ASImportableAccount` (verified swiftinterface `@available(iOS 26.0,…)`).
- PRF: **no provider-side surface** in SDK → out of scope with evidence.
- Details: `researcher-260702-1018-passkey-sdk-availability-report.md`, best practices: `researcher-260702-1011-passkey-provider-best-practices-report.md`.

## Constraints

- Deployment target iOS 17.6, CI = stable Xcode → guard everything > 17.6 (`#available(iOS 18/26, *)`; iOS 26.2 code additionally `#if compiler(>=6.2)` per existing pattern).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` → crypto/data types `nonisolated`.
- Tuist: new files need `tuist generate`; VaultifyCore compiles into BOTH targets.
- Localization: every new string EN + VI in `Localizable.xcstrings`; titles `.inAppLocalized`, runtime `appString()`.
- Local hook blocks the bare word "build" in bash paths/log names.
- Design system: tokens only (Space/Radius/Metric/.vaultType/ThemeRole), Polaris SVG icons, no SF Symbols.

## Unresolved questions

- None blocking; per-phase risks captured in plan.
