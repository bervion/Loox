# Vaultify (iOS) — Codebase Summary

Native **SwiftUI** rewrite of the Flutter Vaultify — a zero-backend, on-device password
manager. **iPhone-only**, iOS 17.6+, Apple-native UI/UX, with the **Polaris SVG icon set**
(vector-PDF template assets) instead of SF Symbols. ~4,100 LOC across 65 Swift files.

## Architecture

```
Vaultify/
├── App/                     Composition root + routing
│   ├── VaultifyApp.swift     @main, injects AppEnvironment + locale + colorScheme
│   ├── AppEnvironment.swift  @Observable root: settings, session, store, repository, clipboard
│   ├── RootView.swift        routes onboarding / locked / unlocked; scene-phase auto-lock + privacy shield
│   └── SettingsStore.swift   UserDefaults flags (appearance, auto-lock, biometric, HIBP, clipboard, language)
├── Security/
│   ├── CArgon2/              vendored phc-winner-argon2 reference C (ref.c) — bridged via Vaultify-Bridging-Header.h
│   ├── Crypto/               Argon2 (KAT), AESGCM (CryptoKit), KeyHierarchy, SecureBytes (mlock+zero), KdfParams, CryptoRandom
│   ├── Keychain/             KeychainStore, VaultKeyBundle, BiometricKeyStore (.biometryCurrentSet), BiometricAuth
│   ├── RecoveryKey.swift      Crockford base32 Emergency Kit key
│   ├── VaultSession.swift     @Observable lock lifecycle: create/unlock/biometric/lock, off-main KDF
│   └── VaultSession+Recovery.swift  recovery, change master password, reset
├── Data/
│   ├── Models/              ItemCategory, FieldKind, DynamicField, VaultItem + ItemSecret (pure, Sendable)
│   ├── Store/               ItemRecord (@Model, fully-sealed payload), VaultStore (ModelContainer)
│   └── Repositories/        VaultRepository (@Observable): decrypt→cache on unlock, CRUD, trash, favorites
├── DesignSystem/           PolarisIcon + Icons, VaultColors (dynamic light/dark), PasswordStrength, Typography
├── Services/
│   ├── PasswordGenerator + DicewareWordList (EFF 7776), TOTPGenerator (RFC 6238), Haptics, ClipboardService
│   ├── Watchtower/          PasswordAudit (weak/reused/score), HIBPService (k-anonymity)
│   └── ImportExport/        VaultBackup (CSV + Argon2id/AES-GCM encrypted backup)
└── Features/                Onboarding, Unlock, Main (tabs), Vault, ItemDetail, ItemEditor, Generator, Search, Watchtower, Settings, ImportExport, Components
```

## Security model
- **KDF:** Argon2id (canonical reference C, OWASP 64 MiB/t=3/p=4) → KEK. Verified against the published v1.3 KAT.
- **Key hierarchy:** random 256-bit Vault Key, wrapped (AES-256-GCM) by the password KEK and an Emergency-Kit recovery KEK; biometric path stores the Vault Key in a `.biometryCurrentSet` Keychain item (Secure Enclave-gated).
- **At rest:** every item is a single AES-256-GCM sealed `ItemSecret` blob in SwiftData; only low-sensitivity metadata (timestamps, favorite, trashed) is plaintext. Decrypted into an in-memory cache on unlock; cleared on lock.
- **Hygiene:** `SecureBytes` (mlock + memset_s), local-only auto-expiring clipboard, auto-lock (inactivity + background), app-switcher privacy shield, HIBP via k-anonymity (only 5 hash chars leave the device).

## Build
See memory `vaultify-ios-build-setup`. `xcodebuild -scheme Vaultify -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd`. Xcode synchronized folders → new files auto-compile. Bridging header + `HEADER_SEARCH_PATHS` wire the Argon2 C.

## Status
Implemented & verified running (EN + VI): onboarding, master password, Emergency Kit, biometric unlock, recovery, full vault (5 categories, dynamic encrypted fields, favorites, trash, search), item detail (reveal/copy/live TOTP/URL), editor, password+passphrase generator, Watchtower (weak/reused/HIBP), import/export, settings, change MP, regenerate kit, about, light/dark, VI+EN.

**Deferred (need Apple Developer entitlements / extra targets):** CloudKit sync, AutoFill Credential Provider extension, passkeys (ASAuthorization), StoreKit 2 IAP/paywall. Service interfaces and security core are ready for these.

**Last updated:** 2026-06-13
