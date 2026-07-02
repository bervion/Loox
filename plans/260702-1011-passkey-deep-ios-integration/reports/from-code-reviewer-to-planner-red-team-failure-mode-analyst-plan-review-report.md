# Red-Team Plan Review — Failure Mode Analyst

Plan: `plans/260702-1011-passkey-deep-ios-integration/` | Reviewer role: FLOW TRACER (behavioral-claim verification)
Method: traced entry→guards→branches→target for every load-bearing claim; SDK claims grep-verified against iPhoneSimulator27.0.sdk.

## Finding 1: Phase 5's key-rotation premise is false — the Vault Key never rotates on master-password change; the mandated envelope rotation manufactures a data-loss TOCTOU

- **Severity:** Critical
- **Location:** Phase 5, "Implementation Steps" step 1 + Risk "Password-change window"
- **Flaw:** Step 1 orders: "Re-provision on master-password change … (envelope private key sealed under OLD vault key becomes garbage → regenerate)". Traced flow: `ChangeMasterPasswordView.change()` → `VaultSession.changeMasterPassword` (`Vaultify/Security/VaultSession+Recovery.swift:43-55`) unwraps the SAME vault key and `rewrapWithPassword` (:57-66) rewrites only `kdfSalt`/`kdf`/`wrappedByPassword`. The doc comment states it outright: "The Vault Key is unchanged, so biometrics and the Emergency Kit stay valid" (`Vaultify/Features/Settings/ChangeMasterPasswordView.swift:3-4`). A new vault key is generated only in `createVault` (`VaultSession.swift:60`). So the envelope private key sealed under the vault key stays perfectly readable after a password change — nothing "becomes garbage."
- **Failure scenario:** Implementer follows the plan and adds migrate-then-rotate to the change-password path. Between "open+migrate all envelope records" and "rotate envelope," the extension process (iOS 18 silent upgrade) seals a NEW envelope record to the old public key — plan's own design allows this with the vault locked and app not running. Rotation then overwrites the old private key → that record is permanently unopenable; the RP has registered the credential; user is locked out of that account with no recovery. The plan creates the exact loss window it claims to mitigate. Bonus inconsistency: `recover()` (`VaultSession+Recovery.swift:25-40`) is a second set-new-password path the plan never mentions — hooks would diverge.
- **Evidence:** `Vaultify/Security/VaultSession+Recovery.swift:43-66`, `Vaultify/Features/Settings/ChangeMasterPasswordView.swift:3-4`, `Vaultify/Security/VaultSession.swift:57-73`
- **Suggested fix:** Delete rotation-on-password-change from Phase 5 entirely (nothing to do — key unchanged). Rotate only on vault erase (delete the file; see Finding 2). If rotation is ever needed, require: new keypair written to temp file, atomic swap ONLY after all envelope records are migrated in the same transaction, plus a key-generation ID in each envelope record so old-generation records are detectable instead of silently unopenable.

## Finding 2: Stale envelope file survives "Erase Everything" — every post-erase silent-upgrade passkey is permanently unreadable, and `provisionIfNeeded` can't detect it

- **Severity:** Critical
- **Location:** Phase 5, "Architecture" (provisioning: "if absent, generate") + step 1; interacts with Phase 1 step 5
- **Flaw:** Traced erase flow: `SettingsScreen.swift:145` → `AppEnvironment.eraseEverything()` (`Vaultify/App/AppEnvironment.swift:41-45`): `repository.clear()` → `try? store.eraseAll()` → `session.resetVault()` (`VaultKeyBundle.wipe()` + `BiometricKeyStore.delete()`, `VaultSession+Recovery.swift:70-76`). No step touches App Group files other than the SwiftData store. Phase 5's provisioning check is existence-based ("if absent, generate") — it cannot distinguish a valid envelope from one whose private key is sealed under a wiped vault key. The "sanity-check envelope file integrity on unlock" appears only as an optional mitigation in the risk table (for the substitution attack), not as a numbered step.
- **Failure scenario:** User erases vault → onboards a new vault (fresh vault key). `passkey-envelope.json` still holds the old plaintext public key + private key sealed under the destroyed key. Next unlock: `provisionIfNeeded` sees the file exists → skips. From then on, every iOS 18 silent upgrade seals passkeys to the orphaned public key; identities get appended, RPs register credentials, everything looks healthy — and no unlock can ever open those records. Silent, unbounded, unrecoverable loss discovered only when sign-in fails. Aggravator: `try? store.eraseAll()` (AppEnvironment.swift:43) swallows failure, so even record erasure can no-op while the key bundle is wiped.
- **Evidence:** `Vaultify/App/AppEnvironment.swift:41-45`, `Vaultify/Security/VaultSession+Recovery.swift:70-76`, `VaultifyCore/Store/VaultStore.swift:31-35`, `Vaultify/Features/Settings/SettingsScreen.swift:145`
- **Suggested fix:** Phase 5 must name `AppEnvironment.eraseEverything` explicitly: delete `passkey-envelope.json` there. Promote validation to a required provisioning step: on every unlocked provision check, attempt to open the stored private key with the current vault key; on failure → regenerate keypair, delete unopenable envelope records, prune their identities.

## Finding 3: Identity refresh is unserialized fire-and-forget Tasks — a stale in-flight refresh resurrects deleted/replaced passkeys in QuickType

- **Severity:** High
- **Location:** Phase 3, step 2 + Risk "replace-then-save race"; Phase 4, step 2
- **Flaw:** Phase 3 keeps the existing pattern; the risk note covers only intra-Task ordering ("two sequential awaits inside one Task — acceptable"). The actual hazard is inter-Task: `CredentialIdentityService.refresh` spawns an unstructured `Task` per call with no serialization or snapshot versioning (`Vaultify/Services/CredentialIdentityService.swift:23-32`, errors `try?`-swallowed). `reload()` calls `refresh` every time (`VaultRepository.swift:54`), and reload fires on unlock (`RootView.swift:34`), on EVERY scene-activation (`RootView.swift:57-59`), after every add/update/delete (`VaultRepository.swift:118,146,209`), and from sync (`AppEnvironment.swift:37`). Overlapping refreshes are routine, not rare.
- **Failure scenario:** User deletes a passkey (Phase 4: delete → reload → refresh, Task B) while an earlier refresh (Task A, pre-delete snapshot from scene-activation) is still awaiting `store.state()`. B runs replace+save; A then runs replace+save with the stale snapshot → deleted passkey re-published. User taps the QuickType suggestion → `prepareInterfaceToProvideCredential` passkey branch (`CredentialProviderViewController.swift:77-81`) → `matching` returns nothing → `.credentialIdentityNotFound` error sheet. Drift persists until the next foreground reload; "eventually consistent on next reload" is last-writer-wins by whichever Task finishes last — which can be the stale one. Same race resurrects Phase 1 dedupe-replaced credential identities.
- **Evidence:** `Vaultify/Services/CredentialIdentityService.swift:23-32`, `Vaultify/Data/Repositories/VaultRepository.swift:54`, `Vaultify/App/RootView.swift:32-59`, `VaultifyAutoFill/CredentialProviderViewController.swift:77-81,168-174`
- **Suggested fix:** Phase 3 must serialize publication: a single long-lived actor (or AsyncStream consumer) that coalesces to the latest snapshot and drops superseded ones; alternatively stamp each snapshot with a monotonic generation and abort publication if a newer generation exists.

## Finding 4: Phase 1 dedupe-replace has no transactional boundary — committed delete + failed insert destroys the user's only working credential

- **Severity:** High
- **Location:** Phase 1, step 4 (`save` dedupe); interacts with Phase 2, step 2 (fail-closed)
- **Flaw:** Step 4: "before insert, decrypt existing records for the same relyingParty + userHandle and delete them … return their credentialIDs" — no requirement that delete + insert commit atomically in one `context.save()`. Current code has one insert+save (`PasskeyVault.swift:11-17`); the plan adds a delete phase before it without specifying the transaction boundary, and Phase 1 step 7's test list has no induced-failure case for it.
- **Failure scenario:** Re-registration at an RP where the user has a working passkey: deletes commit, then the insert's `context.save()` throws (disk pressure, SQLITE_BUSY from a concurrent app-side write through the second container — see Finding 5). Phase 2 correctly cancels `.failed` → the RP never completes the new registration, its OLD credential remains valid server-side — but the old private key is now gone locally. Permanent account lockout produced by the "safe" fail-closed path. Inverse half-failure is also unhandled: save succeeds, extension is killed before `completeRegistrationRequest` (`CredentialProviderViewController.swift:192`) → vault + QuickType carry a phantom credential the RP discarded, failing forever at assertion.
- **Evidence:** `VaultifyCore/Passkey/PasskeyVault.swift:11-17`, `VaultifyAutoFill/CredentialProviderViewController.swift:182-192`
- **Suggested fix:** State as an invariant in Phase 1: replacement delete + insert MUST be one `ModelContext.save()`; add a test that an induced save failure leaves prior records intact. Note the phantom-credential residual (self-heals via rp+userHandle dedupe on retry) in the phase text.

## Finding 5: PasskeyVault's per-call throwaway `ModelContainer` + fatalError init survive on all read paths — Phases 3/5 multiply the cost and turn reads into cross-process writers

- **Severity:** High
- **Location:** Phase 1, step 4 (only `save` switched); Phase 3, step 1 (reload loads passkeys); Phase 5, step 3 (migration-on-read)
- **Flaw:** Phase 1 step 4 switches only `save` to `try VaultStore(recoverable: false)`; `all`/`matching` (and new `delete`/`touchLastUsed`) are not listed, leaving `VaultStore()` whose failure path is `fatalError` (`VaultStore.swift:10-13`, used at `PasskeyVault.swift:13,21`). Every PasskeyVault call also constructs a NEW `ModelContainer` over the same SQLite file. Phase 3 puts `PasskeyVault.all` inside `VaultRepository.reload()`, which runs on every scene-activation (`RootView.swift:57-59`) in a process that already holds a long-lived container (`AppEnvironment.swift:23`) — two coordinators per foreground, plus full passkey decrypt on the main actor. Phase 5 then makes `all`/`matching` perform migration WRITES during reads, from both processes.
- **Failure scenario:** (a) Extension assertion (`matching`) hits a transient container failure (schema migration in progress right after an app update — first opener migrates; store contention) → `fatalError` kills the AutoFill sheet mid-sign-in — the exact F9 crash class the plan claims to fix. (b) Post-Phase 5: app-foreground migration write races the extension's `touchLastUsed`/silent-upgrade insert → SQLITE_BUSY; any `try?`-styled handling silently drops the migration or the touch; the plan specifies no error policy for either. (c) Phase 2's new pre-unlock excluded-credentials check in the view controller needs record IDs — with which store init? Unspecified; the natural choice is the crash-trap `VaultStore()`.
- **Evidence:** `VaultifyCore/Passkey/PasskeyVault.swift:13,21`, `VaultifyCore/Store/VaultStore.swift:10-20`, `Vaultify/App/AppEnvironment.swift:23`, `Vaultify/App/RootView.swift:57-59`
- **Suggested fix:** Phase 1 must convert ALL PasskeyVault entry points to the throwing init and allow injecting an existing `VaultStore` (app passes `AppEnvironment.store`; extension constructs one recoverable instance per request). Phase 5 must define write-failure policy for migration/touch (retry next read; never `try?` in new code).

## Finding 6: BE/BS flag flip deterministically breaks existing TestFlight passkeys at strict RPs, and the data model can't express per-credential flags

- **Severity:** Medium
- **Location:** Phase 1, step 1 + Risk "Flag change vs existing credentials"
- **Flaw:** Current registrations emit UP|UV(|AT) with no BE/BS (`WebAuthn.swift:26-27,38-39`); stored `PasskeySecret` has no flags field (`PasskeyModels.swift:7-15`), so post-change assertions cannot reproduce registration-time flags. WebAuthn L3 makes BE immutable per credential; server libraries (e.g., SimpleWebAuthn) actively reject assertions whose BE differs from registration. The plan's own risk row concedes credentials exist ("TestFlight only") and its mitigation is ship-and-wait ("if a report surfaces, fall back per-credential").
- **Failure scenario:** TestFlight user registered at a strict RP with BE=0. After Phase 1 ships, assertions carry BE=1|BS=1 → RP rejects sign-in. Recovery requires delete + re-register, but the delete UI (Phase 4) ships two phases later — until then the user cannot even remove the broken credential in-app.
- **Evidence:** `VaultifyCore/Passkey/WebAuthn.swift:26-27,38-39`, `VaultifyCore/Passkey/PasskeyModels.swift:7-15`
- **Suggested fix:** Add an optional `flags: UInt8?` to `PasskeySecret` in Phase 1 now (Codable optional, zero migration cost): new registrations store BE|BS; assertions use stored flags, defaulting legacy records to the old UP|UV. Removes the gamble for one field.

## Finding 7: Phase 5 pins a CryptoKit HPKE ciphersuite that does not exist — the envelope format is anchored to a fiction

- **Severity:** Medium
- **Location:** Phase 5, "Architecture" (ciphersuite selection) + step 1 (file format)
- **Flaw:** Plan: "X25519: `Curve25519_SHA256_AES_GCM_256`". SDK ground truth (CryptoKit swiftinterface, iPhoneSimulator27.0.sdk, lines 120-125): only `P256_SHA256_AES_GCM_256`, `P384_SHA384_AES_GCM_256`, `P521_SHA512_AES_GCM_256`, `Curve25519_SHA256_ChachaPoly`, `XWingMLKEM768X25519_SHA256_AES_GCM_256`. There is no Curve25519+AES-GCM suite. Additionally the stored format "`encapsulatedKey || ciphertext`" carries no suite/version tag, and the silent-registration override is named wrong for Swift (`NS_SWIFT_NAME(performWithoutUserInteractionIfPossible(passkeyRegistration:))`, `ASCredentialProviderViewController.h:226`).
- **Failure scenario:** Compile error forces an ad-hoc crypto decision mid-implementation (X25519+ChaChaPoly vs P-256+AES-GCM — different key types, different key sizes, different file contents). If the seal side (extension, Phase 5 step 4) and open/provision side are implemented in separate passes against different resolutions of this ambiguity — or a beta ships one suite and a later build "corrects" it — already-provisioned envelope files and sealed records become undecodable with no version byte to detect it: silent-upgrade passkeys lost.
- **Evidence:** CryptoKit swiftinterface `iPhoneSimulator27.0.sdk …/CryptoKit.swiftmodule/arm64-apple-ios-simulator.swiftinterface:120-125`; `AuthenticationServices.framework/Headers/ASCredentialProviderViewController.h:226`
- **Suggested fix:** Pin `HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly` in the phase text (matches the X25519 intent); mandate a leading version byte in both `passkey-envelope.json` and each `envelopeSealed` blob; correct the override signature.

## Finding 8: Phase 3's identity-removal contract can't be fulfilled from Phase 1's `[Data]` return — stale-entry removal depends on undocumented matching semantics

- **Severity:** Medium
- **Location:** Phase 3, step 3; contract defined in Phase 1, step 4
- **Flaw:** Phase 1's `save` returns bare `replacedCredentialIDs: [Data]`; Phase 3 step 3 tells the extension to "call `removeCredentialIdentities(_:)` with matching passkey identities". The removal API takes full identity objects (`removeCredentialIdentityEntries:` `ASCredentialIdentityStore.h:113-124`), and `ASPasskeyCredentialIdentity` construction requires relyingPartyIdentifier + userName + credentialID + userHandle (`ASPasskeyCredentialIdentity.h:31`). The replaced record's userName was in hand during dedupe decryption but is discarded by the API shape. Whether the store matches removals by credentialID alone or full identity equality is undocumented — the plan silently bets on the former.
- **Failure scenario:** User's account email changed at the RP; re-registration replaces the old passkey (old userName ≠ new). Extension reconstructs the removal identity with the only userName it has (the new one); if the store matches on identity fields, removal misses → stale QuickType entry for the deleted credential → tap → `.credentialIdentityNotFound` (same user-visible failure as Finding 3) until the next app-side full refresh.
- **Evidence:** `ASCredentialIdentityStore.h:100-124`, `ASPasskeyCredentialIdentity.h:31` (iPhoneSimulator27.0.sdk); Phase 1 step 4 vs Phase 3 step 3 contract mismatch
- **Suggested fix:** Change Phase 1's return to the replaced `PasskeySecret`s (or prebuilt identity value objects) so removal identities are exact reconstructions.

## Finding 9: Factual path errors — four phases reference a string catalog that doesn't exist

- **Severity:** Medium
- **Location:** Phase 2 "Related Code Files"; same list in Phases 4, 5, 7
- **Flaw:** All four phases list `Modify: Vaultify/Resources/Localizable.xcstrings`. The catalog lives at `Vaultify/Localizable.xcstrings` (verified by `find` — no `Resources/` catalog exists).
- **Failure scenario:** A phase-executing agent, told to "modify" a non-existent file, creates a second catalog at the phantom path. Tuist's `Vaultify/**` glob (`Project.swift:79-80`) ingests both → strings split across two catalogs; VI translations land in the dead one; extension renders literal keys — reintroducing the exact F11 localization bug this plan is supposed to fix, while `make check` stays green (missing translations don't fail compilation).
- **Evidence:** `find Vaultify … -name "*.xcstrings"` → `Vaultify/Localizable.xcstrings` only; `Project.swift:79-80`
- **Suggested fix:** Correct the path in phases 2, 4, 5, 7.

---

## FLOW TRACER verification summary

| Claim (plan) | Traced path | Verdict |
|---|---|---|
| "envelope key sealed under OLD vault key becomes garbage" on password change (P5) | `ChangeMasterPasswordView.change()` → `changeMasterPassword` (`VaultSession+Recovery.swift:43`) → unwrap same key → `rewrapWithPassword(:57)` → only `wrappedByPassword` rewritten | **FAILED** — vault key never rotates |
| "hook the existing … erase paths" re-provisions envelope (P5) | `SettingsScreen:145` → `eraseEverything` (`AppEnvironment.swift:41-45`) → clear/eraseAll/resetVault; no App-Group file cleanup; provision check is existence-only | **FAILED** as specified (Finding 2) |
| "identities are eventually consistent on next reload" (P3 risk) | `reload()` (`VaultRepository.swift:54`) → `refresh` → unstructured `Task` (`CredentialIdentityService.swift:23`); reload fires from `RootView.swift:34,58`, CRUD paths, sync | **FAILED** — LWW by unordered Task completion |
| `try? PasskeyVault.save` then completes anyway (F4) | `prepareInterface(forPasskeyRegistration:)` (:144) → `showPasskey` → `perform(.register)` → `try?` save (:188) → `completeRegistrationRequest` (:192) unconditional | VERIFIED |
| Assertion picks `matches.first`; miss → `.credentialIdentityNotFound` (F5) | `prepareInterfaceToProvideCredential` (:77-81) → `matching` → `.first` (:170) / `cancel(.credentialIdentityNotFound)` (:174) | VERIFIED |
| `eraseAll` misses PasskeyRecord (F6) | `VaultStore.swift:31-35` deletes ItemRecord+FolderRecord only | VERIFIED |
| record `id` == base64url(credentialID), readable pre-unlock (P2) | `PasskeyVault.save` (:14) sets id from `base64URLEncodedString()`; `PasskeyRecord.id` plaintext (`PasskeyModels.swift:22`) | VERIFIED |
| `matchedExcludedCredential` iOS 18; silent-registration override iOS 18; `ASPasskeyCredentialIdentity` init + `removeCredentialIdentities` iOS 17 | SDK headers `ASExtensionErrors.h:21`, `ASCredentialProviderViewController.h:226`, `ASPasskeyCredentialIdentity.h:31`, `ASCredentialIdentityStore.h:123` | VERIFIED (Swift override name differs — Finding 7) |
| HPKE ciphersuite `Curve25519_SHA256_AES_GCM_256` (P5) | CryptoKit swiftinterface :120-125 | **FAILED** — does not exist |
| Catalog at `Vaultify/Resources/Localizable.xcstrings` (P2/4/5/7) | filesystem | **FAILED** — `Vaultify/Localizable.xcstrings` |

Unresolved questions:
- Does `ASCredentialIdentityStore` match passkey-identity removals by credentialID alone? (Finding 8 — needs empirical test or Apple confirmation.)
- Should Phase 5's "Automatic passkey upgrades" default ON given silent envelope-record creation? Product call for the user, not adjudicated here.
