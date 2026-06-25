# Code Review — iOS 26.2 AutoFill Save + Strong-Password Generation

Scope: `Project.swift`, `VaultifyAutoFill/CredentialProviderViewController.swift`,
`VaultifyAutoFill/SavePasswordView.swift` (new), `VaultifyAutoFill/AutoFillView.swift`,
`Vaultify/Security/VaultSession.swift`, `Vaultify/Localizable.xcstrings`.
Focus: availability guarding, save correctness, AutoFill completion contract, key/security, localization.

Verdict: **APPROVE_WITH_NITS**. No Critical/High. Feature is correct, the completion contract is
clean (exactly-once on every path), no secret logging. Nits are advisory.

## 1. Availability guarding — CORRECT (no holes)
- All four 26.2 overrides wrapped in `#if compiler(>=6.2)` + per-method `@available(iOS 26.2, *)`
  (controller:73-100). grep confirms every 26.2-only symbol (`ASSavePasswordRequest`,
  `ASGeneratePasswordsRequest`, `ASGeneratedPassword`, `completeSavePasswordRequest`,
  `completeGeneratePasswordRequest`) appears ONLY inside those guarded methods.
- `SavePasswordView.swift` uses no 26.2 API (only long-available `ASPasswordCredentialIdentity`/
  `ASCredentialServiceIdentifier`/`ASCredentialIdentityStore`), so it needs no annotation and is safely
  referenced from the guarded `prepareInterface`. Deployment target 17.6 unaffected — methods simply never
  invoked below 26.2. Build passes on 26.2 SDK. No availability hole.

## 2. Save correctness — CORRECT; empty-input safe
- `prepareInterface(save)` extracts `credential.user` / `credential.password` /
  `serviceIdentifier.identifier` (controller:77-83). Sealing via `VaultWriter.createLogin`.
- Empty-input safety verified in `VaultWriter.createLogin` (VaultWriter.swift:22-44): empty password →
  throws `Failure.emptyPassword` (surfaced as error, no crash); empty site/username → title falls back
  ("Login"/username) and Website field is omitted. No force-unwrap. No crash with empty host/username.
- `indexCredential` (SavePasswordView:122-131) skips when host or username empty, and only indexes a
  parseable host — safe, best-effort, `completion: nil` is fine.
- Known limitation (as flagged, NOT a bug): always creates a NEW item; no "update existing on same
  host+user" path → duplicate logins on a password *change*. Acceptable for v1; worth a follow-up.

## 3. Completion / cancel contract — CORRECT (exactly-once, no hang)
- Save sheet: `onCancel`→`cancel(.userCanceled)`; `onSaved`→`completeSavePasswordRequest` — mutually
  exclusive, each fires once.
- `save()` (SavePasswordView:108-119): success → `onSaved()` once; throw → set `errorMessage`,
  `saving=false`, STAY on screen (no completion). Request is not hung — user retries or taps Cancel
  (→ `onCancel` completes). Matches the intended design.
- Double-completion guard: Save button `.disabled(saving)`; `save()` sets `saving=true` synchronously
  before the synchronous `createLogin`; on success `saving` is never reset → button cannot re-fire. ✓
- `performWithoutUserInteractionIfPossible(save)` → `cancel(.userInteractionRequired)` once — correctly
  forces the interactive unlock sheet. ✓
- Generate → `completeGeneratePasswordRequest(results:)` once, headless. With
  `SupportsGeneratePasswordCredentialsWithUI:false` the OS never calls a with-UI variant, so the absent
  override is intentional and complete. ✓
- Biometric-fail in SavePasswordView → shows `unlockForm`, no completion (correct; flow continues). ✓

## 4. Key handling / security — OK
- `vaultKey` held in `@State [UInt8]` (SavePasswordView:15), same pattern as `AutoFillView`
  (AutoFillView:26) — consistent, acceptable. No deeper zeroization than the rest of the extension; not a
  regression.
- Generate path returns a password WITHOUT unlocking the vault — correct: generation needs no secret,
  uses CSPRNG (`CryptoRandom`) via `PasswordGenerator.generate(PasswordOptions())` = length 20, all
  classes, ambiguity-avoided → genuinely strong.
- No secret logging confirmed: `PasswordGenerator.generate` has no logging; the new `os.Logger` lines
  (VaultSession, AutoFillView) log only booleans / error descriptions / lifecycle markers — never
  username, password, or vault bytes. `prepareInterface(save)` logs only `"prepareInterface(save)"`.

## 5. Localization — COMPLETE for this feature
- All SavePasswordView strings present in catalog WITH `vi` (verified via JSON parse, all `state:
  translated`): "Save login", "Save", "Website", "Username", "Couldn’t save the login.", "Unlock your
  vault", "Incorrect master password.", "Couldn’t unlock the vault.", "Master password", "Unlock",
  "Cancel".
- Runtime error strings use `appString(...)`; SwiftUI `Text` literals localize via the host's
  `.environment(\.locale, appResourceLocale)` (controller:175) — consistent with AutoFillView. ✓

## Nits (advisory, non-blocking)
- **L-1 (Low, pre-existing, not this feature):** catalog now contains two auto-extracted strings WITHOUT
  vi — "Create a passkey" / "Sign in with a passkey" — from the passkey prompts at
  CredentialProviderViewController.swift:122 (long-existing literals, just freshly extracted by the build).
  Per the project's "missing VI = bug" rule, add vi translations. Out of scope for save/generate, but
  cheap to fix while the catalog is open.
- **L-2 (Low, DRY):** `SavePasswordView` duplicates `AutoFillView`'s unlock orchestration
  (`attemptBiometricUnlock` / `unlockWithMaster` / biometric+master fallback, state vars). Acceptable for
  now (two small call sites, slight shape differences — Save confirms, Fill picks). If a 3rd unlock host
  appears, extract a shared `VaultUnlockGate` view/modifier. Not worth churning now.
- **L-3 (Low):** on save success `saving` stays `true` and the view relies on the host tearing down after
  `completeSavePasswordRequest`. Fine in practice (sheet dismisses); just noting the success path never
  resets state.

## Unresolved questions
- None. "Always-creates-new" duplicate behavior is acknowledged as a deliberate v1 limitation; confirm a
  follow-up task is tracked for update-existing matching if product wants dedupe.

Status: DONE
