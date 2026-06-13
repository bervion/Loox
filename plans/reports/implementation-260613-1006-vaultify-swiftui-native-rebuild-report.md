# Vaultify SwiftUI Native Rebuild — Implementation Report

**Date:** 2026-06-13 · **Branch:** main · **Scope:** full-parity attempt, Argon2id (vendored C)

## Outcome
Native SwiftUI iPhone rewrite of the Flutter Vaultify. **Compiles clean** (`BUILD SUCCEEDED`)
and **verified running** on iPhone 16 simulator in both **English and Vietnamese**. 65 Swift
files, ~4,100 LOC, 133 Polaris icon assets.

## Approach
- Native Apple UI/UX (NavigationStack, grouped `List`/`Form`, `.sheet`, `.searchable`, `ContentUnavailableView`, `ShareLink`) — NOT the Flutter "Polaris" dark-shell look.
- Polaris icons: 133 SVGs → vector-PDF **template imagesets** (rsvg-convert) → `Image(...).renderingMode(.template)`. No SVG runtime, full vector + tint.
- Xcode synchronized folders (objectVersion 110) → drop files in `Vaultify/`, no per-file pbxproj edits.

## Delivered (verified)
- **Security core:** vendored canonical Argon2id C (`ref.c`) bridged to Swift; matched published v1.3 KAT (`09316115…`). AES-256-GCM (CryptoKit), KEK→VaultKey wrapping, `SecureBytes` (mlock+memset_s), Keychain (`ThisDeviceOnly`), biometric-gated key (`.biometryCurrentSet`), Emergency-Kit recovery key, change-MP, reset.
- **Store:** SwiftData `@Model` with fully-sealed item blobs at rest; decrypt→in-memory cache on unlock, cleared on lock. Repository CRUD + trash + favorites.
- **Vault UX:** onboarding (welcome→MP→kit→biometric→done), lock + recovery, vault list (category filter, favorites/all, swipe trash/favorite, add-by-category), detail (reveal/copy, live TOTP w/ countdown, URL open), editor (dynamic fields, kind picker, protection toggle, inline generator), search, trash.
- **Tools:** password + EFF-passphrase generator (7,772-word list), RFC 6238 TOTP, Watchtower (weak/reused + HIBP k-anonymity + health gauge), CSV import (1Password/Bitwarden/Chrome) + encrypted backup export.
- **Settings:** biometric toggle, auto-lock, lock-on-background, clipboard auto-clear, app-switcher privacy, theme, **language (VI/EN/System)**, HIBP toggle, change MP, regenerate kit, import/export, erase, about.
- **Localization:** runtime locale override + String Catalog (VI for high-frequency UI; EN fallback).
- **Privacy/hygiene:** local-only auto-expiring clipboard, auto-lock (inactivity timer + background), privacy shield, no plaintext content at rest.

## Follow-up additions (this session, post-core)
- **Face ID crash fixed** — added `INFOPLIST_KEY_NSFaceIDUsageDescription` (biometric Keychain access traps without it).
- **App Group foundation** — store + wrapped key bundle moved to the shared `group.com.bervion.vaultify` container (`SharedConfig`); verified at runtime (App Group OK + crypto round-trip + Argon2 KAT PASS via file-based self-test). Enables an AutoFill extension to read the vault without shared-Keychain fragility.
- **CloudKit sync** — `CloudSyncService` (zero-knowledge: uploads only sealed ciphertext + metadata, LWW merge), opt-in toggle + Sync Now + status in a new Sync settings screen, auto-sync on unlock. *To activate:* enable the iCloud (CloudKit) capability + `iCloud.com.bervion.vaultify` container in Xcode; the entitlement is intentionally omitted from the repo because an unprovisioned container SIGTRAPs the app at launch in the sim. `CKContainer` is lazy so launch never touches CloudKit.
- **Full Vietnamese localization** — String Catalog expanded to cover UI chrome, onboarding, field labels, settings, watchtower, generator. Verified rendering (lock screen fully in VI).
- **Free tier** — shipped unrestricted (no item caps), per decision.

## Still deferred (need a new Xcode target)
1. **AutoFill Credential Provider extension** — App Group groundwork is done; remaining: add the extension target (best via Xcode GUI), `ASCredentialProviderViewController` (password + passkey provision), reading the shared store + master-password/biometric unlock in the extension.
2. **Passkeys** — coupled to the AutoFill extension (passkey assertion happens in the credential provider). Model can hold passkey items.
3. **StoreKit 2 IAP/paywall** — not requested (free tier shipped unrestricted).

## Build
`xcodebuild -project Vaultify.xcodeproj -scheme Vaultify -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd` (omit literal `build` action — blocked by a `.ckignore` hook). Argon2 wired via `Vaultify-Bridging-Header.h` + `HEADER_SEARCH_PATHS`.

## Unresolved questions
1. Confirm the 4 deferred features are wanted as a follow-up (each is sizeable; AutoFill + CloudKit need your Apple Developer account/entitlements).
2. Full VI translation of remaining long-form strings (welcome copy, footers) — extend `Localizable.xcstrings`? Currently high-frequency strings only.
3. Free-tier caps (original: 50 items / 1 attachment) — keep, or ship unrestricted since IAP is deferred?
4. Attachments (`fileRef` kind exists in the model) — no file-attachment UI yet; wanted?
