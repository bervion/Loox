# UI/UX polish: pinned CTAs, Level-2 via Face ID, notice banners

Status: in progress
Branch: `fix/ui-ux-polish-level2-banners` (off `feat/detail-polish-search-refactor`)

Ten owner-reported defects, grouped into seven work packages with disjoint file ownership.

## Decisions

- **Button colour rule (owner, 260727).** `theme.accent` (#009DFF) is the button / button-action /
  icon colour. `linkAccent` (#0065F4) is for hyperlinks and text-link buttons only. The theme
  already encodes this; `BrandCapsuleCTA` was the sole violator, painting the link blue on a
  pinned CTA.
- **Bottom CTAs do not follow the keyboard.** Reverses the comments in `CreateMasterPasswordView`
  and `NameStepView` that recorded the ride-up as an Apple-sign-in behaviour.
- **Level-2 via Face ID is bound to `settings.biometricUnlockEnabled`** (owner choice). The Extra
  Password stays the source of truth and the always-available fallback; the biometric item exists
  only while vault biometrics are on, so turning them off removes it.
- **Biometric failure locks the vault; a cancel never does.** `.authenticationFailed` and
  `.biometryLockout` lock deliberately (slide gate); `.userCancel` / `.systemCancel` / `.appCancel`
  / `.userFallback` are not failures. Navigation state already survives a warm lock, so the user
  returns where they were.
- **`.disabledByUser` gets the error treatment** (owner asked for an error banner). This overrides
  the note in `CapabilityBannerView` reserving red for infrastructure states; recorded here so the
  reversal is visible rather than silent.

## Work packages

| ID | Scope | Owns |
| --- | --- | --- |
| A | Pinned CTAs: keyboard, full width, one accent | `BrandCapsuleCTA`, `ThemedButtonStyles`, Onboarding steps, `MainTabView` |
| C | Change-password + Emergency Kit settings screens | `ChangeMasterPasswordView`, `RegenerateKitView` |
| D | Biometric failure policy | `BiometricAuth`, `BiometricKeyStore`, `VaultSession`, `LockScreen`, QuickView, `ApprovalCeremonyService` |
| E | Notice banner system | `VaultInfoBanner`, `CapabilityBannerView`, banner adopters |
| B | Level-2 via Face ID, protected-field editing | `Level2BiometricKeyStore`, `VaultSession+Level2`, `ProtectFieldSheet`, item editor, `Level2SettingsView` |
| F | Join/restore flow buttons + error card | `JoinVaultFlow` |
| G | Private Email gating | `Personas/*` |

A, C, D, E run first (disjoint). B, F, G follow — they consume D's classifier, E's banner API and
A's CTA.

`Level2BiometricKeyStore.swift` is written up front because both B and D reference it.

## Shared contracts

- `BiometricAuth.Outcome { cancelled, failed, lockout, unavailable }` + `classify(_:) -> Outcome`
- `VaultSession.requireBiometrics(reason:) async throws` — every in-app prompt routes through it
- `VaultSession.unlockLevel2WithBiometrics() async throws`
- `VaultInfoBanner.Variant { info, warning, error }`, plus a `String` overload and `.inList()`
- New strings land in per-package JSON fragments and are merged into `Localizable.xcstrings` once,
  so seven packages never contend for the catalog.

## Acceptance

- No bottom CTA moves with the keyboard; screen primaries span the content width; Welcome's
  "Get started" stays hugging.
- Protecting a field with the Extra Password needs Face ID, not retyping, when vault biometrics
  are on. Editing an item with protected fields offers the same sheet; dismissing it leaves those
  fields locked and undeletable.
- A failed Face ID locks the vault; a cancelled one does not.
- Every notice renders through one component and clears WCAG AA in all 36 theme×accent×variant
  combinations.
- Every new string ships EN + VI.
