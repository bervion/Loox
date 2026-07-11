# Phase 06 — HIBP nâng cấp: prefix-group, incremental cache, cancellable

**Priority:** P1 · **Status:** ☐ · **Ước lượng:** 1 ngày · **Phụ thuộc:** 01, 05

## Context (verified)

`HIBPService.pwnedCount` hiện tại: đúng k-anonymity + `Add-Padding` header, nhưng
`WatchtowerScreen.runHIBP` chạy per-item TUẦN TỰ, cache in-memory theo plaintext password chỉ
trong 1 lần chạy, không cancel, không retry, fail im lặng → 0. Proposal §5A + §12 Option B.

## Thiết kế

`Vaultify/Services/Watchtower/PwnedPasswordChecker.swift` (thay orchestration, giữ
`HIBPService` làm transport):

1. Hash SHA-1 local toàn bộ → **dedupe unique passwords** → group theo 5-char prefix.
2. **Randomize thứ tự request** prefix (privacy hardening proposal).
3. `withThrowingTaskGroup` bounded concurrency **4**; mỗi prefix 1 request; so suffix local.
4. Retry nhẹ (1 lần, backoff 2s) cho lỗi transient; timeout giữ 15s.
5. **Cancellable**: check `Task.isCancelled` giữa các batch; cancel → trả partial, coordinator
   đánh dấu `onlineChecksCompleted = false`, KHÔNG ghi cache entry dở.
6. **Incremental cache** (`AuditLocalCache` phase 05): trước khi request, tra HMAC key;
   entry `checkedAt` < 30 ngày → dùng cache, skip network. Password đổi khi save item →
   entry cũ tự miss (HMAC khác). Full audit chỉ refresh entry stale.
7. Không log prefix, không lưu raw response, không gửi kèm domain (đã đúng — giữ).

Findings: `exposure.leaked` (high), nâng critical khi leaked+reused hoặc leaked trên critical
category (dùng category weight phase 04). Detail: "Seen N times in known leaks" — wording
"độ phổ biến trong dataset", không phải xác suất.

Trigger cadence (proposal §13):
- Khi user save/change password 1 item (đã unlock, foreground): check 1 prefix nền, ghi cache.
- Full audit: refresh stale.
- KHÔNG background decrypt vault.

Settings giữ toggle `hibpEnabled` hiện có; copy giải thích k-anonymity giữ + link "How it works"
(sheet nhỏ, phase 07).

## Files

- **Tạo:** `PwnedPasswordChecker.swift`; **Sửa:** `Rules/PwnedPasswordRule.swift` (dùng checker),
  `HIBPService.swift` (expose range fetch `func range(prefix:) async throws -> [Suffix: Int]`
  thay vì per-password), `ItemEditor` save hook (on-change check), xoá `runHIBP` khỏi screen
  (chuyển vào coordinator).

## Todo

- [ ] Refactor HIBPService → range API + errors thay vì nuốt lỗi
- [ ] Checker: dedupe/group/randomize/bounded 4/retry/cancel/cache
- [ ] On-save incremental check hook
- [ ] Tests: mock URLProtocol — group đúng (120 unique → ≤118 request), cache hit không gọi
  network, cancel giữa chừng không ghi cache, offline → findings rỗng + cờ partial
- [ ] `make check`

## Success criteria

Vault 184 items lần 2 chạy gần như 0 request (cache); cancel sạch; offline vẫn ra local result
với nhãn "Online checks unavailable".
