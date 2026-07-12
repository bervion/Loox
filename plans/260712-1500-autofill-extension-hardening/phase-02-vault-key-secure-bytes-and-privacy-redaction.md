# Phase 02 — Vault Key in SecureBytes + Privacy Redaction (S1, S3)

## Context Links

- Audit §S1, §S3
- `SecureBytes` / `secureZero`: `VaultifyCore/Crypto/SecureBytes.swift:9,45` (mlock + memset_s, already used app-side: `VaultSession.swift:29,162`)
- Bare-array boundary: `VaultifyAutoFill/UnlockGate.swift:15,28,40,145,158`
- Generated password inline: `VaultifyAutoFill/CreateLoginView.swift:40`

## Overview

- **Priority**: P1
- **Status**: completed
- The 32-byte Vault Key crosses the whole extension as plain `[UInt8]` — heap-resident, swappable, copied into closures, never zeroed. Wrap it in `SecureBytes` at the `UnlockGate` boundary (single choke point) and zero every transient array copy. Also add `.privacySensitive()` to the one inline secret render (generated password).

## Key Insights

- `SecureBytes` is a **class** — passing it down the view tree copies a reference, not bytes. One locked allocation per unlock.
- Dual overloads `[UInt8]`/`SecureBytes` already exist for `PasskeyVault` (`PasskeyVault.swift:22-77`), `AESGCM` (`AESGCM.swift:24-30`), `prepareEnvelopeOnUnlock` (`PasskeyVault+Envelope.swift:39,55`) — the ceremony views compile against either.
- Extension-only key consumers (verified no app callers): `VaultReader`, `VaultSpaceReader`, `VaultWriter`, `SharedCredentialsCache.load` (`SharedCredentialsCache.swift:100`) — change their signatures to `SecureBytes` directly. No dual overloads (YAGNI).
- Transient `[UInt8]` copies that must be `secureZero`d: `BiometricKeyStore.retrieve` result (`UnlockGate.swift:143`, returns `[UInt8]`, `BiometricKeyStore.swift:54`), `KeyHierarchy.unwrap` result inside `VaultReader.deriveVaultKey` (`VaultReader.swift:15-25`).
- **Accepted limitation**: `masterPassword` `@State` `String` (`UnlockGate.swift:18`) and `SecureField` internals cannot be zeroed in Swift — document, don't fight (matches `SecureBytes.swift:8` doc comment). Same for CryptoKit `SymmetricKey` transients inside `AESGCM`.

## Requirements

- Functional: zero behavior change; every flow (fill, create, save, OTP, passkey assert/register, passkey→password fallback) works identically.
- Security: after this phase, no extension source declares a long-lived `[UInt8]` vault key; every transient array is `secureZero`d in a `defer`.

## Architecture / Data Flow

```
BiometricKeyStore.retrieve → [UInt8] (zeroed) ─┐
VaultReader.deriveVaultKey → SecureBytes ──────┼─► UnlockGate @State SecureBytes?
                                               │        │ content(SecureBytes)
presetKey (passkey→password fallback) ─────────┘        ▼
   CredentialListView / CreateLoginView / SaveLoginView / OneTimeCode / PasskeyCeremony
        → VaultReader/VaultWriter/SharedCredentialsCache(key: SecureBytes)
        → AESGCM SecureBytes overloads (existing)
```

## Related Code Files

Modify:
- `VaultifyAutoFill/UnlockGate.swift` — `vaultKey` state, both inits, `content` closure type, biometric + master unlock paths
- `VaultifyAutoFill/AutoFillView.swift` — `presetKey` (`:10`), `CredentialListView.vaultKey` (`:100`)
- `VaultifyAutoFill/CreateLoginView.swift` — `vaultKey` (`:11`), plus `.privacySensitive()` at `:40`
- `VaultifyAutoFill/SavePasswordView.swift` — `vaultKey` (`:26`)
- `VaultifyAutoFill/OneTimeCodeView.swift` — `vaultKey` (`:26`)
- `VaultifyAutoFill/PasskeyActionView.swift` — `onNoPasskey` (`:29`), `PasskeyMigrationGate.vaultKey` (`:47`)
- `VaultifyAutoFill/PasskeyCeremonyView.swift` — `vaultKey` (`:6`), `onNoPasskey` (`:15`)
- `VaultifyAutoFill/CredentialProviderViewController.swift` — `presetKey` handoff in the passkey→password fallback path (grep `onNoPasskey` / `presetKey`)
- `VaultifyCore/VaultReader.swift` — `deriveVaultKey` returns `SecureBytes`; `logins`/`username(forItemID:)`/`defaultIdentityUsername`/`autofillPrefillUsername`/`totpItems`/`decrypt` take `SecureBytes`
- `VaultifyCore/VaultReader+Spaces.swift`, `VaultifyCore/VaultWriter.swift:23,41`, `VaultifyCore/Sharing/SharedCredentialsCache.swift:100` — key param type

## Implementation Steps

1. `UnlockGate`: `@State private var vaultKey: SecureBytes?`; `content: (SecureBytes) -> Content`; `presetKey: SecureBytes?`. Biometric path: `var raw = try await BiometricKeyStore.retrieve(...); defer { secureZero(&raw) }; vaultKey = SecureBytes(raw)`.
2. `VaultReader.deriveVaultKey`: unwrap into a local `var keyBytes`, `defer { secureZero(&keyBytes) }`, return `SecureBytes(keyBytes)`. Comment explains the why (swap/heap-dump hygiene), not the audit code, per review-audit rules.
3. Mechanical type change through the view chain and core reader/writer/cache signatures. Internals that need raw bytes borrow via `key.withUnsafeBytes` or call the existing `SecureBytes` overloads (`AESGCM.open(_:key:)` at `AESGCM.swift:28`).
4. `SharedCredentialsCache.load(vaultKey: SecureBytes)`: convert signature; internal decrypt goes through the `AESGCM` SecureBytes overload.
5. `CreateLoginView.swift:40`: `Text(password).privacySensitive()` — redacts in app-switcher snapshots. Keep Regenerate button visible.
6. Grep-verify: `grep -rn "\[UInt8\]" VaultifyAutoFill/` leaves only transient locals with `secureZero` defers (and non-key data like `credentialID: Data`).
7. Compile check both targets.

## Todo

- [x] UnlockGate boundary → SecureBytes (+ zeroed transients)
- [x] deriveVaultKey → SecureBytes
- [x] View chain + core signatures converted (`SharedCredentialsCache.load` too; `save` stays `[UInt8]` — app-side writer; cache tests updated)
- [x] `.privacySensitive()` on generated-password row
- [x] Grep sweep confirms no bare long-lived key arrays (zero `UInt8` hits in `VaultifyAutoFill/**`)
- [x] Compile check both targets (make check pass)

## Success Criteria

- No `[UInt8]` vault-key property/closure-param remains in `VaultifyAutoFill/**` (grep-verifiable).
- All extension flows manually smoke-tested (fill, create+fill, save sheet, OTP, passkey assert, passkey register, passkey→password fallback with presetKey — the fallback must NOT re-prompt Face ID, `UnlockGate.swift:37-47` semantics preserved).
- Generated password shows as redacted in the app switcher.

## Risk Assessment

- Medium-touch, low-logic change; the compiler enforces completeness. Watch: `onNoPasskey` capture (`PasskeyCeremonyView.swift:122`) previously copied the array — now shares the reference (better; one allocation).
- `SecureBytes` lifetime: held by SwiftUI `@State` until the hosting controller tears down — same lifetime as today, but now mlocked and zeroed in `deinit`. No leak-across-presentations risk beyond current behavior.

## Security Considerations

- This is defense-in-depth vs. heap dumps/swap of a live or crashed appex — the threat model is physical/forensic, not remote. Do not oversell in comments.
- Do NOT log any key-adjacent values while refactoring; existing loggers are clean (audit §S6).

## Next Steps

- Phase 3 adds a `store:` parameter to the same reader functions — land this phase first so signatures churn once per concern.
