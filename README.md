<div align="center">

<img src="Vaultify/Assets.xcassets/BrandSymbol.imageset/loox-symbol.svg" width="112" alt="Loox app icon">

# Loox Password Manager

**A private, offline password and passkey manager for iPhone, iPad and Mac.**

No account. No vault server. Your vault is encrypted on your device and stays there unless you choose to sync or share it.

<a href="https://apps.apple.com/us/app/loox-password-manager/id6779973474"><img src="https://tools.applemarketingtools.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store" height="54"></a>

[![CI](https://github.com/bervion/Loox/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/bervion/Loox/actions/workflows/ci.yml)
[![App Store](https://img.shields.io/itunes/v/6779973474?label=App%20Store&logo=apple&logoColor=white&color=0D96F6)](https://apps.apple.com/us/app/loox-password-manager/id6779973474)
[![Latest release](https://img.shields.io/github/v/tag/bervion/Loox?sort=semver&label=release)](https://github.com/bervion/Loox/tags)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
<br>
[![Platforms](https://img.shields.io/badge/platforms-iOS%2017.3%2B%20%7C%20iPadOS%2017.3%2B%20%7C%20macOS%2015%2B-lightgrey?logo=apple)](#requirements)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-F05138?logo=swift&logoColor=white)](#tech-stack)
[![Xcode](https://img.shields.io/badge/Xcode-26.5%2B-147EFB?logo=xcode&logoColor=white)](#requirements)
[![Tuist](https://img.shields.io/badge/project-Tuist-6236FF)](https://tuist.dev)
[![Languages](https://img.shields.io/badge/languages-EN%20%7C%20VI%20%7C%20JA-informational)](#features)
[![Website](https://img.shields.io/website?url=https%3A%2F%2Flooxpassword.com&label=looxpassword.com)](https://looxpassword.com)

[Website](https://looxpassword.com) &nbsp;•&nbsp; [App Store](https://apps.apple.com/us/app/loox-password-manager/id6779973474) &nbsp;•&nbsp; [Wiki](https://github.com/bervion/Loox/wiki) &nbsp;•&nbsp; [Build from source](#building-from-source) &nbsp;•&nbsp; [Security](SECURITY.md)

<br>

<img src="App%20Store%20Screenshots/shots/iphone-home.png" width="200" alt="Home screen with Quick Actions and authenticator codes">&nbsp;
<img src="App%20Store%20Screenshots/shots/iphone-detail.png" width="200" alt="Login detail with password strength and one-time code">&nbsp;
<img src="App%20Store%20Screenshots/shots/iphone-codes.png" width="200" alt="2FA codes list">&nbsp;
<img src="App%20Store%20Screenshots/shots/iphone-watchtower.png" width="200" alt="Watchtower security score">

</div>

## Why Loox

- **Offline by design.** The vault is a local encrypted store. There is no Loox account and no server that holds your vault.
- **Strong, boring cryptography.** Argon2id derives the key from your master password; every item is sealed with AES-256-GCM.
- **Built into the system.** AutoFill for passwords, passkeys and one-time codes, a Safari extension, and Face ID / Touch ID unlock.
- **Native everywhere.** One SwiftUI codebase for iPhone, iPad and Mac, localized in English, Vietnamese and Japanese.

## Features

**Vault**
- Logins, passkeys, 2FA (TOTP) codes, cards, identities, notes, recovery codes, security questions and developer secrets (SSH keys, API secrets, App Store Connect and APNs keys, signing identities, certificates).
- Spaces (with color and icon), tags and favorites, plus Profiles to keep work and personal identities apart.
- Password generator with live strength feedback.

**AutoFill and browser**
- Credential Provider extension for passwords and passkeys, one-time codes on iOS 18 and later, and saving new logins from AutoFill.
- Safari web extension on iPhone and iPad: fills identities and cards, suggests generated passwords on sign-up and offers to save.
- Native Mac app with its own AutoFill provider.

**Security health**
- Watchtower score with weak, reused and old password findings, a fix queue and rotation reminders.
- Emergency Kit PDF with a recovery key.
- Encrypted `.vaultify` backups (including passkeys) and CSV import from 1Password, Bitwarden and Chrome.

**Sharing and privacy tools** (optional, use the network)
- Share with another Loox user over iCloud in Approval Mode: share access, not the secret, and approve each use.
- Quick Link: an end-to-end encrypted, expiring link that opens in any browser.
- Quick View: open a single item in a computer's browser by scanning a QR code.
- Private Email: masked addresses that forward to your real inbox.

**Everywhere**
- iPhone, iPad and Mac. English, Vietnamese and Japanese with an in-app language switch.
- Day and Night appearance with seven accent colors, Dynamic Type, Reduce Motion and VoiceOver support.

The vault, AutoFill, passkeys and 2FA codes work without an account.

## Security model

| Layer | What it does |
|---|---|
| **Vault Key** | A random 256-bit key generated once per vault. Every item payload is sealed with AES-256-GCM (CryptoKit). |
| **Master password** | Argon2id (vendored [reference implementation](VaultifyCore/CArgon2), known-answer tested) derives a key-encryption key that wraps the Vault Key. Vault profile: 32 MiB, t=4, p=4, sized for the AutoFill extension's memory budget. Backups: 64 MiB, t=3, p=4. Decoded parameters are bounded so an imported file cannot exhaust memory. |
| **Other unlock paths** | The Vault Key is also wrapped by a recovery key (Emergency Kit) and by a biometric Keychain item bound to the current Face ID / Touch ID enrollment. |
| **Storage** | The encrypted vault lives in the App Group container so the AutoFill and Safari extensions can read it; decryption happens on device after unlock. |
| **Extensions** | Developer secrets never surface in AutoFill or share links (fail-closed capability model). The Safari extension exposes exactly one native command that returns field values. |

### What leaves your device

No request carries your master password or a decrypted vault.

| Data | When | Where |
|---|---|---|
| Encrypted vault items, the device name, and the Vault Key wrapped by your recovery key (useless without the Emergency Kit) | Only if you turn on iCloud sync (off by default) | Your iCloud private database |
| Fields you share | Only when you share | iCloud (Approval Mode) or the Quick Link service, encrypted on device before upload |
| Private Email addresses and forwarding, plus a sealed relay identity | Only if you use Private Email (even with iCloud sync off) | Loox relay service; the sealed identity in your iCloud private database |
| The first 5 characters of each password's SHA-1 hash (k-anonymity) | While "Check for known breaches" is on (on by default) and a Watchtower audit runs, including the automatic one when you open Watchtower | Have I Been Pwned |
| Website domains | While "Show website icons" is on (on by default) | Google favicon service |
| Signed configuration (feature switches, Private Email domains, Quick View signer keys); the request carries no vault data | On unlock and when the app returns to the foreground | Loox config service, with an iCloud public database mirror as fallback |
| Usage analytics: item types, count buckets, setting states (never names, values, websites or search terms) | Only if you turn on "Share anonymous usage statistics" (off by default) | Google Analytics for Firebase, app only, no IDFA |
| Crash reports | Unless you turn off "Send crash diagnostics" | Firebase Crashlytics, app only |
| Subscription transaction | Only if you buy a Loox membership | Loox entitlement service |

The AutoFill and Safari extensions link no analytics or crash reporting SDK. Found a vulnerability? See [SECURITY.md](SECURITY.md).

## Tech stack

| | |
|---|---|
| UI | SwiftUI, native on iPhone, iPad and Mac |
| Storage | SwiftData over an encrypted payload model, shared App Group container |
| Crypto | CryptoKit (AES-GCM, HPKE, P-256), Argon2id reference C |
| System integration | AuthenticationServices Credential Provider, Safari Web Extension (Manifest V3), CloudKit |
| Project | [Tuist](https://tuist.dev) generates the Xcode project from [`Project.swift`](Project.swift) |
| Dependencies | Firebase (Analytics core and Crashlytics, app target only), swift-snapshot-testing (tests only) |
| CI/CD | GitHub Actions, fastlane and match, TestFlight |

## Building from source

### Requirements

- macOS with **Xcode 26.5 or later** (the CI minimum lives in [`scripts/ci/toolchain-pin.sh`](scripts/ci/toolchain-pin.sh))
- [mise](https://mise.jdx.dev), which installs the Tuist version pinned in [`.mise.toml`](.mise.toml)
- For `make test`: an iOS 26.5 or newer Simulator runtime with the iPhone 17 Pro device type (the suite creates a throwaway simulator from it)
- Deployment targets: iOS / iPadOS 17.3, macOS 15

### Generate and run

```bash
git clone https://github.com/bervion/Loox.git
cd Loox
mise install
mise exec -- tuist generate
```

Tuist opens `Vaultify.xcworkspace`. Pick the **Vaultify** scheme and run it on an iOS Simulator. If Xcode reports that the team is unavailable, set `DEVELOPMENT_TEAM` in `Project.swift` to your own team and generate again.

The Xcode project and workspace are generated and gitignored. After adding, removing or renaming a source file, or editing `Project.swift`, run `mise exec -- tuist generate` again.

To run on a device, set `DEVELOPMENT_TEAM` and the bundle identifiers in `Project.swift` to your own, then replace the App Group (`group.com.bervion.vaultify`) and iCloud container (`iCloud.com.bervion.vaultify`) everywhere they appear: the `*.entitlements` files, the privacy manifests and the shared, sync and sharing configuration. `git grep -l -e group.com.bervion.vaultify -e iCloud.com.bervion.vaultify` lists them. Those capabilities must exist for your bundle IDs in your developer account.

### Checks

```bash
mise exec -- make check                             # compile the app and extensions for the simulator
mise exec -- make test TEST_TARGETS=VaultifyTests   # unit tests on a throwaway simulator, same as CI
mise exec -- make test                              # unit, snapshot and UI suites
```

## Project structure

```text
Project.swift            Tuist manifest, the source of truth for targets and settings
Vaultify/                App target: features, design system, services, analytics
VaultifyCore/            Shared code compiled into the app and every extension
├── CArgon2/             Vendored Argon2id reference C
├── Crypto/              Key hierarchy, AES-GCM, KDF parameters
├── Store/ Models/       Vault store and domain models
└── Passkey/             WebAuthn types
VaultifyAutoFill/        iOS AutoFill Credential Provider (passwords, passkeys, codes)
VaultifyAutoFillMac/     macOS AutoFill provider (same sources, Mac capabilities)
VaultifySafari/          Safari web extension (Manifest V3 bundle in Resources/)
VaultifyTests/           Unit tests and crypto test vectors
VaultifySnapshotTests/   Snapshot tests
VaultifyUITests/         UI tests
Design System/           Design tokens, components and iOS UI kit reference
docs/                    Architecture, design guidelines, deployment and runbooks
scripts/ fastlane/       CI helpers and release automation
```

Start with [docs/codebase-summary.md](docs/codebase-summary.md) for the architecture and [docs/design-guidelines.md](docs/design-guidelines.md) for UI work.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first: it covers the Tuist workflow, localization (every string in English, Vietnamese and Japanese), the design system and conventional commits. Never paste real vault data, recovery keys or tokens into an issue.

## Security

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md). Do not open a public issue.

## License

Loox is free software: the source code is licensed under the [GNU General Public License v3.0](LICENSE).

Some bundled assets are **not** covered by the GPL and remain under their own licenses:

- Font Awesome Pro icons (the `dt_*` and `fa_*` assets) are proprietary to Fonticons, Inc. and may not be reused outside this app.
- Shopify Polaris icons are © Shopify and subject to Shopify's terms.
- The Loox name, logo and app icon. Forks must ship under their own name and branding.

Third-party code keeps its own license: Argon2 reference implementation (CC0 1.0 or Apache 2.0), Firebase Apple SDK (Apache 2.0), swift-snapshot-testing (MIT).
