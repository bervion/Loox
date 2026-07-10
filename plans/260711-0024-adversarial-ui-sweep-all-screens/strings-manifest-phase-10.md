# Strings Manifest — Phase 10 (Personas + Profile)

Only NEW or CHANGED user-facing strings from this phase's fixes. Orchestrator merges these
into `Vaultify/Localizable.xcstrings` (append-only). Existing strings this phase reused
unchanged (e.g. `"None"`) are NOT listed — no catalog action needed for those.

| Key (EN, source of truth) | EN | VI | Context |
|---|---|---|---|
| `Delete this identity permanently?` | Delete this identity permanently? | Xóa vĩnh viễn danh tính này? | `PersonaSwitcherScreen` — new confirmationDialog title before `deletePersona` (was executed with zero confirmation on swipe; now gated behind a confirm step matching the alias/persona-delete convention elsewhere in this cluster). |
| `This also permanently deletes its private email addresses. Its logins and other items move to your default identity.` | This also permanently deletes its private email addresses. Its logins and other items move to your default identity. | Thao tác này cũng xóa vĩnh viễn các địa chỉ email riêng tư của danh tính này. Thông tin đăng nhập và các mục khác sẽ chuyển sang danh tính mặc định của bạn. | `PersonaSwitcherScreen` — same dialog's message; states honestly what `deletePersona` actually does (cascade-tombstones aliases, reassigns Spaces/items to the default persona — verified against `VaultRepository+PersonaManagement.swift:102-128`). |
| `Delete this inbox?` | Delete this inbox? | Xóa hộp thư này? | `ForwardingInboxScreen` — new confirmationDialog title before `deleteInbox` (was executed with zero confirmation from both contextMenu and swipeActions). |
| `You can add it again later if you need to.` | You can add it again later if you need to. | Bạn có thể thêm lại sau nếu cần. | `ForwardingInboxScreen` — same dialog's message. |
| `Change photo` | Change photo | Đổi ảnh | `ProfileAvatarView` — new `.accessibilityLabel` on the PhotosPicker camera badge (previously unlabeled; VoiceOver had nothing to announce for the tap target). |
