# Strings Manifest — Item Editor deferred follow-ups (masked multiline + date picker)

New copy from implementing the two Phase-6 deferrals: masked-editing for protected multiline
fields (`MaskedMultilineFieldEditor`) and a `DatePicker` for `.date`-kind fields
(`DateFieldEditor`). Verified against `Vaultify/Localizable.xcstrings` — both keys below are new
(not present under any existing source string). Swift call sites already use `appString()` /
`Text(_:)` literals; these keys need EN (source, already correct in code) + VI added on merge.

## New keys (append-only)

| Key (source, as extracted) | EN | VI | Context |
| --- | --- | --- | --- |
| `1 line hidden` | 1 line hidden | 1 dòng đã ẩn | `MaskedMultilineFieldEditor` masked-summary hint — protected multiline field with exactly one line of hidden content |
| `%lld lines hidden` | %lld lines hidden | %lld dòng đã ẩn | `MaskedMultilineFieldEditor` masked-summary hint — protected multiline field with N (>1) lines of hidden content; count only, never character length |
| `Reveal to edit` | Reveal to edit | Hiện để chỉnh sửa | `MaskedMultilineFieldEditor` reveal button's accessibility label (icon-only affordance, ≥44pt hit target) |

No other new user-facing strings. `DateFieldEditor`'s fallback `TextField` reuses the existing
`Enter value` placeholder key (already in the catalog via `EditorFieldRow.valuePlaceholder`'s
`default:` case) — not a new string. The `DatePicker` itself has no visible label (`labelsHidden()`,
row's own "Label" TextField above it already names the field, matching every other `kindEditor`
case in this file).

## New keys — Settings deferred gaps (Notifications surface + Approval Mode toggle)

Two deferred Settings gaps: a Notifications settings screen (system permission status +
rotation-reminders toggle) and a user-facing Approval Mode toggle (previously DEBUG-only).
`Text(_:)` literals auto-extract on build; keys below need VI added on merge.

| Key (source, as extracted) | EN | VI | Context |
| --- | --- | --- | --- |
| `Notification permission` | Notification permission | Quyền thông báo | `NotificationsSettingsView` row label for the system authorization status |
| `Allowed` | Allowed | Đã cho phép | Notification permission status value — authorized/provisional/ephemeral |
| `Not allowed` | Not allowed | Không được phép | Notification permission status value — denied |
| `Not requested yet` | Not requested yet | Chưa được yêu cầu | Notification permission status value — not determined |
| `Notifications are turned off for Loox in iOS Settings. Turn them back on to receive rotation reminders.` | Notifications are turned off for Loox in iOS Settings. Turn them back on to receive rotation reminders. | Thông báo cho Loox đang tắt trong Cài đặt iOS. Bật lại để nhận nhắc nhở đổi mật khẩu định kỳ. | Warning banner body shown only when permission is denied |
| `Open Settings` | Open Settings | Mở Cài đặt | Banner action button — deep-links to `UIApplication.openSettingsURLString` |
| `Controlled by iOS. Loox only asks once, the first time you turn on a reminder below.` | Controlled by iOS. Loox only asks once, the first time you turn on a reminder below. | Do iOS quản lý. Loox chỉ hỏi một lần, vào lúc bạn bật nhắc nhở đầu tiên bên dưới. | System-permission section footer |
| `Notifications` | Notifications | Thông báo | Settings section header + row label + `NotificationsSettingsView` navigation title (all three share this key already used elsewhere; verify no source-string collision on merge) |
| `Rotation reminders` | Rotation reminders | Nhắc nhở đổi mật khẩu | Toggle label gating `RotationNotificationService` scheduling (new `SettingsStore.rotationRemindersEnabled`, default ON) |
| `Get a local notification on the day a password is due to rotate. The notification shows only the item name, never a password or username.` | Get a local notification on the day a password is due to rotate. The notification shows only the item name, never a password or username. | Nhận thông báo cục bộ vào ngày cần đổi mật khẩu. Thông báo chỉ hiện tên mục, không bao giờ hiện mật khẩu hay tên đăng nhập. | Rotation-reminders toggle footer |
| `Approval Mode` | Approval Mode | Chế độ phê duyệt | New Sharing-section toggle for `SettingsStore.approvalModeEnabled` (ADR-2: independent of iCloud Sync) |
| `Sharing` | Sharing | Chia sẻ | New Settings section header hosting the Approval Mode toggle |
| `Share a login with someone and approve each request before they can use it, over iCloud. Independent of iCloud Sync above.` | Share a login with someone and approve each request before they can use it, over iCloud. Independent of iCloud Sync above. | Chia sẻ một mục đăng nhập và phê duyệt từng yêu cầu trước khi người đó dùng được, qua iCloud. Độc lập với Đồng bộ iCloud ở trên. | Sharing section footer |
| `Turn off Approval Mode?` | Turn off Approval Mode? | Tắt Chế độ phê duyệt? | Confirmation dialog title shown when toggling off (existing shares are not torn down) |
| `Turn Off` | Turn Off | Tắt | Confirmation dialog destructive button |
| `Logins you already shared stay shared. New approval requests and invites pause until you turn this back on.` | Logins you already shared stay shared. New approval requests and invites pause until you turn this back on. | Những mục đã chia sẻ vẫn giữ nguyên trạng thái chia sẻ. Yêu cầu phê duyệt và lời mời mới sẽ tạm dừng cho đến khi bạn bật lại. | Confirmation dialog message — honest about what turning off does and does not do |

Notes: `Icons.notification` / `Icons.refresh` / `Icons.share` reused (no new icon assets).
`NotificationsSettingsView` new file under `Features/Settings/`; entry point added to
`SettingsScreen.swift`. Approval Mode toggle + confirmation added to `SettingsScreen.swift`
directly (no new file — single toggle + one dialog, matches "Erase Vault" pattern already there).

## New keys — AutoFill save/create Space picker (bug fix: new logins had no Space)

Fix: a login saved via the AutoFill extension (native "Save password" sheet or the manual
"+ Create new login" flow) previously always landed with no Space (`folderId` nil), so it had no
persona association. The app now mirrors the active persona's id/default-flag/primary Space/last
selected Home Space into the App Group (`SharedConfig` + `VaultRepository.mirrorActivePersonaContext`)
and the extension defaults the new item into that Space, with a compact picker to change it before
saving (`CreateLoginView.swift`, `SavePasswordView.swift` — new `VaultSpaceReader` in VaultifyCore).

| Key (source, as extracted) | EN | VI | Context |
| --- | --- | --- | --- |
| `Save to` | Save to | Lưu vào | `CreateLoginView` / `SavePasswordView` Space-picker section header + row label. Deliberately NOT the word "Space" alone: that source string already collides with `PasswordGeneratorView`'s literal "Space" (the spacebar character), which carries an unrelated VI translation ("Khoảng trắng") |

No other new keys: the picker's options reuse the existing `Unfiled` key (already translated) plus
each Space's own user-authored name (not localized, same as everywhere else Space names render).

## New keys — Đợt 11: Private Email recognition in Item Detail + Editor

Recognition convention for any username/email field whose value is a private-email alias (badge +
mono + forwards-to line + tap-copies-alias-only), shipped in `DetailFieldRow.swift` (new
`PrivateEmailRecognition.swift` component) and mirrored in the Editor's `LoginEditorSections.swift`
(attach/detach + swap-to-real-email + swap-back-to-alias). `Text(_:)` literals auto-extract on
build; keys below need VI added on merge. `Close`/`Active` already exist in the catalog — reused,
not re-listed.

| Key (source, as extracted) | EN | VI | Context |
| --- | --- | --- | --- |
| `PRIVATE` | PRIVATE | RIÊNG TƯ | `PrivateEmailBadge` pill next to a recognized alias field's label (Item Detail + Editor attached-alias row) |
| `FORWARDS TO` | FORWARDS TO | CHUYỂN TIẾP ĐẾN | `PrivateEmailForwardsToLine` caption-caps label preceding the real destination email |
| `Pending verification` | Pending verification | Đang chờ xác minh | Forwards-to line status when the alias is `.active` but its destination inbox hasn't completed backend verification yet |
| `Paused` | Paused | Đã tạm dừng | Forwards-to line status for a `.paused`/`.disabled` alias — forwarding convention's dot-color noun (distinct from the existing verb `Pause` swipe action in Private Email management) |
| `Not yet active` | Not yet active | Chưa kích hoạt | Forwards-to line status for a `.draft`/`.reserved` alias (reserved locally, not yet live on the relay) |
| `Detach private email` | Detach private email | Gỡ email riêng tư | Accessibility label for the small × button on the Editor's attached-alias row (clears the field's value; the alias itself is untouched) |
| `Use real email instead` | Use real email instead | Dùng email thật thay thế | Editor chip below the Credentials card — one-tap swap from the attached alias to its real forwarding destination |
| `Manage alias…` | Manage alias… | Quản lý email riêng tư… | Editor chip below the Credentials card — opens `AliasDetailScreen` (pause/delete live there, not in the editor) |
| `Switching to your real email keeps the alias alive. Pause or delete it in Private Email.` | Switching to your real email keeps the alias alive. Pause or delete it in Private Email. | Chuyển sang email thật không xoá email riêng tư — tạm dừng hoặc xoá nó trong mục Email riêng tư. | Info note under the Editor's private-email actions row |

Notes: `Icons.close` / `Icons.person` / `Icons.info` / `Icons.mail` reused (no new icon assets). The
top "Suggested email" scroller (`ItemEditorScreen.swift`) was redesigned to remove its card
wrapper (full-bleed horizontal scroll, matching Home's TOTP-scroller bleed pattern) and its chips
now truncate long alias text in the middle — no new copy from that change, existing `Suggested
email` / `Create private email` / `Unique for {host}` keys unchanged. The create-chip is now
gated by the same `CapabilityStore.availability(.privateEmail, operation: .create)` check
`PersonaAliasesScreen` uses (hides instead of offering a tap that's guaranteed to fail), and
`createPrivateEmail()`'s success path no longer fires `Haptics.success()` — matched to
`PersonaAliasesScreen`'s own alias-creation flow, which stays silent on success and only surfaces
`Haptics.error()` on failure.

## New keys — Payment card overhaul (brand detection, formatting, PIN field, camera scan)

Card template gains a PIN field; Card Number/Expiry/Security Code get dedicated editors
(`CardNumberFieldEditor.swift`, `ExpiryFieldEditor.swift`, `CardCodeFieldEditor.swift` — brand
grouping, Luhn hint, numeric keypads) plus an optional camera scan (`CardScannerSheet.swift`,
VisionKit `DataScannerViewController`, hidden where unsupported e.g. Simulator). `Text(_:)`
literals and `TextField` title-string literals auto-extract on build; keys below need VI added on
merge. Brand badge text (`VISA`, `MASTERCARD`, …) is rendered `Text(_ string: String)` verbatim —
proper nouns, deliberately NOT run through the catalog, no VI needed. `Cancel` already exists —
reused for the scanner sheet's toolbar, not re-listed.

| Key (source, as extracted) | EN | VI | Context |
| --- | --- | --- | --- |
| `Enter card number` | Enter card number | Nhập số thẻ | `CardNumberFieldEditor` placeholder |
| `Check the card number` | Check the card number | Kiểm tra lại số thẻ | Subtle hint shown under the Card Number field once its digit count is complete but fails the Luhn checksum — never blocks saving |
| `MM/YY` | MM/YY | MM/YY | `ExpiryFieldEditor` placeholder for a recognized (or empty/new) expiry value — a universal payment-format convention, identical in both languages (Vietnamese banks print the same "MM/YY" shape) |
| `Scan Card` | Scan Card | Quét thẻ | Editor's "Scan Card" row label (top of the Card template's Fields section, hidden where camera scanning is unsupported) and the scanner sheet's navigation title (same key, reused) |
| `Point the camera at your card` | Point the camera at your card | Hướng camera vào thẻ của bạn | `CardScannerSheet` overlay instruction over the live camera preview |

Notes: no new icon assets for Polaris — the "Scan Card" row and the scanner sheet's affordance use
SF Symbol `creditcard.viewfinder` (user-granted 260711 exception scoped to the payment-card
context only; see `docs/design-dna-standard.md` acceptance-matrix note). `Icons.close` unaffected.
Haptics: capture fires `Haptics.tap()` once per successful scan (stable-frame match), matching the
"selection/minor action" vocabulary row — no separate validation haptic for the Luhn hint (visual
only, per the haptics vocabulary's "none" row for non-destructive hints).

## New keys — Home persona-empty state (Issue 1: no-Space / persona-empty scaffolding fix)

`HomeScreen.personaEmptyState`: a calm empty state shown when the vault overall has data but the
ACTIVE persona has nothing to show (no owned Space yet, or an owned Space with zero items) —
previously this fell through to `scrollContent` and rendered the "All Spaces (0)" scaffolding with
an empty card (see investigation report). `Text(_:)` literals auto-extract on build; keys below
need VI added on merge. `Add Item` reuses the existing key (already in the catalog).

| Key (source, as extracted) | EN | VI | Context |
| --- | --- | --- | --- |
| `Nothing here yet` | Nothing here yet | Chưa có gì ở đây | `personaEmptyState` title — active persona has no reachable items |
| `This identity doesn’t have a Space yet. Create one to start adding items.` | This identity doesn’t have a Space yet. Create one to start adding items. | Danh tính này chưa có Không gian nào. Tạo một cái để bắt đầu thêm mục. | Subtitle shown when `activePersonaSpaces` is empty (steers to creating a Space first, never "Add Item" here — a new item would otherwise fall back to Unfiled, which only the default identity owns) |
| `Add your first item to this identity’s vault.` | Add your first item to this identity’s vault. | Thêm mục đầu tiên vào kho của danh tính này. | Subtitle shown when the persona already owns a Space but it has zero items |
| `Create a Space` | Create a Space | Tạo Không gian | Primary CTA when the active persona owns no Space — opens `FolderEditorSheet(folder: nil)` (reused, unmodified) |

Notes: no new icon assets — reuses `Icons.folder` / `Icons.lockFill` / `Icons.addCircle` / `Icons.add`
(the same icons and Space-creation flow already used elsewhere on Home). No new haptics: both CTAs
are plain buttons that open a sheet/menu, matching the existing `emptyVaultState`'s own "Add Item"
button (no haptic — the sheet/menu presentation itself is the feedback).
