# Vaultify — Native SwiftUI Rebuild

Rewrite the Flutter Vaultify (zero-backend, 1Password-class password manager) as a
**pure SwiftUI iPhone app** using **native Apple UI/UX** (NavigationStack, grouped
Lists, sheets, `.searchable`) but the **Polaris SVG icon set** (vector-PDF template
assets) instead of SF Symbols. High security. iPhone-only. iOS 17.6+.

Reference (features only): `/Users/bervion/Developer/Projects/mobile/flutter/vaultify`

## Locked decisions
- KDF: **Argon2id** — vendored canonical `phc-winner-argon2` C (`ref.c`), bridged to Swift. OWASP params (m=64MiB, t=3, p=4).
- Crypto: CryptoKit AES-256-GCM. Key hierarchy: masterPassword→Argon2id→KEK; random 32-byte VaultKey wrapped by KEK / Secure-Enclave / recovery key.
- Store: **SwiftData**, fully-sealed item blobs at rest (id + metadata columns + AES-GCM sealed payload). Decrypt to in-memory cache on unlock, zeroize on lock.
- Keys: Keychain (`...ThisDeviceOnly`) + Secure Enclave (`.biometryCurrentSet`) for biometric unlock.
- UI: native iOS. Icons: `Image("ic_*")` template assets in `Assets.xcassets/PolarisIcons`.
- Project uses Xcode synchronized folders → drop files in `Vaultify/`, no pbxproj per-file edits.

## Phases (full-parity attempt)
| # | Phase | Status |
|---|-------|--------|
| 00 | Foundation: Argon2 vendor, bridging header, icon catalog, iPhone-only | ✅ done |
| 01 | Security core: Argon2 wrapper+KAT, AES-GCM, key hierarchy, SecureBytes, Keychain, Enclave | ✅ done |
| 02 | Data: SwiftData models, sealed store, repositories, domain models | ✅ done |
| 03 | Design system: PolarisIcon, colors, mono text, components, theme | ✅ done |
| 04 | Session + auto-lock + app routing (RootView) | ✅ done |
| 05 | Onboarding: welcome, create master password, emergency kit, biometric, done | ✅ done |
| 06 | Unlock + recovery | ✅ done |
| 07 | Vault UI: home/list, categories, favorites, trash, item detail | ✅ done |
| 08 | Item editor + dynamic fields | ✅ done |
| 09 | Generator (password + EFF passphrase) + TOTP (RFC 6238) | ✅ done |
| 10 | Search (`.searchable`) | ✅ done |
| 11 | Watchtower: weak/reused/HIBP k-anonymity + health score | ✅ done |
| 12 | Import (1Password/Bitwarden/Chrome CSV) + encrypted export | ✅ done |
| 13 | Settings (security, privacy, appearance, change MP, regen kit, watchtower, about) | ✅ done |
| 14 | Passkeys / CloudKit sync / StoreKit 2 IAP / AutoFill ext | ⏸ deferred — need Apple Dev entitlements + extra targets |
| 15 | Localization EN+VI (String Catalog) + locale override | ✅ done (high-frequency strings; EN fallback) |

**Verified:** `BUILD SUCCEEDED`; launched on iPhone 16 sim in EN + VI. See `reports/implementation-260613-1006-vaultify-swiftui-native-rebuild-report.md`.

## Notes
- Platform-entitlement features (CloudKit, AutoFill extension, passkeys, IAP) are wired
  with real APIs but need the Apple Developer signing/entitlements to fully exercise on device.
- Files kept <200 LOC where practical. Swift `MainActor` default isolation in effect;
  crypto is `nonisolated`, heavy KDF runs off-main.
