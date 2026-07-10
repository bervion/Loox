# Kiểm kê màn hình / flow UI hiện có — Loox (Vaultify iOS)

> Scout 260710. Nguồn: `Vaultify/` (app), `VaultifyCore/` (shared), `VaultifyAutoFill/` (extension).
> Root router: `Vaultify/App/RootView.swift` — switch 3 route: `onboarding` → `locked` → `unlocked` (+ PrivacyShield overlay khi background nếu `hideInAppSwitcher`).
> Unlocked shell: `Features/Main/AdaptiveRootView.swift` — compact = `MainTabView` (iPhone), regular = `VaultSidebarView` (iPad), macOS = `MacRootView` (3 cột). Shared behaviors (toast, auto-lock, approval sheet, draft-restore) = `VaultShellBehaviors.swift`.

---

## 1. Tab structure (iPhone shell)

File: `Vaultify/Features/Main/MainTabView.swift` — native `TabView`, icon-only Polaris, 4 tab. iOS 18+ dùng `Tab` builder, Search mang `role: .search`; iOS 17.6 fallback `.tabItem`. Tab selection persist qua `UIStateStore.selectedTab`.

| Tab | Screen | File |
|---|---|---|
| Home | `HomeScreen` | `Features/Home/HomeScreen.swift` |
| Items | `ItemsScreen` | `Features/Items/ItemsScreen.swift` |
| Watchtower | `WatchtowerScreen` | `Features/Watchtower/WatchtowerScreen.swift` |
| Search | `SearchScreen` | `Features/Search/SearchScreen.swift` |

**KHÔNG có tab Settings** — Settings là sheet mở từ header icon trên Home.

Push destinations dùng chung cho 3 stack (Home/Items/Search): `Features/Vault/VaultRoutes.swift` — `String` → ItemDetail, `VaultRoute` (folder/tag/category/manageFolders/archive/recentlyDeleted), `SharedWithMeRoute`, `NotificationsRoute`. Nav path persist per-tab trong `UIStateStore` (homePath/itemsPath/searchPath — state restoration sau unlock).

### Home hiện tại (HomeScreen)
- **Header** (`Features/Home/Components/HomeHeaderBar.swift`, compose `VaultScreenHeader`): trái = wordmark Loox; phải = glass cluster **Notifications (bell + badge count)** · **Add (+ menu chọn category)** · **Settings (gear → sheet)**. Header float overlay, glass blur khi scroll-under. KHÔNG còn Space switcher trên header (đã chuyển xuống section "All").
- **Body** (thứ tự): Profile row (avatar + active persona name + kind·email → push `ProfileScreen`) → Quick actions grid 2×2 (Add Item menu · Generate → GeneratorScreen sheet · 2FA (badge count) → TotpListScreen sheet · Watchtower (badge issue count) → switch tab) → Approval-needed row (khi có pending owner request; 1 = sheet ceremony, >1 = push Notifications) → TOTP horizontal scroller (`TotpCardView`) → Needs Attention (max 4, `AttentionCell`) → Favorites → All items (pinned trước; header = Space switcher "All Spaces · N" → `HomeFolderPickerSheet` + nút Sort toggle).
- **States**: empty vault (lock crest + CTA Add Item menu); Space filter per-persona persist; shared items luôn join feed.
- Sheets từ Home: `ItemEditorScreen` (editorTarget), `SettingsScreen`, `GeneratorScreen`, `HomeFolderPickerSheet`, `TotpListScreen`, `ApprovalRequestSheet`.

### Items tab (ItemsScreen)
Organisation browser: Spaces (mỗi folder → push `FolderItemsScreen`; Unfiled; **Shared with Me** system space → push `SharedWithMeScreen`; Create Space row → `FolderEditorSheet` sheet) → Categories (→ push `ItemListScreen(category:)`) → Tags (→ push `TagItemsScreen`) → standalone **Archive** (→ `ArchiveScreen`) + **Recently Deleted** (→ `TrashScreen`). Header có Add menu.

### Watchtower tab (WatchtowerScreen)
Score ring hero (270° speedometer, `WatchtowerScoreRing`) → issue list → drill-down categories (enum `WatchtowerCategory`: compromised / reused / weak / missing2FA) → push `WatchtowerCategoryScreen` (`Features/Watchtower/WatchtowerCategoryScreen.swift`, list issue → push ItemDetail). Sheet `ItemEditorScreen` để fix tại chỗ. HIBP breach check opt-in (Settings toggle). `WatchtowerStrengthCard` component.

### Search tab (SearchScreen)
Own NavigationStack + `.searchable(isPresented:)` auto-activate on appear; iOS 18+ native search tab (iOS 26: field nằm trong tab bar). Scope theo Space (`SpaceScope.swift`). Kết quả → push ItemDetail.

### iPad / Mac
- `VaultSidebarView` + `VaultSidebarList` (regular width iPad): sidebar thay tab.
- `MacRootView` + `MacSidebarList` + `MacItemListColumn` + `MacHeaderBar`: 3 cột sidebar·list·detail, toolbar search, KHÔNG có Home/Search screen; Settings = native window (⌘,) `MacSettingsView`; Profile = sheet.

---

## 2. Item screens

| Screen | File | Mở từ | Kiểu | State chính |
|---|---|---|---|---|
| Item Detail | `Features/ItemDetail/ItemDetailScreen.swift` | push từ mọi list (route `String` = itemID) | push | owned vs `shared::` projection; trashed/archived; not-found; shared loading |
| Item Editor | `Features/ItemEditor/ItemEditorScreen.swift` | sheet từ Home/Items/Detail/Watchtower/TotpList/Profile/shell (otpauth import, draft restore) | sheet | `EditorTarget` .new/.edit/.draft; dynamic fields add/remove/reorder; login sections (Credentials/Websites/Custom/Notes, multi-website); rotation picker; tags (`TagChipEditor`) |
| Generator | `Features/Generator/GeneratorScreen.swift` (+`PasswordGeneratorView`) | sheet từ Home quick action; embedded sheet trong Editor (per-field GeneratorRequest) | sheet | output, regenerate; không có history |
| 2FA list | `Features/Home/TotpListScreen.swift` | sheet từ Home quick action "2FA" / "View All" | sheet | grid `TotpCardView`; edit → editor sheet |
| TOTP scanner | `Features/ItemEditor/TOTPScannerSheet.swift` (+`QRScannerView`/Overlay) | sheet từ login editor section | sheet | camera QR / Photos screenshot / paste setup key |
| Attachment picker | `Features/ItemEditor/AttachmentPickerSheet.swift` | sheet từ editor | sheet | — |
| Icon picker | `Features/ItemEditor/ItemIconPickerSheet.swift` | sheet từ editor | sheet | — |
| Large Type | `Features/ItemDetail/LargeTypeView.swift` | fullScreenCover từ `DetailFieldRow`/`ProtectedFieldRow`/`RequestCodeView` | fullScreenCover | per-char grid màu-coded, tap-to-mark, TOTP floating code |
| Protect Field | `Features/ItemDetail/ProtectFieldSheet.swift` | sheet từ `DetailFieldRow` | sheet | scheme Level-2 vs custom code |
| Protected field reveal | `Features/ItemDetail/ProtectedFieldRow.swift` + `CodePromptSheet.swift` | inline row + sheet prompt | sheet | locked/revealed |
| Located In | `Features/ItemDetail/LocatedInSheet.swift` | sheet từ detail header | sheet | + Move picker sheet |
| Passkeys section (owned) | `Features/Passkeys/ItemPasskeysSection.swift` | inline trong detail | — | → `PasskeyDetailSheet` |
| Passkeys section (shared) | `Features/Passkeys/SharedItemPasskeysSection.swift` | inline trong shared detail | — | metadata-only |
| Passkey detail | `Features/Passkeys/PasskeyDetailSheet.swift` | sheet từ section / PasskeysScreen / login editor | sheet | delete confirm |

Detail toolbar: Share (→ ShareAccessSheet) + "…" menu (Edit / **Open on Computer** (Quick View, exposure-gated) / Share Website Link / Archive-Unarchive). Shared item: "…" = Leave Share. Field rows tap-to-copy; TOTP row (`TOTPFieldRow`), attachment row.

---

## 3. Onboarding + Lock

### Onboarding (`Features/Onboarding/OnboardingFlow.swift`) — state machine, thứ tự:
1. `welcome` — hero logo + 3 FeatureCard + "Get Started" + "Sync from another device" (nếu iCloud configured)
2. `join` — `JoinVaultFlow.swift` (nhánh riêng: choice → qrPairing / recoveryEntry → password → biometric)
3. `create` — `CreateMasterPasswordView.swift` (strength meter, confirm)
4. `name` — `NameStepView.swift` (display name + email; seed default identity + "Loox Account" login + "My Vault" Space)
5. `emergencyKit` — `EmergencyKitView.swift` (recovery key + BẮT BUỘC save PDF trước khi tiếp)
6. `theme` — `ChooseThemeView.swift` (appearance mode)
7. `biometric` — `EnableBiometricView.swift` (optional, skip được)
8. `done` — OnboardingDoneStep ("Open Loox")

### Lock (`Features/Unlock/LockScreen.swift`)
2 mode: **biometric** (logo + `BiometricBadge`, auto-prompt Face ID, 3 fail → password) / **password** (`LockPasswordField`, "Forgot password?" → sheet `RecoveryView.swift` — recovery key + set new master password). Deliberate lock (shake / Lock Now) yêu cầu `SlideToUnlock` trước Face ID.

---

## 4. Sharing / Approval Mode

| Screen | File | Mở từ | Kiểu | State chính |
|---|---|---|---|---|
| Share Access (owner flow) | `Features/Sharing/ShareAccessSheet.swift` | sheet từ detail Share button; resume từ Notifications | sheet | Step machine: **choose** (Quick Link vs iCloud share) → checking → blocked → **config** (recipient email, per-field `FieldCapabilityRow`/`PasskeyCapabilityRow`, device scope, hand-over confirm) → creating → **waiting** (invite link, iMessage compose) → **fingerprint** (`TrustFingerprintView` safety code) → publishing → done / failed |
| Quick Link (Loox Link) | `Features/Sharing/QuickLinkView.swift` + `QuickLinkResultView.swift` + `QuickLinkFieldRow` | bước trong ShareAccessSheet | trong sheet | config (fields + TTL) → creating → result (link duy nhất chứa key) + revoke list device-local |
| Notifications inbox | `Features/Sharing/NotificationsScreen.swift` | push từ Home bell / approval row (`NotificationsRoute`) | push | 4 section: Share invitations · Approval requests · Shares you sent (resume) · Recent history; empty state |
| Approval ceremony (owner) | `Features/Sharing/ApprovalRequestSheet.swift` | sheet auto-present từ shell/Home/Notifications | sheet | verified request → Face ID approve/reject |
| Recipient request-code | `Features/Sharing/RequestCodeView.swift` | inline trong shared item detail (askEachTime TOTP) | inline | IDLE→REQUESTING→WAITING→APPROVED/REJECTED/EXPIRED/SUPERSEDED |
| Shared with Me | `Features/Sharing/SharedWithMeScreen.swift` | push từ Home/Items (`SharedWithMeRoute`) | push | projected list → ItemDetail thường |
| Shared access gate | `Features/ItemDetail/SharedAccessGateView.swift` | wrap fields của shared detail | — | verifying/authorized/denied — secret chỉ render khi authorized |
| Recipient mgmt | `Features/Sharing/ShareRecipientDetailSheet.swift` | sheet từ detail sharing section | sheet | per-field cap edit, update mode, revoke |
| Invite prompts | `Features/Sharing/InviteInboxBehaviors.swift` | shell modifier (alert) | alert | accept/decline invite |
| iMessage compose | `Features/Sharing/MessageComposeView.swift` | sheet từ waiting step | sheet | — |

### Quick View ("Open on Computer" — browser handoff)
`Features/Sharing/QuickView/`: entry = detail "…" menu (exposure + capability gated) → `QuickViewEntryChooserSheet` (Scan QR / Enter Code) → `QuickViewScannerSheet` hoặc `QuickViewEnterCodeSheet` (format XXXX-XXXX) → `QuickViewApprovalSheet` (browser context, SAS match/abort, per-field toggles, expiry countdown, Face ID). Model: `QuickViewApprovalFlowModel`.

---

## 5. Settings + màn con

Settings = **sheet** từ Home header gear (`Features/Settings/SettingsScreen.swift`, `VaultSheetScaffold` + Form). Sections + push con (NavigationLink):

- **Security**: biometric toggle · Auto-Lock picker · Shake-to-lock · **Change Master Password** (`ChangeMasterPasswordView.swift`) · **Emergency Kit** (`RegenerateKitView.swift` — view/regenerate key + export PDF) · **Extra Protection** (`Level2SettingsView.swift` — Level-2 password) · Automatic passkey upgrades toggle
- **AutoFill**: Set up password AutoFill (iOS 18+ in-app prompt) · Set up verification codes (deep-link)
- **Organization**: Spaces → `ManageFoldersScreen` (+ `FolderEditorSheet`)
- **Online Features**: Private Email toggle · Share Links toggle (capability status text)
- **Privacy**: hide in app switcher · clear clipboard picker
- Show website icons toggle
- **Appearance**: **Theme & Wallpaper** → `Appearance/AppearanceSettingsView.swift` (theme · 7 accent preset · auto-night → `AutoNightSettingsView` · text size · motion; wallpaper picker + custom theme editor bị gate OFF nhưng code còn: `ThemeEditorView`, `WallpaperGalleryView`) · Language picker (System/EN/VI)
- **Watchtower**: HIBP breach check toggle
- **Data**: **iCloud Sync** → `SyncSettingsView.swift` (+ `PairDeviceSheet.swift` QR pairing) · **Passkeys** → `PasskeysScreen.swift` (group theo site → `PasskeyDetailSheet`) · **Import** → `ImportExport/ImportView.swift` (CSV 1Password/Bitwarden/Chrome + encrypted backup) · **Export** → `ImportExport/ExportView.swift` (encrypted / CSV)
- Lock Now · **Erase Vault** (confirm dialog, block nếu relay alias active + offline)
- DEBUG: Share Diagnostics (`ShareDiagnosticsView.swift`)
- **About** → `AboutView.swift` (CÓ RỒI: logo, version/build, crypto explainers, privacy note; không có link web/acknowledgements/rate)

---

## 6. Profile / Identity / Personas / Private Email

| Screen | File | Mở từ | Kiểu |
|---|---|---|---|
| Profile | `Features/Profile/ProfileScreen.swift` | push từ Home profile row (`ProfileRoute`); Mac = sheet | push | avatar header (`ProfileAvatarView` đổi ảnh) · persona card (switch menu) · Identity section (picker + fields) · Payment card section |
| Persona switcher | `Features/Personas/PersonaSwitcherScreen.swift` | push từ Profile "Manage personas" | push | list/switch/create/edit/delete + isolation policy; `PersonaEditorSheet` (sheet) |
| Private Email (aliases) | `Features/Personas/PersonaAliasesScreen.swift` | push từ Profile "Private Email" | push | stable alias + per-site aliases; capability banner; `AliasEditorSheet` (sheet, chọn login bind + domain picker `AliasDomainPicker`) |
| Alias detail | `Features/Personas/AliasDetailScreen.swift` | push từ alias list | push | address, forward-to, bindings, disable/delete |
| Forwarding inboxes | `Features/Personas/ForwardingInboxScreen.swift` | push từ PersonaAliases / AliasDetail | push | derived + manual inboxes, default, update-existing |
| Affected accounts | `Features/Personas/AffectedAccountsScreen.swift` | push từ PersonaAliases | push | logins phụ thuộc private-email |

---

## 7. AutoFill extension UI (`VaultifyAutoFill/`)

Host: `CredentialProviderViewController.swift`. Mọi flow qua `UnlockGate.swift` (Face ID shared-keychain → fallback master password, host NavigationStack + Cancel).

| View | File | Chức năng |
|---|---|---|
| AutoFillView | `AutoFillView.swift` | unlock → pick login (matched site trước) hoặc tạo mới |
| CreateLoginView | `CreateLoginView.swift` | tạo login trong lúc đăng ký web (site prefill, password generated) |
| SavePasswordView | `SavePasswordView.swift` | native iOS 26.2 "Save password" confirm |
| OneTimeCodeView | `OneTimeCodeView.swift` | TOTP fill (single auto, multi picker) |
| PasskeyActionView / PasskeyCeremonyView | `PasskeyActionView.swift` / `PasskeyCeremonyView.swift` | passkey register/assert (+ password fallback) |

---

## 8–9. Các flow phụ — có / chưa

| Flow | Trạng thái | Ghi chú |
|---|---|---|
| Trash / Recently Deleted | ✅ `Features/Vault/TrashScreen.swift` — push từ Items (restore / delete / empty) | |
| Archive | ✅ `Features/Items/ArchiveScreen.swift` — push từ Items | |
| Recovery (forgot password) | ✅ `Features/Unlock/RecoveryView.swift` — sheet từ LockScreen | |
| Large Type | ✅ fullScreenCover | |
| Protect Field (Extra Protection) | ✅ sheet + Level2SettingsView | |
| Open on Computer / Quick View | ✅ đã build đủ UI (chooser/scanner/code/approval) — nhưng **exposure-gated**, GA phụ thuộc signed control-plane manifest (fix mới xong chưa commit) | |
| Loox Link (Quick Link) | ✅ UI xong trong ShareAccessSheet; backend prod-gating pending | |
| Emergency Kit PDF | ✅ onboarding + Settings regenerate + scan-to-recover (JoinVaultFlow) | |
| About | ✅ có | |
| Rotation reminders | ✅ editor picker + attention cell; không có màn riêng | |
| Folder/Space mgmt | ✅ ManageFolders + FolderEditor + 2 picker sheet | |

---

## Nhận xét khoảng trống (màn/flow phổ biến chưa có)

1. **Password history / field history** — không có version history per-item (1Password/Bitwarden đều có). Đổi password là mất giá trị cũ (trừ Trash).
2. **Generator history + passphrase mode** — Generator không lưu history; cần check có diceware/passphrase & PIN mode chưa (PasswordGeneratorView chỉ 1 view, không có tab passphrase rõ ràng).
3. **Onboarding "import từ app khác"** — Import chỉ nằm sâu trong Settings; first-run không offer import CSV/1Password (điểm rơi adoption phổ biến).
4. **Widget / Lock-screen widget / Watch app** — không có target nào ngoài app + autofill.
5. **App Shortcuts / Siri intents** — không thấy AppIntents.
6. **Watchtower thiếu categories phổ biến**: expiring cards / expired documents, unsecured websites (http), 2FA chưa bật nhưng site hỗ trợ có rồi (missing2FA) nhưng không có "compromised website vault-wide breach timeline", không có Passkey-available suggestion list ở Watchtower (passkey upgrade tồn tại ở autofill layer).
7. **Tag management screen** — tags chỉ browse (TagItemsScreen) + chip editor; không có màn rename/merge/delete tag.
8. **Bulk actions / multi-select** trong list (move nhiều item vào Space, bulk trash) — chưa có.
9. **Item type templates mở rộng** (SSH key, API credential, driver license, passport…) — tuỳ `ItemCategory` hiện tại; đáng audit khi redesign.
10. **In-app help / onboarding tips / What's New** — không có changelog screen hay coach-marks.
11. **Search nâng cao** — không có filter theo field type / recent searches (SearchScreen khá tối giản).
12. **Settings về notification preferences** — approval/share push không có màn cấu hình.
13. **CSV import preview/mapping UI** — ImportView parse thẳng, không có bước map cột thủ công.
14. **Travel mode / hidden vault** — không có.
15. **Account/subscription screen** — app zero-backend nên chưa cần, nhưng nếu redesign có monetization thì thiếu chỗ đặt.

## Unresolved questions
- `PasswordGeneratorView` có passphrase mode không — chưa đọc kỹ file, cần xác nhận khi redesign generator.
- iPad `VaultSidebarView` mức độ hoàn thiện so với iPhone (chỉ skim header) — cần QA riêng nếu redesign phủ iPad.
