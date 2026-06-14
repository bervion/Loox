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
│   ├── Models/              ItemCategory, FieldKind, DynamicField, VaultItem + ItemSecret (+tags), Folder/FolderSecret/FolderColor (pure, Sendable)
│   ├── Store/               ItemRecord (@Model, +lastUsedAt) & FolderRecord (@Model, sealed name), VaultStore (ModelContainer)
│   └── Repositories/        VaultRepository (@Observable, + VaultRepository+Folders): decrypt→cache, CRUD, trash, favorites, folders, recents, tags
├── DesignSystem/           PolarisIcon + Icons, VaultColors (dynamic light/dark), PasswordStrength, Typography
├── Services/
│   ├── PasswordGenerator + DicewareWordList (EFF 7776), TOTPGenerator (RFC 6238), Haptics, ClipboardService
│   ├── Watchtower/          PasswordAudit (weak/reused/score), HIBPService (k-anonymity)
│   └── ImportExport/        VaultBackup (CSV + Argon2id/AES-GCM encrypted backup)
└── Features/                Onboarding, Unlock, Main (4 tabs: Home·Items·Watchtower·Search), Home (personalized: Pinned/Favorites/Recently Created/Frequently Used/Utilities + Customize), Items (Spaces/Categories/Tags/Archive/Recently Deleted), Folders, ItemDetail, ItemEditor, Generator, Search, Watchtower, Settings, ImportExport, Components
```

## Security model
- **KDF:** Argon2id (canonical reference C, OWASP 64 MiB/t=3/p=4) → KEK. Verified against the published v1.3 KAT.
- **Key hierarchy:** random 256-bit Vault Key, wrapped (AES-256-GCM) by the password KEK and an Emergency-Kit recovery KEK; biometric path stores the Vault Key in a `.biometryCurrentSet` Keychain item (Secure Enclave-gated).
- **At rest:** every item is a single AES-256-GCM sealed `ItemSecret` blob in SwiftData; only low-sensitivity metadata (timestamps, favorite, trashed) is plaintext. Decrypted into an in-memory cache on unlock; cleared on lock.
- **Hygiene:** `SecureBytes` (mlock + memset_s), local-only auto-expiring clipboard, auto-lock (inactivity + background), app-switcher privacy shield, HIBP via k-anonymity (only 5 hash chars leave the device).

## Vault Organization (Folders & Tags)
- **Folders ("Spaces")** — one per item via `VaultItem.folderId`; `nil` = Unfiled. `FolderRecord` keeps the **name sealed** (AES-GCM under the Vault Key) while icon/color/sortIndex/sync metadata stay plaintext so the Spaces grid renders without unsealing. CRUD + counts + reassign-on-delete (members → Unfiled, items never deleted) live in `VaultRepository+Folders`.
- **Tags** — many per item, stored lightweight as `tags: [String]` inside the sealed `ItemSecret` (no separate record). Aggregated case-insensitively by `allTags()`; surfaced as `#` chips.
- **Recents** — `ItemRecord.lastUsedAt` (plaintext, device-local, NOT synced); `markUsed` writes it without re-sealing/`dirty` on copy/reveal; powers Home's "Recently Used".
- **Home dashboard** (`VaultListScreen` → `HomeDashboard`): Quick Access (favorites + recents) → Spaces grid (tap → folder-color-tinted `FolderItemsScreen`) → Tags row → All Items (category-grouped). Search stays global.
- **Default space:** first launch seeds a renameable **"My Vault"** space; new items default to the primary space.
- **Navigation (4 tabs):** **Home** = personalized dashboard (Pinned · Favorites · Recently Created · Frequently Used, + optional Recently Used/Modified via Customize, + Utilities/Generator; Settings via header gear). **Items** = organization browser (Spaces + Create Space · Categories · Tags · Archive · Recently Deleted). **Watchtower** (security). **Search** = smart search (token-AND over title/fields/tags + Space name). Each tab owns a NavigationStack sharing `vaultNavigationDestinations()`.
- **Pinned / Archived / Frequently-Used:** `pinned`/`archived`/`useCount` are plaintext `ItemRecord` columns (codec untouched). `reload()` splits items 3-way (live / archived / trashed) so archived stays out of every normal surface (Home, Items, Search, counts, AutoFill) but lives in Archive. `togglePin`/`archive`/`unarchive` are column-only (no re-seal, no `updatedAt` bump); `markUsed` bumps `useCount`.
- **Back-compat (critical):** `ItemSecret`/`PortableItem` use a custom `init(from:)` that `decodeIfPresent`s `tags` (default `[]`) so pre-existing sealed blobs and old backups still open.
- **CSV/backup:** export adds `folder` + `tags` columns; import matches/creates folders by name. **CloudKit:** `FolderRecord` syncs as `"VaultFolder"` (sealed name + metadata) behind the `VAULTIFY_ICLOUD` gate; tags ride inside the item blob.

## Theming & Wallpaper
Telegram-adapted (no chat). **Core** in `VaultifyCore/Theme/` (shared into app + AutoFill
extension): `AppTheme` (semantic palette, packed `0xRRGGBB`); built-ins Day / Day-Classic /
Night / Night-Tinted (`BuiltinThemes`); accent HSB recolor (`AccentColor`); `ThemeSettings`
(Codable — theme ref + per-theme accent/wallpaper + custom themes + auto-night + font scale);
`ThemePalette.resolve` (pure); `ThemeReader` (App-Group persist + one-time migrate from
`appearance_mode`); `Wallpaper`/`WallpaperSettings`; `MeshMath` + `MeshGradientRenderer`
(CPU mesh); `ThemeExchange` (`.vaultheme` codec).
- **App layer:** `ThemeStore` (`@MainActor @Observable`) resolves the active `AppTheme`,
  persists, and drives `\.appTheme` + `.tint` + `preferredColorScheme` from the root;
  `ThemeHolder` is a static snapshot for `VaultColors`. Reusable components
  (`DesignSystem/Components`): `ThemedCard`, `.themedForeground(role)`, `.appBackground()`,
  `.themedFormBackground()`, button styles (`.themedProminent/.themedTinted/.themedDestructive`)
  — all read the active theme, so changing a theme or a component restyles the whole app.
- **Wallpaper:** solid / multi-stop gradient / procedural pattern (Canvas, soft-light) / image
  (`PhotosPicker`, no Photos permission; stored file-protected in the App Group) / **animated
  mesh** (Telegram's CPU `generateGradient` frames played via `CAKeyframeAnimation` — no Metal;
  morphs on unlock-fail / tab change; honors Reduce Motion). Rendered behind the canvas (vault
  tabs) + lock + onboarding; settings/detail stay solid. Reduce Transparency drops blur.
- **Settings UI** (`Features/Settings/Appearance`): theme / accent / wallpaper / auto-night
  (off·system·scheduled·brightness) / text size / reduce motion, plus a custom **theme editor**
  with `.vaultheme` import/export. All strings EN + VI. Tests: `VaultifyTests/ThemeEngineTests`.

## Build
See memory `vaultify-ios-build-setup`. `xcodebuild -scheme Vaultify -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd`. Xcode synchronized folders → new files auto-compile. Bridging header + `HEADER_SEARCH_PATHS` wire the Argon2 C.

## Status
Implemented & verified running (EN + VI): onboarding, master password, Emergency Kit, biometric unlock, recovery, full vault (5 categories, dynamic encrypted fields, favorites, trash, search), item detail (reveal/copy/live TOTP/URL), editor, password+passphrase generator, Watchtower (weak/reused/HIBP), import/export, settings, change MP, regenerate kit, about, light/dark, VI+EN. **Vault organization:** Spaces (sealed-name folders w/ icon+color), tags, Home dashboard (Quick Access/recents/Spaces grid/tags), folder-tinted & tag-filtered lists, CSV/backup + CloudKit folder support.

**Deferred (need Apple Developer entitlements / extra targets):** CloudKit sync, AutoFill Credential Provider extension, passkeys (ASAuthorization), StoreKit 2 IAP/paywall. Service interfaces and security core are ready for these.

**Last updated:** 2026-06-14
