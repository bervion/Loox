# Phase 7 Discovery Gate — Credential Exchange (iOS 26)

Date 2026-07-02. Gate mandated by phase-07 step 1 ("verify shapes; if unstable, STOP + defer with findings; don't ship speculative mapping"). Verified against iPhoneSimulator27.0.sdk swiftinterface + headers.

## Verified (present + stable)

- Managers: `ASCredentialExportManager(presentationAnchor:)` → `requestExport(for:) async -> ExportOptions`, `exportCredentials(_: ASExportedCredentialData) async`. `ASCredentialImportManager.importCredentials(token: UUID) async -> ASExportedCredentialData`. All `@available(iOS 26.0, *)`.
- Value tree (all `Codable, Hashable, Sendable`): `ASExportedCredentialData{accounts,formatVersion,exporterRelyingPartyIdentifier,exporterDisplayName,timestamp}` → `ASImportableAccount{id,userName,email,fullName,collections,items}` → `ASImportableItem{id,title,subtitle,favorite,scope,tags,credentials,extensions}` → `ASImportableCredential` (enum, 16 cases).
- Well-defined credential cases Vaultify can map cleanly: `.basicAuthentication{userName,password: ASImportableEditableField?}`, `.note`, `.totp`, `.creditCard`, address/identity docs → `ASImportableEditableField{id,fieldType,value,label}` with `FieldType` enum (string/concealedString/email/…).
- Passkey STRUCTURE: `.passkey(Passkey{credentialID,relyingPartyIdentifier,userName,userDisplayName,userHandle,key: Data,fido2Extensions})` — all fields map from `PasskeySecret` EXCEPT `key`.

## Unverified — load-bearing (STOP conditions)

1. **Passkey `key: Data` encoding.** Opaque `Data`; CXF expects a specific private-key encoding (COSE_Key / PKCS#8), not confirmable from headers. Vaultify holds raw 32-byte P-256 (`P256.Signing.PrivateKey.rawRepresentation`). A wrong guess **silently corrupts exported private keys** → imported passkeys fail at the RP with no local error. Needs iOS 26 device + reference manager interop round-trip to pin.
2. **Import-destination declaration.** `importCredentials(token:)` presupposes the system routes a token to the app. The extension-point / capability that registers Vaultify as an import destination is NOT in the AuthenticationServices headers; SDK grep found no credential-exchange extension-point identifier (only `ASAuthorizationErrorCredentialImport` = error code 1007, iOS 18.2). Guessing the plist/entitlement could silently never fire.

## Other constraints

- No E2E test path here (needs iOS 26 + a second credential manager + the system Transfer flow).
- Compiles out on CI: stable-Xcode builds skip `#if compiler(>=6.2)`, so any code here is never exercised in CI — only the dev Xcode 27 beta builds it.

## Recommendation

Two of three load-bearing unknowns (passkey key encoding, import destination) are unresolvable with current tools, and one carries private-key-corruption risk. Per the gate: **defer the import path + passkey-in-exchange until iOS 26 device verification.** A non-speculative subset IS buildable now if desired: the pure mapper for password/note/card/identity/TOTP + the app-initiated export invocation, unit-tested via Codable round-trip, with passkeys excluded (or their `key` behind an explicitly-flagged assumption). This is a user decision because it trades shipping-partial vs. correctness risk.

## Build outcome (user chose "build full", 2026-07-02)

Built `CredentialExchangeMapping` (login basic-auth + note + passkey ↔ `ASExportedCredentialData`) and `CredentialExchangeService` (export via `ASCredentialExportManager`; import via `ASCredentialImportManager.importCredentials(token:)` + save into the vault). Both `#if compiler(>=6.2)` + `@available(iOS 26.1, *)` (the `ASImportableItem` convenience init is 26.1, not 26.0). Passkey `key` = PKCS#8 DER (`P256.derRepresentation`), internally lossless.

**Deliberately NOT wired to any UI entry point** → the code is dormant; nothing can invoke it until device verification. This is the safe "built but not enabled" state.

**New blocking finding — SDK value types crash on the sim:** constructing any `ASImportable*` / `ASExportedCredentialData` HARD-CRASHES at runtime on the iOS 27.0 beta simulator (trap inside the SDK types, not our logic — the SDK-free key-encoding test passes; every test that builds the value tree crashed). So the mapper round-trip is **unverifiable on current tooling**; only passkey key-encoding is unit-tested (2 tests). Full suite green at 120 tests after removing the runtime-blocked round-trip tests.

### Status: code present + compiled + dormant; verification BLOCKED

Before enabling (wiring UI + shipping), on a stable iOS 26.1+ runtime/device: (1) confirm `ASImportable*` construction no longer crashes; (2) mapper export→import round-trip; (3) cross-manager passkey `key` interop (PKCS#8 DER vs COSE); (4) the import-destination capability/entry-point that delivers the token.

## Unresolved questions

1. Import-destination declaration (how iOS routes the token) — undetermined; needs device.
2. Cross-manager passkey `key` encoding — assumed PKCS#8 DER; needs interop QA.
3. `ASImportable*` runtime crash — sim-only (beta) or also on-device? Needs a device to tell.
