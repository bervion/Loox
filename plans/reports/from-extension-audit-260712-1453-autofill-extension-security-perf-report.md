# AutoFill Credential Provider Extension — Security / Performance / Modern-API Audit

Date: 2026-07-12
Scope: `VaultifyAutoFill/**` (~1550 LOC) + shared `VaultifyCore/**` code compiled into the extension.
Method: READ-ONLY static review. No code modified. iOS 17.3 deployment target, stable-Xcode CI ceiling.

---

## 1. Extension architecture

**Entry point** — `CredentialProviderViewController` (`ASCredentialProviderViewController`), `CredentialProviderViewController.swift:15`. Hosts SwiftUI in a `UIHostingController` child (`host(_:)` `:227`), applying the app's mirrored theme + in-app locale.

Entry points wired (`prepareCredential*` / `prepareInterface*`):
- Passwords: `prepareCredentialList(for:)` `:29`; QuickType single `prepareInterfaceToProvideCredential(for:)` `:63`.
- Silent password fill: `provideCredentialWithoutUserInteraction(for:)` `:55` — **always** returns `userInteractionRequired` (never silent-fills). Correct.
- One-time codes (iOS 18): `prepareOneTimeCodeCredentialList` `:39`, completion `:48`.
- Passkey assert (QuickType): `prepareCredentialList(for:requestParameters:)` `:167`; single `:72`.
- Passkey registration: `prepareInterface(forPasskeyRegistration:)` `:144`.
- Silent passkey registration (iOS 18): `CredentialProviderViewController+SilentPasskeys.swift:9`.
- Save/generate (iOS 26.2, `#if compiler(>=6.2)`): `prepareInterface(for savePasswordRequest:)` `:97`, `performWithoutUserInteraction(generatePasswordsRequest:)` `:134`.

**Unlock** — `UnlockGate.swift:12` is the single gate for every interactive flow (fill / save / OTP / passkey). Order: Face ID first (`BiometricKeyStore.retrieve`, shared keychain group, no Argon2, `:143`); on any failure it reveals the master-password form (`:81`) → `VaultReader.deriveVaultKey` (Argon2id unwrap, `:158`). Pre-unlocked variant (`presetKey`, `:40`) skips a 2nd Face ID for the passkey→password fallback.

**Vault decryption** — the Vault Key never persists in plaintext. `VaultKeyBundle` (`VaultKeyBundle.swift`) lives in the App Group container as JSON with `.completeFileProtection` (`:46`), holding the Vault Key wrapped under the password KEK. Face ID path pulls the raw key from a `.biometryCurrentSet` + `WhenUnlockedThisDeviceOnly` Keychain item in the shared access group (`BiometricKeyStore.swift:37`). Items decrypt via `AESGCM.open` with the Vault Key (`VaultReader.decrypt` `:91`).

**Passkeys** — `WebAuthn.swift` (P-256 / ES256, none-attestation, sign counter fixed 0). Stored sealed under Vault Key in `PasskeyRecord`; iOS 18 silent upgrades sealed under an HPKE envelope (`PasskeyEnvelope.swift`) whose public half is readable while locked, private half sealed under the Vault Key.

**Shared credentials** — recipient-side entries from `SharedCredentialsCache` (sealed cache in App Group). Every shared fill/assert passes a fail-closed live grant check against CloudKit `sharedCloudDatabase` (`SharedGrantLiveCheck.swift`) plus an absolute offline gate (`NetworkReachabilityMonitor`).

---

## 2. Security findings (severity-ranked)

### S1 — MEDIUM · Vault Key held as bare `[UInt8]` in SwiftUI `@State`, never zeroed
`UnlockGate.vaultKey: [UInt8]?` (`UnlockGate.swift:28`) and every downstream view (`AutoFillView.presetKey`, `CredentialListView.vaultKey`, `PasskeyCeremonyView.vaultKey`, `CreateLoginView`, `OneTimeCodeView`) pass the 32-byte key as a plain Swift `Array`. VaultifyCore ships `SecureBytes` (mlock + `memset_s`) and `secureZero`, but **neither is used anywhere in the extension** (grep: zero hits). The key survives in heap for the whole hosting-controller lifetime and in multiple closure captures (the passkey→password `onNoPasskey` path copies it again). Master password `@State` String (`:18`) likewise unwipeable.
Failure scenario: memory-dump / heap-inspection of a live or crashed `.appex` yields the Vault Key in clear; a swap write is possible for the `[UInt8]` copies that `SecureBytes` would have mlocked.
Fix direction: wrap the derived/retrieved key in `SecureBytes` at the `UnlockGate` boundary, borrow via `withUnsafeBytes`, and `secureZero` transient arrays on view teardown.

### S2 — LOW/MEDIUM · Silent passkey registration asserts UV=1 without any verification
`performSilentPasskeyRegistration` (`+SilentPasskeys.swift:16`) runs with no Face ID / password (by design for iOS 18 conditional upgrade). The created credential uses `WebAuthn.newCredentialFlags` = UP|UV|BE|BS (`WebAuthn.swift:24`), i.e. **User Verified = 1**, even though no user verification occurred in the silent path. RPs that trust the UV bit are told the user was verified when only automatic upgrade happened.
Note: this is a subtle spec-fidelity issue, not a leak — the silent path only *writes* a new credential (sealed to the envelope public key) and returns a registration credential; it never signs an assertion or reads existing secrets. Verify against Apple's conditional-registration guidance whether UV should be 0 on the silent write. Gated by `automaticPasskeyUpgradesEnabled` (default ON) + excluded-credential check.

### S3 — LOW · Generated password rendered inline (snapshot/screenshot surface)
`CreateLoginView` shows the freshly generated password as plain `Text(password)` (`CreateLoginView.swift:40`). No `.privacySensitive()` / redaction. The extension UI can be captured in the app-switcher snapshot. By contrast the design deliberately avoids inline secrets elsewhere: `OneTimeCodeView` never renders the live code (`OneTimeCodeView.swift:66`), `AutoFillView` rows show only title/username, `SavePasswordView` shows username but not password. Recommend `.privacySensitive()` on the generated-password row (still a new credential the user is choosing, so lower risk than an existing secret).

### S4 — INFORMATIONAL (verified safe) · Silent passkey path cannot leak assertions
Reviewed per task requirement. `+SilentPasskeys.swift` implements only `performWithoutUserInteractionIfPossible(passkeyRegistration:)` — a *registration* (write). There is **no** silent assertion override; all assertions route through `PasskeyCeremonyView` behind `UnlockGate`. `provideCredentialWithoutUserInteraction` (password) hard-returns `userInteractionRequired` (`:55`). No path returns a signed assertion or a password without an interactive auth gate. Confirmed no leak.

### S5 — INFORMATIONAL (verified safe) · Shared-credential fill is fail-closed and online-gated
`CredentialListView.select` (`AutoFillView.swift:232`) and `PasskeyCeremonyView.signShared` (`:149`) both require `hasSatisfiedNetworkPath` AND a live `SharedGrantLiveCheck.verify` returning `.authorized` before filling; `.revoked`/`.unavailable` keep the sheet up with a message (no fill). `SharedGrantLiveCheck` fails closed on `#if !VAULTIFY_ICLOUD`, deadline, or any error (`SharedGrantLiveCheck.swift:32,51`). QuickType preferred-record path routes shared hits through the same gate (`:134`). Owned items fill directly (correct — no remote authority needed). No bypass found.

### S6 — INFORMATIONAL · Logging hygiene is clean
Both `os.Logger` instances mark only counts/enums/reason-strings `.public`; usernames, passwords, RP secrets, and key bytes are never logged. Biometric error log uses `String(describing: error)` `.public` (`UnlockGate.swift:147`) — leaks an OSStatus/`LAError` code, not a secret. Acceptable.

---

## 3. Performance / memory findings

### P1 — MEDIUM/HIGH · Argon2id (64 MiB) can OOM the memory-budgeted extension on the master-password path
`VaultReader.deriveVaultKey` → `KeyHierarchy.unwrap` → `Argon2.deriveRaw` uses the bundle's stored `KdfParams`, and vaults are created with `KdfParams.standard` = **64 MiB, t=3, p=4** (grep of vault-creation sites: `VaultSession.swift:61` etc.). AutoFill extensions run under a strict jetsam memory limit; a single 64 MiB Argon2 allocation on top of SwiftUI + SwiftData + CryptoKit risks termination mid-unlock. The Face ID path avoids this entirely (key comes from Keychain), so the *common* case is safe — but users without biometrics, after a biometric failure/cancel, or after enrolled-biometrics invalidation fall back to the 64 MiB derivation inside the `.appex`.
Mitigations to consider: (a) verify current jetsam headroom on the min-spec device; (b) the codebase already defines `KdfParams.constrained` (32 MiB) but it is unused — however KDF params are fixed per-vault at creation, so this only helps future vaults; (c) ensure the derivation Task is `detached` (it is, `UnlockGate.swift:158`) and the `p=4` lanes don't multiply resident memory. Flag for on-device QA under memory pressure.

### P2 — MEDIUM · Repeated `ModelContainer` construction per flow
`VaultReader.logins()` (`VaultReader.swift:29`), `autofillPrefillUsername`→`username(forItemID:)` (`:47`), `defaultIdentityUsername` (`:59`), `totpItems` (`:83`), and `VaultReader+Spaces.swift:41` each call `VaultStore()` → a **fresh `ModelContainer`** on the same shared SQLite file. `CredentialListView.task` triggers `logins` + `SharedCredentialsCache.load` + `autofillPrefillUsername` back-to-back, standing up 2–3 containers per presentation. Container creation is the dominant cold-start cost after Argon2; multiple containers on one store file also invite SwiftData contention. Recommend opening one `VaultStore` per presentation and threading it through the reader calls.

### P3 — MEDIUM · `VaultReader.logins/totpItems/username*` use the crashing `VaultStore()` init, not `recoverable:`
`VaultStore.init()` calls `fatalError` on container-load failure (`VaultStore.swift:14`). The passkey path (`makePasskeyStore` `:210`) and `VaultWriter` correctly use `init(recoverable:)` and cancel gracefully, but the **password + OTP read paths** go through `VaultStore()` — a store-load failure (corruption, migration, protected-data-unavailable) crashes the `.appex` instead of a clean `cancel`. Inconsistent robustness for the most common flow.

### P4 — LOW · Whole-vault decrypt on every presentation
`logins()` / `totpItems()` `compactMap`-decrypt (AES-GCM) **every** record on each invocation before filtering. Fine for typical vaults; O(n) crypto latency for large ones. No per-keystroke work exists (search/matching operates on the already-decrypted in-memory array), so keystroke latency is not a concern.

### P5 — LOW · Reachability cold-start race (fail-closed, acceptable)
`NetworkReachabilityMonitor` starts `false` and updates async (`NetworkReachabilityMonitor.swift`). On a fast cold present, shared rows may be briefly hidden until the first `NWPath` update lands. Fail-closed, so correct — noted only as a possible "shared items missing for a beat" UX blip.

---

## 4. Modern Apple API adoption

### Implemented (good coverage)
| Capability | Gate | Where |
|---|---|---|
| `ProvidesPasswords` | iOS 17 | `prepareCredentialList` |
| `ProvidesPasskeys` (assert + register) | iOS 17 | `PasskeyActionView` / ceremony |
| `ProvidesOneTimeCodes` (TOTP) | iOS 18 | `OneTimeCodeView` |
| `SupportsConditionalPasskeyRegistration` (silent upgrade) | iOS 18 | `+SilentPasskeys` + HPKE envelope |
| WebAuthn `largeBlob` (read/write/registerSupport) | iOS 18 | `PasskeyLargeBlob.swift` |
| `SupportsSavePasswordCredentials` (native Save sheet) | iOS 26.2 | `prepareInterface(for savePasswordRequest:)` |
| `SupportsGeneratePasswordCredentials` (headless) | iOS 26.2 | `performWithoutUserInteraction(generatePasswordsRequest:)` |
| `ASCredentialIdentityStore` sync (password + passkey + OTP identities) | iOS 17/18 | `CredentialIdentityService` + inline `saveCredentialIdentities` |

### Missing / opportunities
- **`prepareInterfaceForUserChoosingTextToInsert` (text-to-insert provider, iOS 18+)** — NOT implemented. Would let the user insert arbitrary field values (custom fields, address, note, secondary email) into any focused text field, not just username/password. Natural fit given the vault already stores `DynamicField`s. Requires `ProvidesTextToInsert` capability. iOS 18 gate.
- **Passkey PRF extension (`ASAuthorizationPublicKeyCredentialPRF*`, iOS 18+)** — only `largeBlob` is handled; PRF (used for deriving symmetric secrets from a passkey, e.g. E2E vault unlock on web) is not. Opportunity for parity with 1Password/Bitwarden. iOS 18 gate.
- **`SupportsGeneratePasswordCredentialsWithUI` = false** (`Project.swift:190`) — generation is intentionally headless. A UI variant could offer passphrase (diceware) mode and length/symbol controls; the extension already bundles `eff_large_wordlist.txt`. Minor. iOS 26.2 gate.
- **KDF-cost negotiation for the extension** — no API, but consider provisioning a lighter Argon2 profile aware of the extension budget (ties to P1). Product decision, not an Apple API.

All iOS 18 / 26.2 code is correctly `@available`-guarded or under `#if compiler(>=6.2)`, satisfying the stable-Xcode CI ceiling. No unguarded newer-SDK usage found.

---

## 5. Prioritized recommendations

1. **P1 (mem):** QA the master-password unlock inside the `.appex` under memory pressure on the min-spec device; if it jetsams, gate a lighter Argon2 profile for the extension or push users toward the Face ID path. Highest real-world crash risk.
2. **P3 (robustness):** switch `VaultReader.logins/totpItems/username*/Spaces` to `VaultStore(recoverable:)` and cancel gracefully — remove the `fatalError` crash on the most common flow.
3. **S1 (secret hygiene):** wrap the Vault Key in `SecureBytes` at the `UnlockGate` boundary and `secureZero` transient `[UInt8]` copies; the primitives already exist in core.
4. **P2 (perf):** share one `VaultStore`/`ModelContainer` per presentation across the reader calls.
5. **S3 (leak surface):** add `.privacySensitive()` to the generated-password row in `CreateLoginView`.
6. **S2 (spec fidelity):** confirm whether silent conditional registration should set UV=0; adjust `newCredentialFlags` usage on that path if so.
7. **API growth:** evaluate `prepareInterfaceForUserChoosingTextToInsert` and passkey PRF for the next iOS-18-baseline release.

---

## Open questions
1. **KDF params are fixed at vault creation** — is there any migration that would re-wrap an existing vault to `KdfParams.constrained` for extension safety, or is 64 MiB assumed to fit the current jetsam budget? (Drives whether P1 is a code fix or a QA sign-off.)
2. **Silent passkey UV bit** — is UV=1 on `performWithoutUserInteractionIfPossible(passkeyRegistration:)` an intentional choice matching Apple's automatic-upgrade behavior, or an oversight? (S2.)
3. **Text-to-insert** — is arbitrary-field insertion a desired product capability, or deliberately out of scope for a password manager? (Determines whether the missing iOS 18 provider is a gap or a non-goal.)
4. Not audited in depth (out of extension scope): `ApprovalVerifier` / `PasskeyApprovalTransport` cryptographic correctness for the askEachTime ceremony — flagged only that its extension-side entry points fail closed under `#if !VAULTIFY_ICLOUD`.
