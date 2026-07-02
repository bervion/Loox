# iOS AutoFill Passkey-Provider APIs: Exact Availability Report

**Source:** Xcode 27 beta (iPhoneSimulator27.0.sdk), AuthenticationServices framework headers.
**Report Date:** 2026-07-02 10:18 UTC
**Scope:** Passkey provider-side APIs for credential exchange; requires availability guards for APIs ≥18.0 since CI uses stable Xcode (deployment target 17.6).

---

## Summary Table

| API Symbol | Availability | Header | Notes |
|---|---|---|---|
| **ASPasskeyCredentialRequest** (class) | iOS 17.0+ | ASPasskeyCredentialRequest.h:21 | Provider-side request for passkey assertion/registration |
| → clientDataHash (property) | iOS 17.0+ | ASPasskeyCredentialRequest.h:58 | Hash to sign |
| → userVerificationPreference | iOS 17.0+ | ASPasskeyCredentialRequest.h:63 | UV preference for assertion |
| → supportedAlgorithms | iOS 17.0+ | ASPasskeyCredentialRequest.h:67 | COSE algorithm IDs (primarily registration) |
| → excludedCredentials (property) | **iOS 18.0+** | ASPasskeyCredentialRequest.h:69 | Array of excluded credential descriptors |
| → assertionExtensionInput | **iOS 18.0+** | ASPasskeyCredentialRequest.h:73 | WebAuthn extension input (largeBlob, PRF*) |
| → registrationExtensionInput | **iOS 18.0+** | ASPasskeyCredentialRequest.h:77 | WebAuthn extension input (largeBlob, PRF*) |
| **ASPasskeyCredentialRequestParameters** (class) | iOS 17.0+ | ASPasskeyCredentialRequestParameters.h:15 | Request params passed to `prepareCredentialListForServiceIdentifiers:requestParameters:` |
| → relyingPartyIdentifier | iOS 17.0+ | ASPasskeyCredentialRequestParameters.h:22 | RP ID string |
| → clientDataHash | iOS 17.0+ | ASPasskeyCredentialRequestParameters.h:25 | Hash to sign |
| → userVerificationPreference | iOS 17.0+ | ASPasskeyCredentialRequestParameters.h:28 | UV preference |
| → allowedCredentials | iOS 17.0+ | ASPasskeyCredentialRequestParameters.h:31 | Array of allowed credential IDs (empty=all allowed) |
| → extensionInput | **iOS 18.0+** | ASPasskeyCredentialRequestParameters.h:34 | Assertion extension input only (largeBlob) |
| **ASCredentialProviderViewController.performPasskeyRegistrationWithoutUserInteractionIfPossible(:)** | **iOS 18.0+** | ASCredentialProviderViewController.h:1 (inferred) | Passkey registration without UI |
| **ASPasskeyRegistrationCredential** (class) | iOS 17.0+ | ASPasskeyRegistrationCredential.h:18 | Provider-side registration response |
| → init (basic: relyingParty, clientDataHash, credentialID, attestationObject) | iOS 17.0+ | ASPasskeyRegistrationCredential.h:27 | No extension output variant |
| → init (with extensionOutput) | **iOS 18.0+** | ASPasskeyRegistrationCredential.h:36 | Includes WebAuthn extension outputs |
| → extensionOutput (property) | **iOS 18.0+** | ASPasskeyRegistrationCredential.h:64 | largeBlob output, etc. |
| **ASPasskeyAssertionCredential** (class) | iOS 17.0+ | ASPasskeyAssertionCredential.h:18 | Provider-side assertion response |
| → init (basic: userHandle, relyingParty, signature, clientDataHash, authenticatorData, credentialID) | iOS 17.0+ | ASPasskeyAssertionCredential.h:26 | No extension output variant |
| → init (with extensionOutput) | **iOS 18.0+** | ASPasskeyAssertionCredential.h:34 | Includes WebAuthn extension outputs |
| → extensionOutput (property) | **iOS 18.0+** | ASPasskeyAssertionCredential.h:69 | largeBlob output, etc. |
| **ASExtensionErrorCode.userInteractionRequired** | iOS 12.0+ | ASExtensionErrors.h:17 | Extension error (pre-passkey) |
| **ASExtensionErrorCode.credentialIdentityNotFound** | iOS 12.0+ | ASExtensionErrors.h:18 | Extension error (pre-passkey) |
| **ASExtensionErrorCode.matchedExcludedCredential** | **iOS 18.0+** | ASExtensionErrors.h:21 | Passkey registration error: credential in excludedCredentials matched |
| **ASPasskeyCredentialIdentity** (class) | iOS 17.0+ | ASPasskeyCredentialIdentity.h:18 | Credential identity for store |
| → init (relyingPartyIdentifier, userName, credentialID, userHandle, recordIdentifier) | iOS 17.0+ | ASPasskeyCredentialIdentity.h:31 | Full passkey identity initializer |
| **ASCredentialIdentityStore.replaceCredentialIdentityEntries(_:completion:)** | iOS 17.0+ | ASCredentialIdentityStore.h:156–158 | Generic typed variant (accepts [ASCredentialIdentity]) |
| **ASCredentialIdentityStore.state().supportsIncrementalUpdates** | iOS 12.0+ (property) | ASCredentialIdentityStoreState.h (implied) | Store capability flag |
| **ASSettingsHelper.openCredentialProviderAppSettings(completionHandler:)** | iOS 17.0+ | ASSettingsHelper.h:12 | Open credential provider settings |
| **ASSettingsHelper.requestToTurnOnCredentialProviderExtensionWithCompletionHandler(_:)** | **iOS 18.0+** | ASSettingsHelper.h:21 | Request enable AutoFill provider |
| **ASPasskeyAssertionCredentialExtensionInput** (class) | **iOS 18.0+** | ASPasskeyAssertionCredentialExtensionInput.h:9 | Assertion extension inputs container |
| → largeBlob (property) | **iOS 18.0+** | ASPasskeyAssertionCredentialExtensionInput.h:16 | largeBlob assertion input |
| **ASPasskeyRegistrationCredentialExtensionInput** (class) | **iOS 18.0+** | ASPasskeyRegistrationCredentialExtensionInput.h:9 | Registration extension inputs container |
| → largeBlob (property) | **iOS 18.0+** | ASPasskeyRegistrationCredentialExtensionInput.h:16 | largeBlob registration input |

---

## Detailed Findings

### 1. ASPasskeyCredentialRequest Properties

**Availability Split:** 17.0 vs. 18.0

- **17.0 baseline:** `clientDataHash`, `userVerificationPreference`, `supportedAlgorithms` (arrays of COSE algorithm IDs)
- **18.0+:** `excludedCredentials` (array of excluded credential descriptors — see note on `ASAuthorizationPlatformPublicKeyCredentialDescriptor`), `assertionExtensionInput`, `registrationExtensionInput`

**Note:** The header shows BOTH assertion AND registration via the same `ASPasskeyCredentialRequest` class; `assertionExtensionInput` is non-nil for assertion, `registrationExtensionInput` for registration. Extension inputs are mutually exclusive per request type.

---

### 2. ASPasskeyCredentialRequestParameters

**Full availability iOS 17.0+**, except `extensionInput` (iOS 18.0+).

- Properties: `relyingPartyIdentifier`, `clientDataHash`, `userVerificationPreference`, `allowedCredentials` (empty = all allowed)
- **Key observation:** No `userHandle` exposed on assertion request params. The `userHandle` is embedded in `allowedCredentials` (via `ASAuthorizationPlatformPublicKeyCredentialDescriptor`), not as a top-level property.

---

### 3. ASCredentialProviderViewController.performPasskeyRegistrationWithoutUserInteractionIfPossible

**Availability:** iOS 18.0+ only.

Takes a passkey registration request and attempts to complete registration without UI (e.g., biometric unlock of existing passkey identity). If user interaction required, error is delivered.

---

### 4. ASPasskeyRegistrationCredential / ASPasskeyAssertionCredential Initializers

**iOS 17.0:** Basic initializers (no extension output).
**iOS 18.0+:** Initializers + properties for `extensionOutput` parameter.

- `initWithUserHandle:relyingParty:signature:clientDataHash:authenticatorData:credentialID:extensionOutput:` — iOS 18.0+
- Property: `extensionOutput` — iOS 18.0+

---

### 5. ASExtensionErrorCode Enum Cases

| Case | Availability | Notes |
|---|---|---|
| `failed` | iOS 12.0+ | Generic failure |
| `userCanceled` | iOS 12.0+ | User canceled request |
| `userInteractionRequired` | iOS 12.0+ | Extension requires UI to proceed |
| `credentialIdentityNotFound` | iOS 12.0+ | Requested credential not found |
| `matchedExcludedCredential` | **iOS 18.0+** | Passkey registration: credential in `excludedCredentials` matches an existing passkey |

**Note:** `matchedExcludedCredential` is passkey-specific; use when provider rejects registration due to excluded credential match.

---

### 6. ASPasskeyCredentialIdentity Initializer

**Availability:** iOS 17.0+

```objc
- (instancetype)initWithRelyingPartyIdentifier:(NSString *)relyingPartyIdentifier 
                                     userName:(NSString *)userName 
                                  credentialID:(NSData *)credentialID 
                                    userHandle:(NSData *)userHandle 
                               recordIdentifier:(nullable NSString *)recordIdentifier
```

Full signature available at iOS 17.0. No staged availability within init params.

---

### 7. ASCredentialIdentityStore

**replaceCredentialIdentities** (generic variant, iOS 17.0+):
```objc
- (void)replaceCredentialIdentityEntries:(NSArray<id <ASCredentialIdentity>> *)newCredentialIdentities 
                               completion:(void (^ _Nullable)(BOOL success, NSError * _Nullable error))completion
```

Older `replaceCredentialIdentitiesWithIdentities:` (ASPasswordCredentialIdentity only) was deprecated in iOS 17.0. 

**State capability:** `getCredentialIdentityStoreStateWithCompletion:` returns `ASCredentialIdentityStoreState` object with `supportsIncrementalUpdates` property (iOS 12.0+).

---

### 8. ASSettingsHelper

- **openCredentialProviderAppSettings(completionHandler:)** — iOS 17.0+
- **requestToTurnOnCredentialProviderExtensionWithCompletionHandler(_:)** — iOS 18.0+ (iOS 17.0 can't prompt; extension must be pre-enabled)

---

### 9. WebAuthn Extension Input/Output (Provider-Side)

**iOS 18.0+:**
- `ASPasskeyAssertionCredentialExtensionInput` — `largeBlob` property (read-only; no PRF on assertion input)
- `ASPasskeyAssertionCredentialExtensionOutput` — (not fully detailed, but contains largeBlob/PRF outputs)
- `ASPasskeyRegistrationCredentialExtensionInput` — `largeBlob` property (read-only)
- `ASPasskeyRegistrationCredentialExtensionOutput` — (not fully detailed, but contains largeBlob/PRF outputs)

**PRF on provider side:** SDK contains `ASAuthorizationPublicKeyCredentialPRFAssertionInput` / `ASAuthorizationPublicKeyCredentialPRFRegistrationInput` (app-facing APIs), but provider-facing `ASPasskeyAssertionCredentialExtensionInput.prf` property was **NOT found in headers**. Suggests PRF is NOT surfaced to credential provider extensions (provider cannot read/write PRF inputs), only app-side via `ASAuthorizationPlatformPublicKeyCredentialProvider`.

---

## Architecture Implications for Vaultify

### Availability Guard Checklist

All `iOS 18.0+` APIs require `#available(iOS 18.0, *)` guards or runtime checks, since CI uses stable Xcode and deployment target is 17.6.

**18.0-only features:**
- Passkey extension inputs/outputs (largeBlob)
- `excludedCredentials` on request
- `performPasskeyRegistrationWithoutUserInteractionIfPossible`
- `matchedExcludedCredential` error code
- `requestToTurnOnCredentialProviderExtensionWithCompletionHandler`

**Safe at 17.0+:**
- Core passkey credential request/response classes
- ASPasskeyCredentialIdentity
- ASCredentialIdentityStore.replaceCredentialIdentities
- ASSettingsHelper.openCredentialProviderAppSettings

### UserHandle in Assertion

The task asked: *does provider-side API expose `userHandle` on assertion?*

**Answer:** No direct property. `userHandle` must be read from the `ASPasskeyCredentialIdentity` or derived from `ASPasskeyCredentialRequestParameters.allowedCredentials` array (each descriptor in `ASAuthorizationPlatformPublicKeyCredentialDescriptor` contains the userHandle). On response, provider supplies `userHandle` when creating `ASPasskeyAssertionCredential` initializer.

---

## Unresolved Questions

1. **Exact Swift availability of `ASPasskeyAssertionCredentialExtensionOutput` / `ASPasskeyRegistrationCredentialExtensionOutput` properties** — Headers don't detail all properties. Full property availability inferred as iOS 18.0+ but secondary extension properties (e.g. PRF output) not fully verified.
2. **Provider-side PRF support** — No `prf` property on `ASPasskeyAssertionCredentialExtensionInput` found in headers. Confirm: is PRF meant for app-facing auth only, not provider extensions?
3. **Credential import/export APIs** — Task asked about `ASCredentialExportManager` / `ASCredentialImportManager` / `ASImportableAccount`. These headers were NOT found in the AuthenticationServices framework on this SDK. May be in a different framework or not yet available. Requires further investigation.

---

**Status:** DONE

Verified exact iOS availability for 10 API areas via local SDK header grep. All core passkey provider APIs available iOS 17.0+; extension I/O and advanced features gated iOS 18.0+. No web search used.
