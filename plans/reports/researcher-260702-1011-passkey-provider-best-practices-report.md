# Research: Apple Passkey Provider Best Practices & WebAuthn Specs
**Date:** 2026-07-02 | **Context:** Vaultify AutoFill Credential Provider | **Status:** iOS 18 + WebAuthn L3

---

## 1. iOS 18 Silent Passkey Registration (performPasskeyRegistrationWithoutUserInteractionIfPossible)

### Requirements & Conditions
- **Trigger:** Provider must have *just filled username+password* for the same account (matching username). This is the key gate.
- **Device Prerequisites:** Passcode configured, credential manager configured, non-Private browsing (web), Secure Enclave available.
- **UI Allowed:** System-level Face ID/Touch ID biometric prompts ARE allowed (implicit user verification during key creation). The term "without user interaction" means no app UI dialogs, not no biometrics.
- **Request Style:** Must use `requestStyle: .conditional` (iOS) or `mediation: "conditional"` (Web) to trigger automatic detection.

### When System Invokes It
- Automatic passkey upgrade path: After password sign-in succeeds, if no passkey exists for that account, system checks conditions above.
- Does NOT auto-trigger on browser back-forward or cached state.

### Fallback Behavior When Silent Registration Fails
- Returns `ASExtensionError` (not caught by success handler).
- No system UI shown; error is surfaced to app/web page.
- App can optionally show upsell dialog or retry later.
- **No automatic fallback to interactive registration** — provider must handle the error and decide next step.

**Sources:**
- [WWDC24: Streamline sign-in with passkey upgrades and credential managers](https://developer.apple.com/videos/play/wwdc2024/10125/)
- [WWDC24 Notes: performPasskeyRegistrationWithoutUserInteractionIfPossible](https://wwdcnotes.com/documentation/wwdcnotes/wwdc24-10125-streamline-signin-with-passkey-upgrades-and-credential-managers/)
- [Apple ASCredentialProviderViewController docs](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller/performwithoutuserinteractionifpossible(passkeyregistration:)?language=objc)

---

## 2. WebAuthn Authenticator Flags: BE & BS for Synced Passkeys

### Backup Eligibility (BE) — Bit 0x08
- **0 = Single-device:** key cannot leave the current device.
- **1 = Multi-device (synced):** key can be backed up or synced to another device.
- **Permanent:** Once set at registration, does not change for that credential.

### Backup State (BS) — Bit 0x10
- **0 = Not yet backed up:** credential has not been synced to another device.
- **1 = Backed up:** credential is currently usable on another device.
- **Mutable:** Can change between registration and authentication (e.g., user enables iCloud Keychain backup post-registration).

### Vault-Based Provider Recommendation
- **Set BE=1** if your provider syncs credentials across user's devices (e.g., via CloudKit or your own backend).
- **Set BS=1** only if credential is actively synced/backed up at registration time.
- **Do NOT always set UV flag (0x04)** — provider must honor userVerificationPreference (see Q5).

### RP Usage
- RPs use BE/BS to distinguish multi-device passkeys (phishing-resistant, less need for passwords) from single-device security keys (hardware-bound, potential account reset risk).
- Some RPs check `authenticatorAttachment.transports` + BE flag to make risk-adjusted decisions (e.g., drop password requirement only if BE=1).
- **1Password / Bitwarden practice:** Set BE=1 for vault-synced pairing, BS depends on sync state at moment of registration.

**Sources:**
- [W3C WebAuthn Level 3: Backup Eligibility & Backup State](https://www.w3.org/TR/webauthn-3/)
- [Yubico: High assurance passkey relying party](https://developers.yubico.com/Passkeys/Passkey_relying_party_implementation_guidance/High_assurance_passkey_relying_party.html)
- [NIST: Syncable Authenticators](https://pages.nist.gov/800-63-4/sp800-63b/syncable/)
- [GitHub w3c/webauthn#1933: Backup State discussion](https://github.com/w3c/webauthn/issues/1933)

---

## 3. AAGUID for Third-Party Providers with None Attestation

### Spec Legality & Practice
- **Yes, non-zero AAGUID is spec-legal with none attestation.** WebAuthn Level 3 allows AAGUID in attestationObject even with `attestation: "none"`.
- **Caveat:** Per processing rules, the AAGUID *may* be zeroed if attestation format is "none" — but this is implementation-dependent. WebKit (Safari) does NOT zero it; some mobile platforms do.
- **iOS behavior:** iCloud Keychain and third-party providers retain AAGUID even with "none" attestation.

### Benefit
- **RP display:** Allows RPs to show user a friendly provider name/icon in account settings ("Signed in with 1Password", "Bitwarden", etc.).
- **Audit & compliance:** Helps RPs track which providers their users rely on.
- **Ecosystem:** Community registry ([passkeydeveloper/passkey-authenticator-aaguids](https://github.com/passkeydeveloper/passkey-authenticator-aaguids)) encourages adoption; include your provider if shipping to production.

### Apple Requirement
- **No explicit requirement.** Apple does NOT mandate a specific AAGUID for third-party providers; zero AAGUID is valid.
- **Recommendation:** Choose or register a stable, non-zero AAGUID so RPs can identify your provider. Submit to community registry if public product.

### Vaultify Consideration
- If Vaultify is never public-facing (offline-only tool), zero AAGUID is acceptable.
- If user shares vault or credential, consider registering a community AAGUID for future interop.

**Sources:**
- [web.dev: Determine passkey provider with AAGUID](https://web.dev/articles/webauthn-aaguid)
- [Corbado: Passkey Providers — AAGUID & Adoption](https://www.corbado.com/blog/passkey-providers)
- [GitHub: Community passkey-authenticator-aaguids registry](https://github.com/passkeydeveloper/passkey-authenticator-aaguids)
- [W3C WebAuthn#2198: AAGUID with none attestation](https://github.com/w3c/webauthn/issues/2198)

---

## 4. excludedCredentials Handling in Registration

### Correct Provider Behavior
- **Match check:** During registration, if any credential in `excludedCredentials` list matches a stored credential by descriptor (credentialID + transports), provider MUST reject the request with `ASExtensionError.Code.matchedExcludedCredential`.
- **No silent overwrite:** Do NOT silently overwrite the old credential; abort and signal the error. RP will decide re-registration strategy.
- **Descriptor matching:** Must check credentialID byte-for-byte; transports is hint only (may omit transports in request).

### Error Code Semantics
- **iOS 18+:** `matchedExcludedCredential` (code 1006) — explicit duplicate signal.
- **iOS 17 & earlier:** Duplicate credentials hidden inside generic `Failed` (code 1004).
- **Since iOS 18:** Specific error code allows RP to distinguish "already registered" from other failures (network, user canceled, etc.).

### RP Compatibility
- RPs **should** use `excludedCredentials` to prevent accidental re-registration of the same passkey.
- When provider returns `matchedExcludedCredential`, RP typically shows "This passkey already exists; sign in instead" or offers update flow.

**Sources:**
- [Apple: ASExtensionError.Code.matchedExcludedCredential docs](https://developer.apple.com/documentation/authenticationservices/asextensionerror/code/matchedexcludedcredential)
- [Apple: excludedCredentials docs](https://developer.apple.com/documentation/authenticationservices/asauthorizationsecuritykeypublickeycredentialregistrationrequest/excludedcredentials)
- [Apple Passkey Error Codes Reference (2026)](https://www.corbado.com/blog/apple-passkey-error-codes)
- [WebKit bug #270553: excludeCredentials duplicate prevention](https://bugs.webkit.org/show_bug.cgi?id=270553)

---

## 5. userVerificationPreference Handling

### Spec vs. Apple Implementation
- **Spec intent:** "discouraged" = RP does NOT require UV; may skip to minimize friction.
- **Apple reality (iOS/macOS):** Always applies UV when biometrics are available (Face ID, Touch ID), regardless of RP preference.
- **Result:** Even if RP sends `userVerificationPreference: "discouraged"`, Apple sets UV flag (bit 0x04) to 1 on assertion/registration.

### Provider Best Practice
- **Always honor device capabilities:** If device has biometrics AND device is enrolled, apply UV.
- **Do NOT skip UV to match RP preference** — Apple platform does not support this on passkeys, and RPs that trust Apple's validation accept UV.
- **RP compatibility risk:** MINIMAL if you always set UV=1. RPs that explicitly require UV (preference: "required") are satisfied. RPs that prefer UV discouraged will still work (UV is orthogonal to other validation).

### Edge Case: Non-Biometric iOS Device
- If device has no biometric (Face ID, Touch ID disabled), provider may choose UP-only (UV=0), but this is rare and not recommended for vault-backed passkeys.

### Vaultify Approach
- Set `userVerificationPreference: "preferred"` or "required" in requests; apply Face ID/Touch ID at assertion.
- No need to branch on RP preference; Apple handles this transparently.

**Sources:**
- [Yubico: User Presence vs. User Verification](https://developers.yubico.com/WebAuthn/WebAuthn_Developer_Guide/User_Presence_vs_User_Verification.html)
- [Corbado: WebAuthn User Verification & User Presence](https://www.corbado.com/blog/webauthn-user-verification)
- [web.dev: userVerification deep dive](https://web.dev/articles/webauthn-user-verification)
- [WebKit bug #215836: UV option handling](https://bugs.webkit.org/show_bug.cgi?id=215836)

---

## 6. largeBlob & PRF Extensions: iOS Support

### PRF (Pseudo-Random Function) Extension
- **iOS 18+:** Supported for **iCloud Keychain passkeys only** (first-party authenticator).
- **Third-party providers:** NO support. Apple's WebAuthn implementation on iOS/iPadOS does not forward PRF extension data to external credential providers.
- **Use case:** Enables non-custodial end-to-end encryption (e.g., Dashlane, Proton Pass use PRF to derive encryption keys).
- **Status:** Enhancement, not core dependency. Treat as optional; RP fallback behavior is to ignore unsupported extensions.

### largeBlob Extension
- **iOS 17+:** Available for platform authenticator (iCloud Keychain).
- **Third-party providers:** Not documented as supported.
- **Use case:** Store auxiliary encrypted data (e.g., backup codes, additional metadata) associated with credential.

### Recommendation for Vaultify
- **Skip PRF & largeBlob in initial release.** These are niche extensions; most RPs don't require them.
- **Reason:** Apple doesn't forward extension data to third-party providers, so you can't meaningfully support them without custom workarounds.
- **Future:** If Vaultify becomes public, revisit after iOS 19+ if extension support expands.

**Sources:**
- [Corbado: Passkeys & WebAuthn PRF for End-to-End Encryption](https://www.corbado.com/blog/passkeys-prf-webauthn)
- [MDN: Web Authentication extensions](https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API/WebAuthn_extensions)
- [Yubico: Developers Guide to PRF](https://developers.yubico.com/WebAuthn/Concepts/PRF_Extension/Developers_Guide_to_PRF.html)
- [Apple Developer Forums: Large Blob support (limited)](https://developer.apple.com/forums/thread/730133)

---

## 7. Multiple Passkeys Per RP (Different userHandles)

### Correct Model
- **One userHandle per RP per user account.** All credentials for a single user account MUST share the same `userHandle` (= User ID).
- **Multiple credentials same userHandle:** Normal use case (user rotates an old passkey, or backs up same key on multiple devices). Provider should support this.
- **Different userHandles same RP:** Indicates SEPARATE user accounts (e.g., work vs. personal account on same RP). Each account is independent.

### Duplicate Registration (Same RP + Same userHandle)
- **Provider behavior:** Use `excludedCredentials` to detect and reject.
- **When RP omits excludedCredentials:** Technically allowed (provider stores both), but leads to confusion at sign-in (ambiguous which credential to use).
- **Vaultify approach:** Overwrite the old credential (update entry in vault with new credentialID + publicKey) if user explicitly re-registers for same account. Log the overwrite for audit.

### Sign-In UX (Multiple Credentials Per Account)
- **If user has 2+ passkeys for same account:** Provider picker shows "Sign in as [userHandle]" with multiple credential options (e.g., "iPhone", "YubiKey").
- **Selector:** Typically by registration date, friendly name, or device type.
- **Vaultify UI:** If vault stores multiple credentials for same RP+userHandle, present a picker in AutoFill extension.

**Sources:**
- [web.dev: Passkey Credential ID, User Handle, User ID](https://dev.to/corbado/passkey-credential-id-user-name-user-id-user-handle-20l7)
- [Corbado: Prevent multiple passkeys for one account](https://www.corbado.com/blog/passkey-providers/prevent-multiple-passkeys-for-one-account)
- [Google: Server-side passkey registration guide](https://developers.google.com/identity/passkeys/developer-guides/server-registration)

---

## 8. signCount: Zero for Synced Passkeys (Confirmed)

### Best Practice
- **Set signCount = 0 at registration.** This is the standard for all synced/vault-backed passkeys (iCloud Keychain, 1Password, Bitwarden, Dashlane, etc.).
- **Reason:** Maintaining a synchronized counter across multiple devices is impractical. Signature counters are only meaningful for single-device hardware authenticators (YubiKey, Titan).
- **RP compatibility:** RPs that validate signCount expect:
  - Single-device hardware keys: incremented counter (0 → 1 → 2 …).
  - Synced passkeys: constant 0 (RP skips counter validation for these).

### Vaultify Implementation
- **At registration:** Set `signCount = 0`.
- **At assertion:** Return `signCount = 0` (never increment).
- **Edge case:** Do NOT store old signCount; always return 0 to ensure RPs recognize this as synced.

**Sources:**
- [ImperialViolet: Signature counters](https://www.imperialviolet.org/2023/08/05/signature-counters.html)
- [W3C WebAuthn Level 3: Signature Counter Considerations](https://www.w3.org/TR/webauthn-3/)
- [GitHub w3c/webauthn#1734: Constant-zero signCount case](https://github.com/w3c/webauthn/issues/1734)
- [FusionAuth: WebAuthn signCount guide](https://fusionauth.io/docs/lifecycle/authenticate-users/passwordless/webauthn-passkeys)

---

## 9. Credential Exchange (FIDO CXF/CXP): iOS 26+ ASCredentialExportManager/ImportManager

### Overview
- **iOS 26+ / macOS 26+ / visionOS 26+:** Native credential export/import APIs via `ASCredentialExportManager` (export) and `ASCredentialImportManager` (import).
- **Protocol:** FIDO Alliance Credential Exchange Protocol (CXP) — direct app-to-app transfer, no intermediate files, no plain-text CSV.
- **Security:** User-initiated, protected by Face ID / Touch ID; OS acts as intermediary (no credentials written to filesystem mid-flight).

### What Adopting Would Involve for Vaultify
1. **Declare passkey manager capability** in Info.plist (likely a new entitlement/capability).
2. **Implement ASCredentialExportManager interface:** User taps "Export passkeys" → enumerate stored passkeys → call `exportCredentials(_:)` with selected credentials.
3. **Implement ASCredentialImportManager interface:** Receive credentials from another app via system mediator; validate + store in vault.
4. **Credential mapping:** Map between Vaultify's internal vault format (Argon2id+AES-GCM encrypted file) and FIDO CXP wire format (likely CBOR).
5. **UI flow:** Simple sheet "Export to [1Password, Dashlane, etc.]" → Face ID → done. Similarly for import.

### Effort & Priority
- **Effort:** Moderate (2–3 weeks for a careful implementation: export serialization, import validation, error handling, testing with other managers).
- **Priority:** Lower for Vaultify Phase 1. Export/import is a convenience feature, not core. Prioritize standard registration/assertion first.
- **Future:** If Vaultify becomes public or users request multi-manager workflows, revisit.

### Example Use Cases
- User switches from iCloud Keychain to Vaultify: "Export passkeys from Keychain" → import into Vaultify.
- User exports passkeys from Vaultify to send to trusted colleague via secure handoff.

**Sources:**
- [Apple: ASCredentialExportManager docs](https://developer.apple.com/documentation/authenticationservices/ascredentialexportmanager)
- [Apple: ASCredentialImportManager docs](https://developer.apple.com/documentation/authenticationservices/ascredentialimportmanager)
- [Medium: Dan Fabulich — Export/import passkeys on iOS](https://danfabulich.medium.com/you-can-export-import-passkeys-now-but-only-on-ios-3b90cddf5fe6)
- [WWDC25: What's new in passkeys](https://developer.apple.com/videos/play/wwdc2025/279/)

---

## 10. Known RP Compatibility Pitfalls for DIY WebAuthn Providers

### DER ECDSA Signature Format
- **Pitfall:** WebAuthn attestation/assertion signatures are ASN.1 DER-encoded ECDSA. RPs using Web Crypto API expect raw r|s format.
- **Fix:** Provide both formats; document clearly. Most RPs handle DER natively (FIDO Alliance reference implementations do).
- **Common error:** Passing DER to Web Crypto without conversion → signature verification fails.

### COSE Key Encoding (Public Key)
- **Pitfall:** Public key must be in COSE format (CBOR-encoded). Ensure:
  - Key type (kty): 1 (OKP), 2 (EC2), 3 (RSA) — align with your algorithm.
  - Algorithm (alg): -7 (ES256), -257 (RS256), etc. — must match the credential algorithm.
  - Coordinate encoding (for EC): x/y as raw bytes, not base64-encoded.
- **Fix:** Use a CBOR library (Swift: CBORCoding, Python: cbor2, JavaScript: cbor-x); don't hand-encode.

### attestationObject "None" Format
- **Pitfall:** `attestationFormat: "none"` still requires correct CBOR structure. Some DIY implementations omit fields or mis-encode.
- **Fix:** Verify attestationObject structure: `{ fmt: "none", attStmt: {}, authData: ... }` — attStmt must be empty map `{}`, not null.

### rpIdHash Validation
- **Pitfall:** rpIdHash must be SHA-256(rpId), and if AppID extension is used, rpIdHash is SHA-256(appId) instead. Confusion here causes verification to fail.
- **Fix:** Check presence of AppID extension in request/response before computing expected rpIdHash.

### credProps & residentKey Responses
- **Pitfall:** Registration response **must** include `credentialProperties: { residentKey: false }` (or true if discoverable). Some DIY providers omit this.
- **Reason:** RP needs to know if passkey is discoverable (affects sign-in UX — can RP show username picker?).
- **Fix:** Always include credProps with accurate residentKey boolean.

### signCount Initialization
- **Pitfall:** Some DIY providers initialize signCount to random values or 1; this confuses RPs expecting 0 for synced pairing.
- **Fix:** Always initialize to 0 for vault-backed passkeys.

### Missing Validation of clientDataJSON Hash
- **Pitfall:** Signature is over SHA-256(clientDataJSON) + authenticatorData, not raw clientDataJSON. DIY implementations sometimes hash twice or omit hash.
- **Fix:** Compute clientDataHash = SHA-256(clientDataJSON), then include in signature input as `clientDataHash || authenticatorData`.

**Sources:**
- [idura.eu: WebAuthn ECDSA Signature Verification](https://idura.eu/blog/webauthn-ecdsa-signature/)
- [Paragon Initiative: Security Concerns in WebAuthn](https://paragonie.com/blog/2018/08/security-concerns-surrounding-webauthn-don-t-implement-ecdaa-yet/)
- [Corbado: WebAuthn pubKeyCredParams & COSE Encoding](https://www.corbado.com/blog/webauthn-pubkeycredparams-credentialpublickey/)
- [The Copenhagen Book: WebAuthn reference](https://thecopenhagenbook.com/webauthn)
- [GitHub w3c/webauthn#1721: Signature format underspecification](https://github.com/w3c/webauthn/issues/1721)

---

## Summary Table: Key Recommendations for Vaultify

| Aspect | Recommendation | Reason |
|--------|-----------------|--------|
| Automatic silent registration (Q1) | Implement `requestStyle: .conditional`; allow Face ID prompt | iOS 18+ best practice; seamless UX |
| BE/BS flags (Q2) | Set BE=1 (synced), BS based on current state | Industry standard for vault providers |
| AAGUID (Q3) | Use zero or community registry if public | Optional; improves RP display but not critical for private tool |
| excludedCredentials (Q4) | Reject with `matchedExcludedCredential` error; no overwrite | Spec compliance; prevents accidental duplication |
| userVerificationPreference (Q5) | Always apply UV when biometrics available | iOS platform behavior; RP-compatible |
| PRF & largeBlob (Q6) | Skip in Phase 1; revisit if third-party support arrives | Low priority; Apple doesn't forward to third-party providers |
| Multiple credentials (Q7) | Support picker UI; overwrite old credential on re-registration | Expected for typical vault UX |
| signCount (Q8) | Always 0 for vault passkeys | Standard practice; RPs expect this |
| Credential Exchange (Q9) | Defer to Phase 2+; not core MVP | Convenience feature; moderate implementation effort |
| RP compatibility (Q10) | Use CBOR library; validate clientDataHash; include credProps | Avoid hand-rolling crypto; test with 2–3 RPs |

---

## Unresolved Questions & Notes

1. **iOS 18 automatic upgrade triggering:** Do subsequent password fills (e.g., re-entering credentials for same account) re-trigger the silent registration attempt? Need to verify if system de-duplicates or re-offers per fill. *Likely:* Once accepted/rejected per registration ceremony, system waits for next explicit app navigation.

2. **Vaultify-specific AAGUID:** If Vaultify remains offline/private, zero AAGUID is fine. If future public release, should register community AAGUID — unclear if Vaultify qualifies (offline-only vs. synced vault). Deferred decision.

3. **excludedCredentials on multiple-device scenario:** If user registers same passkey on Device A, then Device B, does Device B's registration see Device A's credential in excludedCredentials? Answer likely "no" unless vault is synced real-time. Vaultify's offline mode won't handle this.

4. **signCount mutation across sync:** If vault is synced later and user signs in from Device B, should Device B return signCount=0 or should old signCount from Device A be preserved? Standard is 0; but untested in Vaultify's architecture. Recommend always return 0 to match expectations.

5. **RP attestation validation:** Vaultify uses "none" attestation (no certificate chain). Some high-assurance RPs reject "none" attestation entirely. Check if any target RPs enforce strict attestation. Likely: low-friction RPs (web, social) accept none; enterprise RPs may require.

6. **Credential Exchange (CXP) wire format:** FIDO CXP spec is not publicly detailed (alliance members only). Need to obtain spec or reverse-engineer from iOS sample code when available. Defer until Phase 2.

---

**Report Date:** 2026-07-02 | **Researcher:** Technical Analyst | **Next Steps:** Validate findings against Vaultify's current extension code (commit 275bc0c); prioritize Q1–Q8 for Phase 1 MVP.
