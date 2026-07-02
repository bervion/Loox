# Red-Team Plan Review — Assumption Destroyer + Scope Auditor

Plan: `plans/260702-1011-passkey-deep-ios-integration/` (plan.md + phases 1–7)
Reviewer role: hostile assumption destroyer; assigned verification role: SCOPE AUDITOR (state lifetime boundaries).
All evidence grep-verified against working tree (main, v1.6.0) and iPhoneOS 27.0 SDK interfaces.

---

## Finding 1: Phase 5 re-provisioning is built on a false key-rotation premise

- **Severity:** High
- **Location:** Phase 5, step 1 ("Re-provision on master-password change / vault erase") + Risk "Password-change window"
- **Flaw:** Plan claims "envelope private key sealed under OLD vault key becomes garbage" after a master-password change and mandates an ordered migrate-then-rotate step inside the change-password path. The Vault Key NEVER rotates on password change: `changeMasterPassword` unwraps the existing key and `rewrapWithPassword` re-wraps the **same** `keyBytes` under the new KEK. The envelope private key sealed under the Vault Key stays perfectly openable. The plan also ignores `recover(recoveryKey:newPassword:)` — a second "set new password" path — which by its own (wrong) logic would need the same hook, proving the rule was invented, not derived from code.
- **Failure scenario:** Implementer wires envelope rotation + forced envelope-record migration into `changeMasterPassword`. Any bug in that added machinery (rotate before migrate, throw mid-sequence, store unavailable) strands envelope-sealed passkeys or blocks password changes — in exchange for zero benefit. The only trigger that truly matters is vault erase/re-create (new Vault Key), which needs an envelope wipe in `AppEnvironment.eraseEverything()`.
- **Evidence:** `Vaultify/Security/VaultSession+Recovery.swift:43-66` (same `keyBytes` re-wrapped); `VaultifyCore/Crypto/KeyHierarchy.swift:5-9` ("generated once at vault creation and only ever stored *wrapped*"); `Vaultify/App/AppEnvironment.swift:41-45` (erase path).
- **Suggested fix:** Delete the password-change hook and the "Password-change window" risk row. Keep exactly one invalidation trigger: vault erase/reset (`eraseEverything` / `resetVault`) wipes `passkey-envelope.json`; provisioning on next unlock regenerates. Document that vault-key stability across password changes is the invariant the envelope relies on.

## Finding 2: Phase 5 names a nonexistent CryptoKit ciphersuite and the wrong Swift override

- **Severity:** High
- **Location:** Phase 5, "Architecture" + step 4
- **Flaw:** (a) `HPKE.Ciphersuite.Curve25519_SHA256_AES_GCM_256` does not exist. SDK presets: `P256_SHA256_AES_GCM_256`, `P384_SHA384_AES_GCM_256`, `P521_SHA512_AES_GCM_256`, `Curve25519_SHA256_ChachaPoly`, `XWingMLKEM768X25519_SHA256_AES_GCM_256` (iOS 26+). Neither researcher report mentions HPKE/Curve25519 at all — the symbol was invented by the planner. (b) Step 4's override `performPasskeyRegistrationWithoutUserInteractionIfPossible(_ request:)` is the ObjC selector; the Swift name is `performWithoutUserInteractionIfPossible(passkeyRegistration:)` (`NS_SWIFT_NAME`), and it already takes `ASPasskeyCredentialRequest` — the planned gate "`request` is `ASPasskeyCredentialRequest`" is dead code.
- **Failure scenario:** Compile error on the ciphersuite constant forces an on-the-spot, undocumented crypto decision (ChaChaPoly preset vs P-256+AES-GCM preset vs custom `init(kem:kdf:aead:)`). The chosen suite is frozen into the on-disk envelope format (`encapsulatedKey || ciphertext`) — an improvised pick that later gets "corrected" bricks previously sealed silent-upgrade records.
- **Evidence:** CryptoKit swiftinterface `iPhoneOS27.0.sdk/.../CryptoKit.swiftmodule/arm64e-apple-ios.swiftinterface:119-130` (preset list + `public init(kem:kdf:aead:)`); `AuthenticationServices.framework/Headers/ASCredentialProviderViewController.h:226` (NS_SWIFT_NAME + typed parameter); `grep HPKE|Curve25519` over both researcher reports → no matches.
- **Suggested fix:** Decide the suite in the plan, with rationale: simplest is the existing preset `Curve25519_SHA256_ChachaPoly` (X25519, no AES requirement for this use) or `P256_SHA256_AES_GCM_256` if AES-GCM consistency with the vault is wanted. Encode a version byte in the envelope file for future agility. Correct the override name; drop the type-check gate.

## Finding 3: Phase 1 PasskeyVault tests are unimplementable as specced — and destructive if attempted

- **Severity:** High
- **Location:** Phase 1, steps 4 & 7 ("Tests — PasskeyVaultTests (in-memory `VaultStore(recoverable: true)`)")
- **Flaw:** Every `PasskeyVault` method constructs its **own** `VaultStore` internally; the plan changes that to `try VaultStore(recoverable: false)` — still hardcoded, still the on-disk store at `SharedConfig.storeURL`. No store/context injection is added anywhere in the plan, so a test constructing an in-memory `VaultStore(recoverable: true)` has no way to make `PasskeyVault` use it. `VaultifyTests` is hosted by the app (Tuist unit-test target depending on the app), so `SharedConfig.containerURL` resolves to the real App Group container.
- **Failure scenario:** `PasskeyVaultTests` run against the developer's actual simulator vault: the "eraseAll clears PasskeyRecord" test wipes real records (items + folders too — `eraseAll` deletes everything); save/dedupe tests leave junk passkeys that then surface in QuickType via Phase 3. Tests are order-dependent and flaky on CI. Secondary cost: Phase 3 routes app-side reads through `PasskeyVault`, so every `reload()` (called after every CRUD) constructs a fresh `ModelContainer` alongside the app's long-lived one — per-edit container churn contradicting "PasskeyVault remains the only store gateway."
- **Evidence:** `VaultifyCore/Passkey/PasskeyVault.swift:13,21` (`VaultStore()` per call); `VaultifyCore/SharedConfig.swift:35-41` (real container/store URL); `Project.swift:157-168` ("Hosted by the app", `dependencies: [.target(name: "Vaultify")]`); `Vaultify/Data/Repositories/VaultRepository.swift:118,145,173,209` (reload after every mutation); `Vaultify/App/AppEnvironment.swift:23,28` (app already owns a `VaultStore`).
- **Suggested fix:** Add explicit plan step: `PasskeyVault` gains a `store:`/`context:` parameter (or becomes an instance over an injected `VaultStore`), app passes `AppEnvironment.store`, extension constructs `try VaultStore(recoverable: false)` once per ceremony, tests pass `VaultStore(recoverable: true)`. This fixes testability AND the in-app double-container churn in one move.

## Finding 4: Phase 3 hauls passkey PRIVATE KEYS into the app-side UI cache

- **Severity:** Medium
- **Location:** Phase 1 step 3 (`StoredPasskey { let secret: PasskeySecret; … }`) + Phase 3 step 1 (`VaultRepository.passkeys: [StoredPasskey]`)
- **Flaw:** `StoredPasskey` embeds the full `PasskeySecret`, which includes `privateKeyRaw`. `VaultRepository.passkeys` feeds PasskeysScreen, ItemDetail sections, and identity refresh — none of which need the private key (identities need rp/userName/credentialID/userHandle; UI needs metadata). Passwords in `items` are decrypted because the app displays/copies them; passkey private keys have **zero** app-side use. Contradicts Phase 3's own non-functional requirement ("only non-secret data leaves the vault") in spirit: signing keys sit in an `@Observable` object graph for the whole unlock session.
- **Failure scenario:** Any future app-side feature touching `repository.passkeys` (export, debug dump, logging, SwiftUI preview fixtures) is one `Codable` call away from serializing raw signing keys; memory-scraping surface grows for no functional gain.
- **Evidence:** `VaultifyCore/Passkey/PasskeyModels.swift:7-15` (`privateKeyRaw` in `PasskeySecret`); phase-01 step 3 definition; Phase 3 consumers need no key material (`CredentialIdentityService.swift:14-31` pattern; Phase 4 detail sheet shows rp/userName/dates/credentialID only).
- **Suggested fix:** Split the read model: `PasskeyVault.all/matching` returns full secrets (extension signing path); a separate `PasskeyVault.metadata(key:) -> [PasskeyInfo]` (rp, userName, userHandle, credentialID, createdAt, lastUsedAt — no `privateKeyRaw`) feeds `VaultRepository.passkeys` and both UI surfaces.

## Finding 5: Phase 5 silent-path dedupe is a guaranteed no-op; duplicates become permanent at migration

- **Severity:** Medium
- **Location:** Phase 5, step 3 ("`saveEnvelope` mirrors `save` minus dedupe-by-decrypt … dedupe by record id only") + step 4
- **Flaw:** Record id = base64url of the **freshly generated random** credentialID (`CryptoRandom.bytes(16)` per registration), so "dedupe by record id" can never match an existing record — it dedupes nothing. The best-practices report's own unresolved question #1 states the system may re-offer upgrades per fill. The migration step (open envelope records on unlock → rewrite vault-sealed) performs no rp+userHandle reconciliation, so silent-path duplicates are laundered into permanent vault records, bypassing the Phase 1 replace-on-reregister semantics (report Q7) the plan just built.
- **Failure scenario:** RP re-triggers a conditional upgrade for the same account (user signed in with password again; RP unaware of our stored passkey). Extension seals a second envelope record + appends a second QuickType identity for the same rp+userName. RP keeps only the newest credential server-side → the older suggestion is dead; user sees two identical entries, one of which always fails. Repeats indefinitely; vault and identity store accumulate corpses.
- **Evidence:** `VaultifyCore/Passkey/WebAuthn.swift:24` (random credentialID per registration); `VaultifyCore/Passkey/PasskeyModels.swift:19-31` (id = base64url credID); researcher best-practices report "Unresolved Questions" #1 (re-trigger unknown).
- **Suggested fix:** Add a reconciliation step to the unlock-time migration: after opening envelope records, apply the Phase 1 dedupe (same rp+userHandle → keep newest, delete older, prune identity store with the replaced IDs). Optionally also gate the silent path on "no existing record for rp" using a plaintext rp column — but note that requires adding rp as a plaintext column (privacy trade-off) — otherwise accept dupes until unlock and reconcile then.

## Finding 6: Identity append can be dropped by extension teardown right after request completion (Phases 3 & 5)

- **Severity:** Medium
- **Location:** Phase 3, step 3; Phase 5, step 4 ("… → append `ASPasskeyCredentialIdentity` → `completeRegistrationRequest`")
- **Flaw:** `saveCredentialIdentities` is asynchronous. The existing extension precedent the plan cites is fire-and-forget (`completion: nil`) and survives only because a UI dwell (user taps Done) keeps the process alive. In the silent path there is no dwell: `completeRegistrationRequest` fires immediately after the append is *enqueued*, and completion tears the extension process down. The plan never states the append must be awaited.
- **Failure scenario:** Silent upgrade succeeds, identity write is killed mid-flight → success criterion "suggestible immediately" fails intermittently. Worse for Phase 5 than Phase 3: the vault may stay locked for days, so no app-side `reload()` repairs the identity store until then — the user's shiny new passkey is invisible to QuickType the entire time.
- **Evidence:** `VaultifyAutoFill/SavePasswordView.swift:69`, `VaultifyAutoFill/CreateLoginView.swift:79` (`saveCredentialIdentities([identity], completion: nil)` — the cited pattern); `CredentialProviderViewController.swift:188-192` (registration completes synchronously after save today).
- **Suggested fix:** Make the ordering explicit in both phases: `await store.saveCredentialIdentities(...)` (async variant) — and for the replaced-ID prune, `await removeCredentialIdentities(...)` — **before** calling `completeRegistrationRequest`. Budget the few ms; the ceremony already did Argon2/HPKE work.

## Finding 7: Phase 3's SecureBytes→[UInt8] "bridging accessor" is self-contradictory and ignores the existing pattern

- **Severity:** Medium
- **Location:** Phase 3, step 1 ("repository holds `SecureBytes`, PasskeyVault takes `[UInt8]` — add a bridging accessor rather than duplicating key material")
- **Flaw:** Any accessor returning `[UInt8]` **is** a duplication: `SecureBytes.bytes` already exists and copies key bytes into an unlocked, non-zeroized Swift `Array` (the class doc says exactly that). So the instruction "accessor, not duplication" is unsatisfiable as stated — and it implies writing a new accessor that already exists. The codebase's established bridge is the opposite direction: `AESGCM` has `SecureBytes` overloads that scope the borrow via `withUnsafeBytes`.
- **Failure scenario:** Implementer adds a second `.bytes`-style accessor believing it avoids copies; `reload()` (after every CRUD) then mints a fresh unprotected Vault Key array per call, multiplying key residue in heap memory — precisely what `SecureBytes` (mlock + memset_s) exists to limit.
- **Evidence:** `VaultifyCore/Crypto/SecureBytes.swift:33-34` (`var bytes: [UInt8]` — "Callers are responsible for the resulting Array"); `VaultifyCore/Crypto/AESGCM.swift:24-30` (SecureBytes overload pattern); `VaultifyCore/Passkey/PasskeyVault.swift:11,20,30` (`key: [UInt8]` API); `Vaultify/Security/VaultSession.swift:29` (`vaultKey: SecureBytes?`).
- **Suggested fix:** Replace the step with: add `SecureBytes` overloads to `PasskeyVault` (mirroring `AESGCM`), keeping `[UInt8]` variants for the extension path. No new accessor on `SecureBytes`.

## Finding 8: BE/BS=1 decision misattributes its cited source; account-lockout risk for a sync-less vault is unassessed

- **Severity:** Medium
- **Location:** plan.md "Key decisions — Flags"; Phase 1, step 1 ("we choose constant 1|1 … — best-practices report Q2")
- **Flaw:** The cited report section 2 recommends the opposite of what the plan attributes to it: "Set BS=1 **only if** credential is actively synced/backed up at registration time"; summary table: "BS based on current state." Vaultify is zero-backend; `PasskeyRecord` is excluded even from the (compile-gated-off) CloudKit sync (scout F15); "device-backup-able" depends entirely on the user having backups enabled. The 1Password/Bitwarden precedent for constant 1|1 comes from providers with **actual server-side sync**. Phase 1's risk table covers only flag consistency vs TestFlight credentials — not the RP-behavior consequence of advertising a recoverable credential that may not be.
- **Failure scenario:** RP sees BS=1 → per the report's own "RP Usage" note, risk-adjusts by dropping the password fallback for the account. User loses the phone with no device backup → the only credential (a local-only passkey) is gone → permanent account lockout that BE/BS honesty would have prevented.
- **Evidence:** best-practices report §2 ("Vault-Based Provider Recommendation", "RP Usage") vs `plans/.../phase-01-...md:31`; scout report F15 (PasskeyRecord unsynced); `VaultifyCore/Store/VaultStore.swift:40-90` (sync paths are ItemRecord/FolderRecord only).
- **Suggested fix:** This is a user-decision item, not an implementer default: present the trade-off (constant 1|1 for industry-lookalike behavior + future sync/export story vs BE=1/BS=0 honest-local until sync ships — noting BS is mutable per spec, so 0→1 later is legal, while BE is immutable). Whatever is chosen, fix the citation and add the lockout consequence to the risk table.

---

## SCOPE AUDIT (assigned verification role) — state additions & lifetimes

| State addition | Lifetime classification | Instantiation/owner sites | Verdict |
|---|---|---|---|
| `VaultRepository.passkeys: [StoredPasskey]` (P3) | SESSION-SCOPED: built on `reload()`, dropped on `clear()` at lock | Single owner — `VaultRepository`, instantiated once at `AppEnvironment.swift:28`; lock/unlock wiring `RootView.swift:32-38` | PASS structurally; **FAILED content scope** — retains `privateKeyRaw` with no consumer (Finding 4) |
| `passkey-envelope.json` (App Group, P5) | PERSISTENT CROSS-PROCESS by design: public half readable locked (extension), private half sealed under Vault Key | Written by unlock hooks app+extension; read by locked silent path | PASS with corrections: erase hook required (plan has it); password-change hook is premise-false (Finding 1); wipe must land in `eraseEverything()` `AppEnvironment.swift:41-45` |
| Settings toggle in `SharedConfig.sharedDefaults` (P5) | PERSISTENT CROSS-PROCESS, non-secret | New key beside `languageKey` (`SharedConfig.swift:27-31`) | PASS; note: `UserDefaults(suiteName:) ?? .standard` fallback means a broken App Group silently splits app/extension views of the toggle (extension then honors default-ON against a user's OFF) — add the key with the fail-safe reading "absent ⇒ ON, but treat unreadable group as OFF" if strictness wanted |
| `PasskeyVault` transient `VaultStore` instances (P1/P3/P4) | PER-CALL container over the shared SQLite file | `PasskeyVault.swift:13,21` today; plan adds delete/touch/all call sites app-side | **FAILED as planned** — second-container churn in-app per `reload()` + blocks in-memory tests; needs injection (Finding 3) |
| `PasskeyRecord` new columns `lastUsedAt`/`envelopeSealed`/`largeBlobSealed` (P1/5/6) | Persistent, store-scoped, NOT synced | Model file only | PASS; note for F15 follow-up: `PasskeyRecord` has no `updatedAt`, so the whole-record LWW sync model has nothing to gate on when sync is eventually enabled — document in the F15 note |
| No new singletons introduced; no existing state already serves these purposes (no passkey cache exists anywhere under `Vaultify/Features` — scout F3 confirmed by grep) | — | — | PASS |

## Verified-OK claims (no finding)

- `UnlockGate` reuse fits: `title: LocalizedStringKey, onCancel, content: ([UInt8]) -> Content` (`UnlockGate.swift:12-15`); only change: current prompt is `LocalizedStringResource` (`CredentialProviderViewController.swift:159-160`) → pass a `LocalizedStringKey`.
- `ASCOSEAlgorithmIdentifier.ES256` exists (`ASCOSEConstants.h:4-9`, typed-extensible-enum → Swift `.ES256`).
- `excludedCredentials` is iOS 18 on `ASPasskeyCredentialRequest` (`ASPasskeyCredentialRequest.h:69`); `supportedAlgorithms` iOS 17 (`:67`).
- `ASPasskeyCredentialIdentity(relyingPartyIdentifier:userName:credentialID:userHandle:recordIdentifier:)` exists (`ASPasskeyCredentialIdentity.h:31`).
- `prepareInterface(forPasskeyRegistration:)` cast pattern matches existing code (`CredentialProviderViewController.swift:144-147`).
- Favicon service is host-keyed, reusable for rpId (`FaviconService.swift:30,39` — `cachedIcon(host:)`/`fetchIcon(host:)`); Phase 4's "item-bound" fallback risk is moot.
- `VaultifyTests` target exists and reaches VaultifyCore via the app host (`Project.swift:157-168`) — subject to Finding 3.
- `eraseAll` PasskeyRecord gap (scout F6) is real (`VaultStore.swift:31-35`).
- Registration/assertion flag bytes in Phase 1 tests are correct: `0x5D` / `0x1D`.
- Identity-store `isEnabled` guard: app-side guard retained (`CredentialIdentityService.swift:25`); extension-side appends need no guard (extension invoked ⇒ provider enabled) — consistent with `CreateLoginView.swift:79`.

## Unresolved questions

1. Finding 8 (BE/BS for a sync-less vault) is a product/user decision — needs explicit sign-off, not a planner default.
2. Phase 5 silent-path duplicate policy (Finding 5): reconcile-at-migration only, or also add a plaintext rp column to gate silently? The latter trades metadata privacy for correctness — user call.
3. HPKE suite choice (Finding 2): `Curve25519_SHA256_ChachaPoly` vs `P256_SHA256_AES_GCM_256` vs custom — pick before Phase 5 starts; format is frozen on disk.
