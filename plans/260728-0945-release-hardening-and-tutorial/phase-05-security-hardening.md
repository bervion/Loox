# Phase 05 — Security & integrity hardening (v2)

## 1. Domain matcher contract chung cho 3 surface (HIGH, confirmed)
- Hiện trạng: OS AutoFill `matchesAutoFill` có `other.contains(host)` (`VaultReader.swift:143`); test `WebExtensionHostMatchTests.swift:30` đang CODIFY loosening này ("fine in the QuickType context") — thay hành vi lẫn test.
- Contract (theo semantics Safari popup hiện có, KHÔNG phải eTLD+1): match khi `host == other || host.hasSuffix("." + other) || other.hasSuffix("." + host)` — exact hoặc parent/child đúng label boundary. Bỏ hẳn substring clause.
- Một matcher duy nhất trong VaultifyCore dùng cho: OS AutoFill list, QuickType promote, Safari popup (parity test 3 surface cùng bộ vector).
- Bộ test bổ sung: IDN/punycode (`xn--`), trailing dot (`google.com.`), IP literal, sibling subdomain (`a.example.com` vs `b.example.com` — child-of-parent vẫn pass, sibling exact-host không), public suffix (`com`, `co.uk` — lưu ý: label-boundary thuần sẽ match `evil.co.uk` với item lưu `co.uk`; quyết định có chặn public-suffix-only host khi lưu/khi match, ghi thành test).
- Regression: passkey matcher (đang conservative) giữ nguyên.

## 2. CloudKit push chunking (HIGH, confirmed)
- `CloudSyncService.swift:120` + `SyncPushService.swift`: chunk mọi plane (limit hằng số 1 nơi, mặc định thận trọng ~200–350; xác minh limit thật bằng integration test/tài liệu trước khi chốt số); per-chunk error isolation — 1 record lỗi không chặn phần còn lại; phần fail giữ dirty để retry riêng.
- Test: fake container 900 dirty → nhiều ops, tất cả synced; 1 record oversized chỉ record đó fail; không còn retry-nguyên-batch vô hạn.

## 3. Watchtower snooze + L2 scoring (HIGH, confirmed)
- `effectiveStatus()` thành đường filter duy nhất cho 3 surface (expiry + rule-version resurfacing). Test: snooze quá hạn resurface; dismissed ẩn; version bump resurface.
- `VaultAuditSnapshot.swift:48`: lọc `isExtraProtected` cho usernames/password/totp (đồng bộ với `PasswordAudit`); item chỉ còn field sealed → "not assessable", assert số item "based on" đổi tương ứng.

## 4. Extension session (re-scoped sau review)
- Code ĐÃ có trần cứng `maxTTL = 15*60` (`ExtensionSessionStore.swift:27`). Việc còn lại: design-review việc session sống qua app termination trong trần 15' (có chủ ý không — document hoặc fix); nếu thêm absolute expiry thì **không dài hơn trần 15' hiện tại**. Không có thay đổi 8h nào (v1 sai).

## 5. Safari extension fallback không biometric (MED, confirmed)
- `SafariMessageRouter.swift` + web UI: khi biometric off/invalidated → hướng dẫn mở app Loox unlock (hand-off App Group session), KHÔNG thêm command mới trả secrets, giữ contract `getFillPayload` duy nhất + content-script không summon Face ID (test-enforced giữ nguyên).

## 6. Recovery-key normalizer (LOW)
- Map Crockford confusables (I/L→1, O→0) thay vì xóa; round-trip test với key format trên PDF kit.

Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
