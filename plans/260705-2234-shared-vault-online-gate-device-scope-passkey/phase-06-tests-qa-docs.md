# Phase 06 — Adversarial Tests + QA 2 thiết bị + docs (V2.1)

Priority: bắt buộc trước merge · Effort: 1 buổi · Depends: P00–P05

## Unit/vector — adversarial matrix (bổ sung theo review)

Grant/canonical (INV-12):
- reordered device IDs → reject (hoặc normalize đúng spec) · duplicate device ID → reject
- unknown enum value / trailing bytes / malformed key length → reject
- v2 payload signed as v1 → fail · v1 signature với injected v2 fields → fail
- v1 grants cũ verify OK (deviceScope=multi)

Request replay (INV-06/09):
- same requestID twice → reject · same nonce twice → reject
- response của request khác → reject · epoch N response sau revoke epoch N+1 → reject

Passkey:
- rpId mismatch / credentialId mismatch → reject
- clientDataHash != 32 bytes → reject · swapped clientDataHash giữa 2 requests → reject
- expired request → reject · owner approve SAU khi recipient huỷ ceremony → response
  không dùng được (requestID bound, extension đã bỏ)

Device scope (INV-04/05):
- legacy synced key decrypt v2 single → MUST FAIL (test bắt buộc, thiết lập: legacy key
  trên device A+B, grant pin A)
- device pubkey replacement dưới cùng label → reject (hash binding)
- cùng deviceKeyID nhưng pubkey khác → reject · removed device dùng ciphertext cũ →
  không có blob mới, epoch guard chặn request

Gate race (INV-01/06/11):
- T0 authorized → background → owner revoke → foreground → tap copy NGAY → fail
- verify bắt đầu → owner revoke → stale verify response về → bị loại (epoch guard)

State machine: offline / verifying / authorized / unavailable / revoked transitions
(unit thuần logic — SharedAccessAuthorizer).

## QA 2 thiết bị (A owner + B recipient)
1. Gate: B airplane → không lộ values app+extension; bật mạng → verifying → hiện sau
   verify (KHÔNG hiện ngay). B tắt mạng trước khi A revoke → mở lại cần mạng → thấy revoked.
2. Extension: A revoke → B extension chọn fill (cache còn) → verify chặn, không điền.
3. Device scope: single → B device 2 = Tier 0; multi → device mới xin → A duyệt → OK.
   Replace Device: atomic swap, máy cũ chết quyền.
4. Passkey askEachTime full round-trip + đo extension lifetime; owner offline → timeout.
5. Shared mode: modal cảnh báo đúng chỗ; revoke gỡ identity (copy KHÔNG claim thu hồi
   secret đã giao).
6. Regression: owned items + Quick Link không bị gate ảnh hưởng.

## Docs
- `docs/codebase-summary.md` (Approval Mode section) + `security-invariants.md` link.
- Release notes EN+VI: online-required là feature; shared-mode revoke semantics nói thật.
