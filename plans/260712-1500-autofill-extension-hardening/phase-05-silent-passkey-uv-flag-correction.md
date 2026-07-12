# Phase 05 — Silent Passkey Registration UV/UP Flag Correction (S2)

## Context Links

- Audit §S2 + open question 2
- Flags: `VaultifyCore/Passkey/WebAuthn.swift:18-24` (`newCredentialFlags = UP|UV|BE|BS`, `legacyAssertionFlags = UP|UV`)
- Silent path: `VaultifyAutoFill/CredentialProviderViewController+SilentPasskeys.swift:43` (`WebAuthn.register` — no auth occurred)
- Interactive registration: `VaultifyAutoFill/PasskeyCeremonyView.swift:225` (behind `UnlockGate` — Face ID/password DID occur)
- Assertion flag reuse: `PasskeyCeremonyView.swift:260` (`secret.flags ?? legacyAssertionFlags`), `:172` (shared slots)
- Backup-status consumer of stored flags: `VaultifyCore/Passkey/PasskeyBackupStatus.swift:16-19` (reads BE/BS only)

## Overview

- **Priority**: P2 (spec fidelity, not a leak)
- **Status**: completed
- The silent iOS 18 conditional-upgrade path emits authenticator data claiming UP=1 UV=1 while no user was present or verified. WebAuthn conditional-create guidance expects UP=0 and UV=0 for conditionally created credentials; RPs are told to expect exactly that ([web.dev passkey form autofill guidance](https://web.dev/articles/passkey-form-autofill), [FIDO dev thread on automatic upgrade UP/UV=false](https://groups.google.com/a/fidoalliance.org/g/fido-dev/c/WAaopDGjgaI), [Corbado conditional-registration writeup](https://www.corbado.com/blog/webauthn-conditional-registration-extension), [WWDC24 passkey upgrades](https://developer.apple.com/videos/play/wwdc2024/10125/)).

## Key Insights

- **The naive fix breaks assertions.** Registration flags are STORED on the secret (`+SilentPasskeys.swift:51`) and later replayed as ASSERTION flags (`PasskeyCeremonyView.swift:260,172`). Storing UV=0 flags would make every future assertion of a silently-created passkey claim UV=0 — even though assertions always run behind `UnlockGate` (Face ID or master password = genuine UV). RPs that require UV would then reject sign-ins. Fix must decouple registration-time flags from assertion-time flags.
- Stored `flags` doubles as the backup-status marker (BE/BS, `PasskeyModels.swift:41-43`); BE/BS stay set on the silent path (the credential IS synced/backup-eligible via the envelope design) — only UP/UV change.
- `request.userVerificationPreference` (`ASPasskeyCredentialRequest`) is available on the silent request; if the RP demands `required` UV, the correct silent answer is to bail to `userInteractionRequired` (existing `skipSilentRegistration` mechanism `+SilentPasskeys.swift:86`) rather than lie.

## Requirements

- Silent registration authenticatorData: UP=0, UV=0, BE=1, BS=1 (+AT for attested data).
- Interactive registration: unchanged (UP=1 UV=1 BE=1 BS=1).
- Assertions (owned + shared, all interactive): UP=1, UV=1, BE/BS copied from the stored credential — regardless of how the credential was registered.
- Silent path with `userVerificationPreference == .required`: skip (cancel `.userInteractionRequired`) so the OS falls back to an interactive flow.

## Architecture

```
WebAuthn.register(relyingParty:flags:)          // flags param, default = newCredentialFlags
  interactive callers: default (UP|UV|BE|BS)
  silent caller:       conditionalCredentialFlags = BE|BS

WebAuthn.assertionFlags(stored: UInt8?) -> UInt8
  = UP | UV | ((stored ?? 0) & (BE|BS))          // single helper; replaces both
                                                  // `secret.flags ?? legacyAssertionFlags` sites
```

Stored `secret.flags` keeps recording the REGISTRATION flags (truthful history + BE/BS source); assertion flags are computed per-ceremony because every assertion in this provider is user-verified by construction (all assertion routes pass `UnlockGate`; audit §S4 verified no silent assertion path exists).

## Related Code Files

Modify:
- `VaultifyCore/Passkey/WebAuthn.swift` — `register` gains `flags:` param (`:34-45`); add `conditionalCredentialFlags`; add `assertionFlags(stored:)` helper; keep `legacyAssertionFlags` for compatibility or fold into the helper
- `VaultifyAutoFill/CredentialProviderViewController+SilentPasskeys.swift` — pass conditional flags at `:43`; add `userVerificationPreference == .required` guard before registering
- `VaultifyAutoFill/PasskeyCeremonyView.swift` — `:260` and `:172` use `WebAuthn.assertionFlags(stored:)`

Read for context: `VaultifyCore/Passkey/PasskeyBackupStatus.swift`, `PasskeyModels.swift`.

## Implementation Steps

1. `WebAuthn.register(relyingParty:flags: UInt8 = newCredentialFlags)`; authData uses `flags | flagAttestedData`; `Registration.flags` records the passed flags. Code comment states the WHY: conditional creations happen without a user-verification ceremony, so the authenticator must not assert UP/UV (no plan/finding refs).
2. Add `assertionFlags(stored:)` and switch both assertion call sites. Verify shared-slot path (`:172`): shared assertions also run behind `UnlockGate` + live grant check → UP|UV correct.
3. Silent path: guard on `request.userVerificationPreference` — `.required` ⇒ `skipSilentRegistration("uv-required")`. Confirm the property's availability on iOS 18 SDK during implementation (stable-Xcode ceiling; it is part of the base `ASPasskeyCredentialRequest` API).
4. Unit tests (phase 6 lists them; land with this phase): flag byte layout for conditional vs interactive registration; `assertionFlags` matrix (nil / legacy UP|UV / silent BE|BS / full UP|UV|BE|BS stored).
5. Compile check both targets.

## Todo

- [x] `register(flags:)` + `conditionalCredentialFlags` (`legacyAssertionFlags` kept — still used by `ApprovalCeremonyService` + tests)
- [x] `assertionFlags(stored:)` + both call sites switched (owned `sign` + shared hand-over slot)
- [x] `.required` UV preference guard on silent path (`skipSilentRegistration("uv-required")`; API compiled against stable SDK ceiling)
- [x] Flag unit tests (added to `WebAuthnTests.swift`: 0x58 conditional, 0x5D interactive, assertionFlags matrix, 0x1D assertion of conditional credential)
- [x] Compile check both targets (make check pass; tests not RUN — sim-less session, `make test` deferred to phase 6)

## Success Criteria

- Byte-level test: silent registration authData flags == `0x58` (AT|BS|BE) and interactive == `0x5D` (AT|BS|BE|UV|UP).
- Assertion authData flags == `0x1D` (BS|BE|UV|UP) for a silently-registered credential and `0x05` (UV|UP) for a legacy credential with nil flags.
- Manual QA: automatic upgrade on a test RP (e.g. webauthn.io flow) still completes; subsequent sign-in with the upgraded passkey succeeds.

## Risk Assessment

- Some non-compliant RPs may reject UP=0 registrations → upgrade silently fails server-side; user keeps password sign-in, and the `automaticPasskeyUpgradesEnabled` toggle (`+SilentPasskeys.swift:17`) remains the kill switch. Orphaned-credential handling is unchanged from today (existing rollback at `:79`).
- Do NOT migrate stored flags of previously silent-registered credentials — with `assertionFlags(stored:)` they assert correctly without data changes.

## Security Considerations

- This INCREASES honesty toward RPs (no false UV claims). No secret handling changes.

## Next Steps

- Phase 6 QA includes one end-to-end conditional-upgrade run on-device (iOS 18+).
