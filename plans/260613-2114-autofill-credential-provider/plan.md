# AutoFill Credential Provider (Password + Passkey)

Make Vaultify appear in **Settings → Passwords & AutoFill** and provide credentials.
Cause of absence: app has a single target, no Credential Provider extension.

## Decisions (locked by user)
- Scope: **passwords + passkeys** (passwords first, passkeys after passwords work).
- Mechanism: real decryption in the extension (zero-knowledge preserved).

## Architecture
Extension must reuse the vault crypto + model to decrypt. Project uses Xcode 16
synchronized folders, so share source via a `VaultifyCore/` folder compiled into
**both** the app and the extension targets (same module per target → no `public`
refactor, no framework).

- **VaultifyCore/** (both targets): Crypto/, CArgon2/ (C + bridging), Keychain/
  (KeychainStore, VaultKeyBundle, BiometricKeyStore, BiometricAuth), SharedConfig,
  SecretGuard, Models/ (DynamicField, FieldKind, ItemCategory, VaultItem),
  Store/ (ItemRecord, VaultStore), Localization.swift (appResourceLocale +
  appLocale + inAppLocalized + appString, moved out of SettingsStore), and a new
  **VaultReader** (open store + decrypt with a key — read-only, no VaultSession).
- **App keeps**: VaultSession(+Level2) (MainActor + SettingsStore), VaultRepository
  (CRUD via session), SettingsStore (class), all UI/Services.
- **VaultifyAutoFill/** (extension): CredentialProviderViewController, Info.plist,
  entitlements, bridging header.

## Shared unlock in the extension
Load wrapped key bundle (App Group) → user enters master password → Argon2id →
unwrap VaultKey → VaultReader decrypts items → return ASPasswordCredential.
(Biometric/keychain-group unlock = later enhancement.)

## Entitlements / signing
- Extension entitlements: App Group `group.com.bervion.vaultify` +
  `com.apple.developer.authentication-services.autofill-credential-provider`.
- Bundle id `com.bervion.vaultify.autofill`, team WDNL2F75V7.
- Info.plist NSExtension point `com.apple.authentication-services-credential-provider-ui`,
  capabilities ProvidesPasswords (+ ProvidesPasskeys in Phase B).
- On a real device the app + extension + App Group need provisioning (signing in Xcode).

## Phases
| # | Phase | Status |
|---|-------|--------|
| A1 | Extract `VaultifyCore/` (move shared files, move localization globals, add to app target, fix HEADER_SEARCH_PATHS/bridging). App builds unchanged. | pending |
| A2 | Add `VaultifyAutoFill` extension target + entitlements + Info.plist + `VaultReader`; password list/provide with master-password unlock. Builds + appears in Settings. | pending |
| A3 | App populates `ASCredentialIdentityStore` (domain → login) on unlock/save/delete. | pending |
| B  | Passkeys: passkey model in Core, registration + assertion (WebAuthn/P-256), passkey identities. | pending |

## Risks
- pbxproj surgery (new target, synchronized groups, embed phase) — verify each step with `xcodebuild`.
- SwiftData + C Argon2 must compile in extension context (both supported).
- Device signing for two targets + App Group (user may need to confirm in Xcode).

## Build gate
After every phase: `xcodebuild -scheme Vaultify -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd` must succeed; commit working state.
