# Phase 01 — Data-safety criticals (v2)

Gate: Phase 00 mục 2 (backup contract) phải chốt trước mục 2 dưới đây.

## 1. Extra Password off — transaction 2 bước (HIGH, confirmed)
- Hiện trạng: `Level2SettingsView.swift:320` duyệt `env.repository.items` (live cache), rồi `VaultSession+Level2.swift:80 removeLevel2Wrap()` xóa L2SK vĩnh viễn → sealed fields trong Archive/Trash chết.
- Thiết kế fix (KHÔNG "quét rồi update từng item"):
  1. **Preflight (read-only):** decrypt toàn bộ records qua `store.allRecords()` (live + archived + trashed), unseal thử mọi field `guard2 && scheme == .level2` vào bộ nhớ. Bất kỳ field nào fail (L2SK khác/corrupt) → abort, không ghi gì, hiện danh sách item chặn.
  2. **Persist atomic:** chỉ khi preflight 100% pass mới ghi lại toàn bộ items đã unseal (1 save transaction của ModelContext; nếu SwiftData không cho 1 transaction phủ hết thì ghi theo batch + cờ `level2DisableInProgress` trong keybundle để resume sau crash).
  3. **Verify rồi mới xóa wrap:** quét lại allRecords xác nhận 0 field còn `scheme == .level2` → lúc đó mới `removeLevel2Wrap()`.
- Test: unit — item archive + trash có field guard2 → off → mở lại plaintext; fail-injection giữa persist → relaunch resume, không mất field, L2SK còn nguyên; field L2SK lạ → abort sạch.

## 2. Backup theo contract Phase 00 (HIGH, confirmed)
- Hiện trạng: `ExportView.swift:105` chỉ `env.repository.items` (live); `VaultBackup.swift:6 PortableItem` chỉ title/category/fields/tags/folderName — thiếu favorite/pinned/icon/rotation/timestamps/defaultIdentity; không mang persona/avatar/alias/inbox.
- Contract A (portable export): thêm archived + cờ `archived`; UI export ghi rõ phạm vi không gồm gì.
- Contract B (full backup): payload `version: 2` mang đủ metadata trên + persona/avatar/alias/inbox; import: v1 vẫn decode (decodeIfPresent, default cũ), v2 restore đủ; passkeys giữ nguyên cơ chế hiện có.
- Test: roundtrip theo contract đã chọn; legacy `.vaultify` v1 vẫn mở; CSV không đổi contract.

## 3. deleteFolder dangling folderId (MED, confirmed)
- `VaultRepository+Folders.swift`: reassign-on-delete quét cả trashed + archived members → Unfiled.
- Test: xóa folder có member trashed/archived → restore/unarchive hiện ở Unfiled, đủ trên mọi surface persona-scoped.

Rollback: mỗi mục 1 commit, revert độc lập.
Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
