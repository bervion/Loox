# Shared Vault Hardening V2 — Online Gate + Device Scope + Passkey Ask-Each-Time

Status: **PLANNED — chờ user review, chưa triển khai** (user chọn "plan trước, review rồi làm").
Supersedes: `plans/260705-2217-approval-share-passkey/` (passkey giao-key bị loại — user chốt ask-each-time).

## Quyết định của user (260705, verbatim — KHÔNG tự đảo)

1. **Passkey share = ask-each-time như TOTP**: "không giao key, extension biết là có hỗ trợ
   passkey, khi mở lên thì ở extension có thể request đến owner... approve để login".
2. **Online gate = luôn bắt buộc, chặn tuyệt đối** (không grace): mất mạng → ẩn shared vault,
   hiện state "cần mạng mới xem được" — cả app lẫn extension (chống chiêu tắt mạng né thu hồi).
3. **Single-device = seal per-device (crypto cứng)**: owner chọn multi-device hay 1 device;
   single → sealed blobs chỉ device đó giải mã được.
4. Thực thi: review plan xong mới code.
5. **(Bổ sung cùng tối)** TOTP và Passkey đều có THÊM mode "giao key" (`shared`): recipient
   dùng không cần hỏi. Bắt buộc kèm cảnh báo cho owner khi chọn ("đối phương dùng mà không
   cần hỏi trước; giá trị đã giao không thu hồi được"). ⚠️ Reversal có ý thức: QA round 4
   từng BỎ option reveal TOTP — user khôi phục 260705 dưới dạng giao-key-có-cảnh-báo.
   (Quick Link/Loox Link KHÔNG đổi: TOTP seed vẫn cấm tuyệt đối trong envelope — spec server.)

## Honesty note (ghi vào UI copy khi làm)

Online gate + device scope là **enforcement chống né thu hồi**, không phải chống recipient
ác ý tuyệt đối: giá trị đã từng hiển thị thì có thể đã bị chụp màn hình/chép tay. Copy revoke
hiện tại đã nói thật điều này — giữ nguyên tinh thần.

## Phases

| # | Phase | Effort | Phụ thuộc |
|---|-------|--------|-----------|
| 01 | Online gate — app (reachability + live-grant verify, fail-closed UI) | 0.5 buổi | — |
| 02 | Online gate — extension (reachability; live verify đầy đủ chờ P04) | 0.5 buổi | P01 |
| 03 | Device scope — per-device HPKE seal + owner toggle + grant v2 | 1 buổi | P01 |
| 04 | Extension CloudKit enablement (entitlement + core service move) | 0.5 buổi | — |
| 05 | Passkey + TOTP capability v2: askEachTime (owner ký/cấp hộ) VÀ shared giao-key + cảnh báo | 2 buổi | P03, P04 |
| 06 | Tests + QA 2 thiết bị + docs | 0.5 buổi | tất cả |

Chi tiết từng phase: `phase-01..06-*.md`.

## Kiến trúc chạm vào

- `VaultifyCore/Sharing/*` (ApprovalModels — grant v2 CÓ CHỮ KÝ: thêm field = đổi canonical
  bytes → cần version + vector tests; ApprovalCrypto — seal per-device; ParticipantIdentity —
  per-device HPKE keypair, KHÔNG sync private key nữa).
- `Vaultify/Services/Sharing/*` (projection gate, recipient service move core xuống
  VaultifyCore cho extension dùng).
- `VaultifyAutoFill/*` (reachability gate, passkey identity đăng ký cho shared passkey,
  waiting-for-approval ceremony UI).
- `Project.swift` + portal: iCloud entitlement cho `com.bervion.vaultify.autofill`.
- Snapshot/cache 260705 giữ nguyên vai trò TỐC ĐỘ (hiện list ngay khi có mạng); tầng gate
  quyết định có RENDER values hay không — hai việc tách bạch.

## Rủi ro tổng

1. **Grant canonical/signature compat** (P03, P05): share cũ phải verify được sau update —
   grant v1 coi như `deviceScope=multi`, không có passkey capability. Vector tests bắt buộc.
2. **AutoFill extension lifetime** (P05): ceremony chờ owner approve có thể vượt kiên nhẫn
   user/iOS; cần UI chờ + timeout lịch sự + fallback deep-link mở app.
3. **Per-device seal nhân N ciphertext** (P03): owner re-seal khi recipient thêm device
   (multi mode) — cần đường "device mới xin cấp" (join request) hoặc chấp nhận re-share.
4. Extension + CloudKit: memory ceiling của appex khi thêm CK stack — đo thực tế ở P04.

## Unresolved questions

- P03: recipient single-device đổi máy (mất máy) → owner revoke + re-share, hay có flow
  "chuyển thiết bị" được owner approve? (đề xuất V1: revoke + re-share cho đơn giản)
- P05: passkey shared có nên hiện trong QuickType không, hay chỉ trong list extension?
  (đề xuất: có — ASPasskeyCredentialIdentity với credentialId thật, vì identity không chứa secret)
- Online gate có áp cho TOTP ask-each-time không? (bản chất nó đã cần mạng — không đổi)
