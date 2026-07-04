# Seed-folder fix + UI state restoration

Two independent asks:

## A. Bug: onboarding-seeded identity/login land in "Unfiled" (chưa phân loại)
- Root cause: `seedIdentity` / `seedLooxAccount` / `IdentitySeed.make` create items with `folderId == nil`;
  normal editor auto-assigns `folders.first?.id` ("My Vault"). Seed path bypasses editor.
- Fix: capture the "My Vault" folder id returned by `addFolder` (already returns `String`) and set it on
  every seeded item before `repository.add`.
- File: `Vaultify/Features/Onboarding/OnboardingFlow.swift`.

## B. Feature: restore last screen + in-progress edits on relaunch
User choices: restore unsaved editor draft • restore tab + navigation depth • re-apply AFTER unlock
(vault locks on background by default).

### Design
- Encrypted UI-state snapshot sealed with the Vault Key (AES-256-GCM), written to app Documents with
  complete file protection. Contains: selected tab, per-tab `NavigationPath` (codable rep), pending
  editor draft (`VaultItem` + isNew).
- New `UIStateStore` (@MainActor @Observable) is the live source of truth for tab + 4 nav paths + draft,
  injected into the environment so screens bind directly.
- Save on scene `.background` **before** `session.lock()` (key still alive). Restore on unlock after
  `repository.reload()`. Wipe on Erase Vault.
- `VaultItem` + `VaultRoute` gain `Codable`. Draft re-presented from `MainTabView` via `.draft`/`.edit`.
- Watchtower deep path uses a non-Codable `WatchtowerCategory` → its depth simply won't serialize
  (graceful: `.codable` returns nil); tab + Home/Items/Search depth persist fully.

### Files
- New: `Vaultify/App/UIStateStore.swift`
- Edit: `VaultifyCore/Models/VaultItem.swift` (+Codable), `Vaultify/Features/Vault/VaultRoutes.swift` (+Codable),
  `Vaultify/App/AppEnvironment.swift`, `Vaultify/App/VaultifyApp.swift`, `Vaultify/App/RootView.swift`,
  `Vaultify/Features/Main/MainTabView.swift`, `HomeScreen.swift`, `ItemsScreen.swift`, `SearchScreen.swift`,
  `WatchtowerScreen.swift`, `Vaultify/Features/ItemEditor/ItemEditorScreen.swift`.

### Status — DONE (BUILD SUCCEEDED, app + extension)
- [x] A. Seed folder fix (OnboardingFlow threads My-Vault id into both seeds)
- [x] B1. VaultItem/VaultRoute Codable
- [x] B2. UIStateStore + env wiring (injected via VaultifyApp)
- [x] B3. RootView persist on .background (before lock) / restore on unlock
- [x] B4. Tab + path bindings (MainTabView + Home/Items/Search/Watchtower)
- [x] B5. Editor draft capture/clear
- [x] Build check (tuist generate + xcodebuild)

### Correctness notes
- `restore()` runs once per process launch (`hasRestored`) so a warm re-lock
  (foreground timeout/shake) doesn't rewind live in-memory nav state.
- `persist()` runs on `.background` before `session.lock()` drops the Vault Key.
- Watchtower category is non-Codable → its deep path just isn't serialized (tab still restored).
- No new user-facing strings → no Localizable.xcstrings change.
