# Red-Team Plan Review — Security Adversary + Fact-Checker

**Plan:** 260702-1011-passkey-deep-ios-integration
**Reviewer role:** hostile security adversary; assigned verification role = FACT CHECKER
**Method:** every cited path/symbol/config key grep- or read-verified against the live codebase and the Xcode 27 iOS 27.0 SDK. Findings without file:line evidence omitted.
**Focus:** Phase 5 (HPKE envelope enabling silent locked passkey creation).

---

## Finding 1: Phase 5 re-provisions the envelope on master-password change based on a false crypto premise — unnecessary, and a passkey data-loss trap
- **Severity:** Critical
- **Location:** Phase 5, "Implementation Steps" §1 + "Risk Assessment" → "Password-change window"
- **Flaw:** Step 1 says: *"Re-provision on master-password change … (envelope private key sealed under OLD vault key becomes garbage → regenerate; hook the existing change-password + erase paths)."* This is factually wrong. In Vaultify the **Vault Key never rotates on a master-password change** — it is generated once and only ever re-*wrapped*. `KeyHierarchy.swift:5-9` states verbatim "generated once at vault creation and only ever stored *wrapped*"; `changeMasterPassword` → `rewrapWithPassword` (`VaultSession+Recovery.swift:43-66`) re-derives a KEK from the new password and re-seals **the same `keyBytes`** — it never calls `KeyHierarchy.newVaultKey()`. Therefore an envelope private key sealed under the Vault Key stays perfectly decryptable after a password change; it does **not** "become garbage."
- **Failure scenario:** A developer implements the instruction literally: on password change, regenerate the keypair (overwrite `passkey-envelope.json`). Any `PasskeyRecord.envelopeSealed` rows not yet migrated to `sealed` are sealed to the OLD envelope public key. Regeneration overwrites the OLD envelope private key → those records can never be opened → **permanent, silent passkey loss** (the private key the RP relies on is gone). The plan's "migrate FIRST, then rotate" mitigation assumes migration always ran; but the extension writes new envelope records while locked as a *separate process*, so a record can be written after the app's last `reload()`-migration and before the password change in the same session → migrate-first misses it. Meanwhile the intended security benefit (revoking envelope access by changing the password) does not exist, because the Vault Key is immutable — a stolen envelope/vault key survives any number of password changes.
- **Evidence:** `VaultifyCore/Crypto/KeyHierarchy.swift:5-9,13,22-29`; `Vaultify/Security/VaultSession+Recovery.swift:43-66`; contrast erase path `VaultSession+Recovery.swift:70-76` (`resetVault` wipes the bundle; a subsequent `createVault` → `newVaultKey()` *does* rotate — so the "erase" hook is legitimate, only the "change-password" hook is not). Plan: `phase-05-…:36,55`.
- **Suggested fix:** Drop the change-password re-provisioning entirely. Re-provision the envelope **only** on `resetVault()`/new-vault creation (where the Vault Key genuinely changes). Correct the plan's stated rationale so no one re-introduces the destructive step. If password-change-based envelope revocation is actually desired, that requires rotating the Vault Key itself (a much larger design change touching every sealed record) — call that out explicitly rather than implying the current design provides it.

---

## Finding 2: The envelope is an unauthenticated write channel promoted to trusted vault + identity state on unlock; the "attacker owns the device" dismissal is defeated by the backup vector
- **Severity:** High
- **Location:** Phase 5, "Architecture" (plaintext `publicKeyRaw`) + "Risk Assessment" → "Public-key substitution"
- **Flaw:** The plan stores `publicKeyRaw` **plaintext** beside the vault, seals silently-created passkeys to it while locked, and on unlock **opens and migrates those records into the vault and publishes them to the system identity store** (Phase 3). The write path has no way to authenticate the public key while locked (the matching private key is Vault-Key-sealed, unreadable without unlock), so a substituted or injected record is trusted until an unlock-time check that the plan leaves vague ("sanity-check envelope file integrity … regenerate if mismatched"). The plan dismisses substitution with "that attacker already owns the device/container (can read the vault file, replace the app)." That understates the threat: the App Group container ships in device/iCloud backups, and only the **plaintext public key** needs tampering — not the Argon2/AES-GCM-protected vault. An attacker who edits `passkey-envelope.json` in a backup (malicious host computer, compromised backup) never needs the master password.
- **Failure scenario:** (a) *Downgrade:* attacker swaps the plaintext pubkey in a backup for their own. After restore, the locked extension seals every silent-upgrade passkey (incl. the P-256 private key inside `PasskeySecret`) to the attacker's key. The attacker later reads those `envelopeSealed` blobs from a subsequent backup and decrypts them with **no master password** — silent-path passkeys are thus protected *below* the interactive-path bar (Argon2-derived Vault Key). (b) *Poisoning:* attacker injects an `envelopeSealed` record (sealing an attacker-chosen `PasskeySecret` to the real plaintext pubkey); on next unlock it is migrated into the vault and published as an `ASPasskeyCredentialIdentity`, polluting the user's vault/QuickType with attacker-controlled credentials. The detection step fires too late — private keys are already generated, sent to RPs, and indexed.
- **Evidence:** `phase-05-…:21-22,54`; identity publication `phase-03-…:29-30`; container layout (store + keybundle "complete file protection" beside the new unprotected JSON) `VaultifyCore/SharedConfig.swift:41-44`; zero-knowledge item model for contrast `Vaultify/Data/Repositories/VaultRepository.swift:248-253` (payloads AES-GCM under the password-derived Vault Key).
- **Suggested fix:** Bind the public key to the vault: on unlock, derive the public key from the sealed private key and **compare** to `publicKeyRaw`; on mismatch, quarantine (do not migrate) and alert, never silently regenerate-and-continue. Set an explicit file-protection class on the envelope file and mark it `isExcludedFromBackup`. Treat every `envelopeSealed` record as untrusted input at migration time (validate the P-256 key, rp/userHandle shape) before promoting to `sealed` or the identity store. Re-classify substitution/injection from "residual, accepted" to "must-mitigate," since the backup vector needs neither device ownership nor the master password.

---

## Finding 3: Locked silent registration cannot dedupe → duplicate/orphan passkeys per account, invisible to the user until Phase 4
- **Severity:** High
- **Location:** Phase 5, "Implementation Steps" §3 ("dedupe by record id only") + §4 (silent registration)
- **Flaw:** `WebAuthn.register` mints a **fresh random `credentialID` every call** (`WebAuthn.swift:24` `credentialID = Data(CryptoRandom.bytes(16))`), and `PasskeyRecord.id = base64url(credentialID)` (`PasskeyVault.swift:14`). Phase 1's real dedupe replaces by **rp + userHandle**, which requires decrypting existing records (`phase-01-…:36`). The locked silent path cannot decrypt others, so Phase 5 falls back to "dedupe by record id only" — but record ids are always unique, so this **never dedupes**. The migration step (§3) also does not dedupe.
- **Failure scenario:** iOS offers an automatic passkey upgrade each time the user signs in with a Vaultify-filled password at an upgrade-enabled RP. If that happens twice for the same account while the app stays locked (plausible across days), two envelope records are created for the same rp+userHandle. On unlock both migrate to `sealed` with no dedupe → the RP now sees multiple Vaultify passkeys for one account; the assertion picker (Phase 2 §3) shows duplicates; orphans accumulate. The user cannot see or prune them until the Phase 4 UI ships (and Phase 4 is P2, after the "shippable release" line at Phase 5).
- **Evidence:** `VaultifyCore/Passkey/WebAuthn.swift:22-32`; `VaultifyCore/Passkey/PasskeyVault.swift:11-17`; `phase-01-…:36`; `phase-05-…:38,41`.
- **Suggested fix:** Make the silent path idempotent without the Vault Key: since a silent *upgrade* carries the RP + userHandle in the request, store `base64url(rpIdHash ‖ userHandle)` as a plaintext dedupe key column on `PasskeyRecord`, and have the locked write path replace an existing envelope/`sealed` record with the same dedupe key (delete-then-insert by that plaintext key). At minimum, run rp+userHandle dedupe during the unlock-time migration so duplicates collapse on first read.

---

## Finding 4: Phase 5 cites a CryptoKit HPKE ciphersuite constant that does not exist
- **Severity:** Medium
- **Location:** Phase 5, "Architecture"
- **Flaw:** The plan specifies *"ciphersuite `P256_SHA256_AES_GCM_256`-equivalent for X25519: `Curve25519_SHA256_AES_GCM_256`."* No such predefined `HPKE.Ciphersuite` member exists. The SDK's predefined suites are only `P256_SHA256_AES_GCM_256`, `P384_SHA384_AES_GCM_256`, `P521_SHA512_AES_GCM_256`, and `Curve25519_SHA256_ChachaPoly`. An X25519 KEM with AES-GCM-256 must be built as a custom `HPKE.Ciphersuite(kem: .Curve25519_HKDF_SHA256, kdf: .HKDF_SHA256, aead: .AES_GCM_256)`, not referenced as a constant.
- **Failure scenario:** Implementer writes `HPKE.Ciphersuite.Curve25519_SHA256_AES_GCM_256` per the plan → does not compile; time lost, or an ad-hoc suite substituted without review.
- **Evidence:** SDK grep across `iPhoneOS27.0.sdk` returned ciphersuite tokens `Curve25519_SHA256_ChachaPoly` and `P256_SHA256_AES_GCM_256` only; `Curve25519_SHA256_AES_GCM_256` absent. Plan: `phase-05-…:20`.
- **Suggested fix:** Replace the constant with the explicit custom-ciphersuite construction, or use the real `Curve25519_SHA256_ChachaPoly`; state the chosen KEM/KDF/AEAD triple precisely.

---

## Finding 5: Phase 5's silent-registration override uses a Swift method name that does not match the SDK — a mismatched override is a silently dead feature
- **Severity:** Medium
- **Location:** Phase 5, "Implementation Steps" §4 + "Related Code Files"
- **Flaw:** The plan says to *"override `performPasskeyRegistrationWithoutUserInteractionIfPossible(_ request:)`."* That is the **Objective-C** selector. Its Swift name (per `NS_SWIFT_NAME`) is `performWithoutUserInteractionIfPossible(passkeyRegistration:)`. Overriding with the ObjC-spelled name in Swift matches no superclass method.
- **Failure scenario:** `override func performPasskeyRegistrationWithoutUserInteractionIfPossible(_:)` fails to compile ("method does not override any method from its superclass"); if a developer then drops `override` to make it compile, iOS never calls it → the flagship silent-upgrade feature is dead with no runtime error, and manual testing shows "no upgrade offered," which the plan pre-labels a non-bug (`phase-05-…:56`) — masking the defect.
- **Evidence:** `iPhoneOS27.0.sdk/.../AuthenticationServices.framework/Headers/ASCredentialProviderViewController.h:226`: `performPasskeyRegistrationWithoutUserInteractionIfPossible:` `NS_SWIFT_NAME(performWithoutUserInteractionIfPossible(passkeyRegistration:))` `ios(18.0)`. The cited SDK report already flagged this selector as "(inferred)" — `researcher-260702-1018-…:26,73-77`. Plan: `phase-05-…:29,39`.
- **Suggested fix:** Specify the exact Swift override: `override func performWithoutUserInteractionIfPossible(passkeyRegistration request: ASPasskeyCredentialRequest)`. Add a build-time or manual assertion that the override is actually invoked (log at entry) so a future signature drift is caught, not silently swallowed.

---

## Finding 6: Phase 7 claims credential-exchange APIs are "verified in SDK swiftinterface," but its own cited report says they were NOT found
- **Severity:** Medium
- **Location:** Phase 7, "Overview" / "Requirements"
- **Flaw:** Phase 7 states the FIDO Credential Exchange APIs are *"`ASCredentialExportManager` / `ASCredentialImportManager`, iOS 26.0 — verified in SDK swiftinterface."* The referenced SDK-availability report explicitly says the opposite: these headers were **"NOT found in the AuthenticationServices framework on this SDK … May be … not yet available. Requires further investigation."** The plan asserts a verification its own evidence base does not support.
- **Failure scenario:** A reader trusts the "verified" label and skips the discovery gate; the exact iOS availability, the passkey private-key encoding (CXF/COSE), and the required Info.plist/entitlement keys — all of which Phase 7 itself flags as unknowns — go unresolved, and speculative mapping ships. (Independent grep does show the *symbols exist* as `ASImportableAccount`/`ASCredentialExportManager` in the Swift interface, so the API is real — but the plan's cited proof is contradictory, and availability/shape remain genuinely unverified.)
- **Evidence:** Plan: `phase-07-…:13`. Contradicting source: `researcher-260702-1018-…:185` + Unresolved Q3. Symbols do exist: `iPhoneOS27.0.sdk/.../AuthenticationServices.swiftmodule/arm64e-apple-ios.swiftinterface:824` (`struct ASImportableAccount`), `:1420` (`class ASCredentialExportManager`).
- **Suggested fix:** Reconcile the claim — either re-run the SDK check against the swiftinterface and cite that file:line, or downgrade the wording to "present in the Xcode 27 swiftinterface; exact availability and passkey key-encoding pending the Phase 7 discovery gate." Do not carry a "verified" label that the linked report refutes.

---

## Finding 7: Phase 5 introduces logging the relying-party at `.public` redaction, contradicting the extension's own "non-sensitive markers only" policy
- **Severity:** Medium
- **Location:** Phase 5, "Implementation Steps" §4 (final bullet)
- **Flaw:** Step 4 says to *"Log via `autofillLog` (non-sensitive: rp only at `.public` redaction level consistent with existing logging)."* It is **not** consistent: the extension logger is documented "Non-sensitive markers only — never log usernames, passwords, or vault contents," and existing call sites log only **counts** at `.public` (`services=\(count, privacy: .public)`), never identifiers. The relying-party is the domain where the user holds an account; at `.public` it is written verbatim to the unified log and captured in sysdiagnose.
- **Failure scenario:** Anyone with device-log access (a sysdiagnose the user is social-engineered into sharing, an MDM-managed device, a forensic capture) recovers a timeline of exactly which sites Vaultify silently created passkeys for — an account-enumeration / behavioral-correlation leak that the current logging policy specifically avoids.
- **Evidence:** Policy + existing pattern: `VaultifyAutoFill/CredentialProviderViewController.swift:9` (comment) and `:35,45,98,127` (only counts/enum raw values at `.public`). Plan: `phase-05-…:42`.
- **Suggested fix:** Log the rp hashed or at `.private` (redacted by default), or log only a boolean/outcome marker ("silent upgrade: performed/skipped") with no domain. Keep the extension's identifier-free logging invariant.

---

## Verification results summary (FACT CHECKER)

Claims sampled and checked: ~22 across all 7 phases.

- **VERIFIED (true as stated):** F6 `eraseAll` omits `PasskeyRecord` (`VaultStore.swift:31-35`); `record.id == base64url(credentialID)` (`PasskeyVault.swift:14`); current zero AAGUID (`WebAuthn.swift:13`); current flags UP|UV(|AT), no BE/BS (`WebAuthn.swift:15-17,27-28,38-39`); random credentialID per registration (`WebAuthn.swift:24`); registration uses `try?` (non-propagating) today (`CredentialProviderViewController.swift:188`); `UnlockGate` exists for reuse (`UnlockGate.swift`); `PasskeyActionView` bespoke master-password form (`PasskeyActionView.swift`); `CredentialIdentityService.refresh(items:)` + replace-then-re-add-OTP ordering (`CredentialIdentityService.swift:13,27-32`); `clear()`→`removeAllCredentialIdentities` (`VaultRepository.swift:25-31`, `CredentialIdentityService.swift:50-56`); repo holds `SecureBytes`, `PasskeyVault` takes `[UInt8]` (bridging need real) (`VaultRepository.swift:248-252` vs `PasskeyVault.swift:11`); `SharedConfig.sharedDefaults`/`languageKey` (`SharedConfig.swift:27,31`); store+keybundle colocated in App Group (`SharedConfig.swift:41-44`); `matchedExcludedCredential`/`excludedCredentials` iOS 18 (SDK report + header); silent-reg ObjC selector exists, iOS 18 (`ASCredentialProviderViewController.h:226`); credential-exchange symbols exist in swiftinterface (`AuthenticationServices.swiftinterface:824,1420`); Vault Key immutable across password change (`KeyHierarchy.swift:5-9`, `VaultSession+Recovery.swift:43-66`).
- **FAILED (claim false / contradicted):** HPKE ciphersuite `Curve25519_SHA256_AES_GCM_256` does not exist in the SDK (Finding 4); Phase 5 re-provision premise "envelope key becomes garbage on password change" is false (Finding 1); Phase 7 "verified in SDK swiftinterface" contradicts the cited report's "NOT found" (Finding 6).
- **WRONG SIGNATURE:** silent-registration override Swift name is `performWithoutUserInteractionIfPossible(passkeyRegistration:)`, not the ObjC spelling the plan uses (Finding 5).

**Status:** DONE
