# Changelog

## [1.1.1] - 2026-06-14

### Added
- add app-theme selection step before biometrics
- app-icon splash, launch screen, and lock-screen logo

### Fixed
- background-only launch screen to stop square-logo flash
- evaluate biometrics when enabling unlock so Face ID actually triggers

### Changed
- Vietnamese for new onboarding strings; mandate localization
- declare exempt encryption to skip ASC compliance prompt


## [1.1.0] - 2026-06-14

### Added
- add fastlane match + GitHub Actions TestFlight pipeline
- enable AutoFill Credential Provider entitlement on app target
- add passkey support to the AutoFill extension
- publish login identities to ASCredentialIdentityStore
- add AutoFill credential provider extension (passwords)
- extra field protection, attachments, and Vietnamese localization

### Fixed
- auto-select newest Xcode on runner for project format 110
- resolve concurrency, deprecation, and asset-symbol warnings

### Changed
- add README and project CLAUDE.md (dev workflow, Tuist, release)
- generate Xcode project with Tuist
- Xcode project tweaks (app category, extension debug scheme)
- add shared schemes for Vaultify app and AutoFill extension
- extract VaultifyCore shared layer for AutoFill reuse
- add Xcode .gitignore and untrack per-user xcuserdata
- update app icon assets
- Implement native SwiftUI rewrite of Vaultify iOS app
- Initial Commit
