# Release Hardening — Implementation Report

- Date: 2026-07-28 · Branch: `feat/release-hardening-260728` (13 commits, base `main` @ 3c5ef6a)
- Nguồn: `deep-audit-260728-0945-release-readiness-report.md` (v2) + Phase 00 decisions của owner
- Verify: compile iOS Simulator PASS · compile macOS slice PASS · **935/935 unit tests PASS** · 4/4 Safari node harnesses PASS · self-test UI iPhone 11 + iPad Air

## Phase 00 — decisions đã khóa

| Mục | Quyết định |
|---|---|
| Backup contract | **A — portable export** (thêm archived, không xây full-backup v2) |
| CloudKit Production | Owner xác nhận **đã deploy all** → gate mở |
| Quick View | Hoàn thành production (wire payload + operator mirror) |
| iPad/Mac AutoFill | **Triển đầy đủ** |
| Support contact | `support@looxpassword.com` là thật → gỡ ghi chú "placeholder" |

## Đã sửa (13 commits)

### Data safety
1. **Tắt Extra Password thành transaction 3 bước** — preflight read-only unseal toàn bộ live+archived+trashed → persist → verify 0 ciphertext → mới xóa L2SK. Abort giữ nguyên key; retry sau crash bỏ qua field đã unseal. `Level2Disable` tách pure + 4 test (gồm foreign-key abort, idempotent retry).
2. **Export gồm archived items** + cờ `archived` restore đúng chỗ; footer UI nêu rõ phạm vi (không gồm Recently Deleted); backup cũ vẫn decode.
3. **deleteFolder reassign cả trashed/archived** → hết dangling folderId.

### Security & integrity
4. **`HostMatch` chung cho 3 surface** (OS AutoFill, QuickType, Safari popup, shared credentials): exact hoặc parent/child theo label boundary, IP literal so khớp tuyệt đối. **Test cũ codify `evilgoogle.com` PASS đã lật ngược**; thêm vector punycode, trailing dot, sibling subdomain, public-suffix (documented limitation).
5. **CloudKit push chunk 200/op, non-atomic** — 1 record lỗi không giết plane; hết vòng lặp retry-batch vô hạn.
6. **Snooze hết hạn resurface** — `effectiveStatus()` (dead code) giờ là filter duy nhất của cả 3 surface qua `hiddenFingerprints`.
7. **Audit engine loại field L2-sealed** khỏi scoring (username/password), giữ presence check cho 2FA.
8. **Recovery key map Crockford confusables** (I/L→1, O→0) thay vì xóa.
9. **Safari: state `unlockUnavailable` riêng** khi không có biometric key (invalidated/unavailable) → popup chỉ đường mở app unlock; contract `getFillPayload` duy nhất giữ nguyên.

### Bug owner báo + self-test
10. **Watchtower CTA sống lại trên iPhone** — 2 NavigationLink trong UIKit shell push → callback `openCategory` (giữ paywall gate). Verify tay: "Xem báo cáo đầy đủ" mở đúng màn.
11. **Share permission UX** — `check()` không còn tự bắn OS prompt; thêm pre-permission explainer (component app-layer dùng chung), grant → tự advance, denied → nút mở Settings.
12. **Theme mitigation** — re-apply `forceInterfaceStyle` khi window mới visible + khi scenePhase active.
13. **Identity email** — chặn Protect L2 cho email của identity; 4 reader thô (`TotpCardView`, `SharedItemsProjection`, `CredentialExchangeMapping`, `VaultBackup`) chuyển sang `readableUsernameField`.
14. NameStep `.autocorrectionDisabled()` (Kiyo→Koyo); "Add Website" auto-focus row mới.
15. Sharing errors: `SharingErrorMessage` map CKError → copy hành động được, localize EN/VI/JA (10 chuỗi mới).

### Platform & i18n
16. **AutoFill extension mở iPad** (`destinations` + `TARGETED_DEVICE_FAMILY 1,2`) — macOS slice compile lại vẫn xanh.
17. **Quick View wire payload có `title` + `category`** (additive, nằm trong sealed plaintext nên hưởng AES-GCM integrity); `publishSecondaryMirror` có call site trong operator screen.
18. **JA vào pipeline**: `metadata/apple/ja/`, generator + release.sh + Makefile, storekit ja localizations, `InfoPlist.xcstrings` (Face ID/camera EN/VI/JA) wire cả 3 target.
19. **JA classifier**: field-classifier + signup-detector nhận label tiếng Nhật; phát hiện & sửa bug NFD tách dakuten (ド→ト+゛) khiến `カード番号` không match — thêm `.normalize("NFC")`. 16 test JA mới.
20. **JA/VI polish**: 「ID」→「プロフィール」 (25 chuỗi app + 3 Safari), 2要素認証 thống nhất, さん, badge Stale→要更新; VI "Mật khẩu cấp 2", bỏ "nhé", "đầu cuối"; "computer approvals"→"browser approvals"; plural EN "Based on %lld item(s)".

## Self-test round 2 (đã chạy tay)

- iPhone 11: reinstall giữ nguyên vault test; slide-to-unlock (deliberate lock) OK; audit chạy lại 965/1000; **"Xem báo cáo đầy đủ" mở đúng** (trước đây chết); export footer scope hiển thị đúng VI.
- iPad Air: **vault gốc của owner backup trước install và còn nguyên** (7 file), app launch vào màn unlock đúng — không mở khóa vault thật.

## Còn lại (chưa làm, có chủ đích)

1. **Track Tutorial + onboarding polish** (phase-03/04) — theo review 260728-1040 là track riêng sau feature flag, không chặn RC. Chưa bắt đầu.
2. **Signed RC + QA máy thật** (phase-07 mục 4): artifact Release ký thật, Face ID, AutoFill trong app thứ ba, sharing 2 thiết bị, case mạng — cần owner chạy trên device.
3. **Docs sync** (CLAUDE.md/README/codebase-summary còn ghi "iPhone-only / EN+VI") — chưa đụng, để cùng đợt phase-06 mục 6.
4. Medium/low còn lại trong appendix chưa xử lý hết (65 finding, đã sửa các nhóm nằm trong phase 01/02/05/06).

## Unresolved questions

1. Quick View: exposure trên manifest đã set `ga` + assertion enforcement REQUIRED ở backend chưa? App-side resolver đã đúng, phần còn lại là ops.
2. Có ship AutoFill cho macOS slice (extension riêng) trong release này không, hay iPad là đủ?
3. Docs sync + Tutorial track: làm ngay sau đây hay để sau khi RC lên TestFlight?
