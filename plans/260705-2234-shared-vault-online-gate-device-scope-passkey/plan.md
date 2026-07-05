# Shared Vault Hardening V2.1 (reviewed) — Online Gate + Device Scope + Passkey/TOTP v2

Status: **V2.1 — đã patch theo security review 260705 tối, chờ user gật P00 để bắt đầu.**
Supersedes: `plans/260705-2217-approval-share-passkey/`.
Review gốc: user feedback 260705 22:53 (7 blocker P0/P1 — đã tiếp thu toàn bộ).

## Quyết định của user (KHÔNG tự đảo)

1. Passkey share mặc định **ask-each-time** như TOTP (không giao key).
2. Online gate **chặn tuyệt đối** — nhưng theo review: "có mạng" chỉ là PRECONDITION,
   quyền xem đến từ **authoritative grant verify** (INV-01/02). Bật mạng lại → `verifying`
   → chỉ render sau verify thành công (không còn "xem được ngay").
3. Single-device = **seal per-device** (crypto cứng); legacy synced key CẤM trong v2
   single-device (INV-04).
4. Review plan xong mới code; review 260705 yêu cầu thêm P00 — đã thêm.
5. TOTP + Passkey thêm mode **giao key** (`shared`) kèm modal cảnh báo. Semantics revoke
   trung thực (INV-08): revoke chỉ chặn Vaultify-access + updates; seed/key ĐÃ GIAO không
   thu hồi được bằng mật mã — muốn thu hồi thật phải rotate ở RP/origin.
6. (Review 260705) **Mất máy single-device** = flow "Replace Device" owner duyệt bằng
   Face ID: new device publish key → owner approve → epoch++ → remove old + add new
   deviceKeyID → re-seal → old request authority chết. Không auto-transfer theo iCloud.
7. (Review 260705) **QuickType**: đăng ký identity chỉ khi grant known + device allowed +
   capability ≠ none + không tombstoned. askEachTime → chọn là vào approval ceremony;
   shared → như passkey thường; revoked → gỡ ngay sau verified refresh; single-device
   unapproved → KHÔNG đăng ký (không dụ user bấm rồi báo lỗi).

## Verified facts

- Passkey private key của Loox là **software exportable**: `PasskeySecret.privateKeyRaw: Data`
  (`VaultifyCore/Passkey/PasskeyModels.swift`), ký qua `WebAuthn.assertion(privateKeyRaw:)`
  — không SE binding → shared-mode khả thi, không cần re-registration migration (P2-9 đóng).

## Phase order (đổi theo review — P04 trước khi P02 được coi là xong)

| # | Phase | Effort | Depends |
|---|-------|--------|---------|
| 00 | Security invariants (INV-01..12) + protocol/schema freeze | 0.5 | — |
| 01 | App gate state machine (không render trước verify) | 0.5–1 | P00 |
| 03a | Device identity migration (per-device HPKE, private key hết sync) | 1 | P00 |
| 03b | Grant v2 (DeviceKeyBinding IDs+hash, canonical bump MỘT lần cùng P05 schema) + per-device envelopes | 1 | P03a |
| 04 | Extension CloudKit enablement + entitlement verification preflight | 0.5–1 | P00 |
| 02 | Extension authoritative gate COMPLETE (P02a UX sớm được, release cần P02b) | 0.5 | P01, P04 |
| 05 | Passkey/TOTP capability v2 (frozen transcripts từ P00) | 2–3 | P03b, P04 |
| 06 | Adversarial test matrix + QA 2 máy + docs | 1 | tất cả |

**Effort thực tế: 6.5–9 buổi** (revised theo review; 5 buổi cũ là lạc quan).
**Release gate production**: P02a + P04 + P02b đều xong — reachability-only KHÔNG được
ship như bản hoàn chỉnh.

## Honesty note (UI copy phải theo)

Online gate + device scope chống NÉ THU HỒI cho kẻ lười; không chống screenshot/copy trước
đó, không thu hồi được secret đã giao (INV-08). Modal cảnh báo mode `shared` nói thẳng.

## Reversal có ý thức

Mode `shared` cho TOTP khôi phục thứ QA-round-4 từng bỏ (TOTP reveal) — user chốt lại
260705 với điều kiện cảnh báo. Quick Link (Loox Link) KHÔNG đổi: TOTP seed vẫn cấm trong
envelope theo spec server.

## Unresolved questions

- P00: chốt counter strategy passkey (A/B/C) — cần quyết trước khi freeze schemas.
- Tier 1 metadata cụ thể gồm gì cho từng loại item (đề xuất trong P00 deliverable 5,
  user duyệt cùng lúc gật P00).
