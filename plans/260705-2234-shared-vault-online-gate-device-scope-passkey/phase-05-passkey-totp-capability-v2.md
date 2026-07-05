# Phase 05 — Passkey + TOTP capability v2 (askEachTime & shared giao-key)

Priority: cao · Status: planned · Effort: 2 buổi · Depends: P03 (grant v2), P04 (extension CK)

## Overview
Hai capability mới trên grant v2, mỗi cái 2 mode (quyết định #1 + #5):
- **Passkey**: `none | askEachTime | shared`
  - `askEachTime` (mặc định đề xuất): KHÔNG giao key. Extension/app recipient gửi
    ApprovalRequest kèm `clientDataHash` + rpId + credentialId → owner nhận push, Face ID,
    duyệt → owner ký WebAuthn assertion bằng privateKey (on-device) → response sealed
    (ephemeral HPKE như TOTP) → extension `completeAssertionRequest`.
  - `shared`: seal `PasskeySecret` (privateKeyRaw + metadata) cho recipient (per-device
    theo deviceScope P03) — recipient ký local, dùng không cần hỏi.
- **TOTP**: thêm mode `shared` (giao seed) bên cạnh `askEachTime` hiện có — recipient
  generate code local, không cần hỏi. ⚠️ Reversal QA-4 (bỏ TOTP reveal) — user chốt lại
  260705 kèm điều kiện CẢNH BÁO.

## Cảnh báo owner (bắt buộc, l10n EN+VI)
Khi chọn mode `shared` cho TOTP hoặc Passkey → `PolarisModal.destructive`-style confirm:
"Đối phương sẽ dùng được KHÔNG CẦN HỎI bạn, trên chính thiết bị của họ. Đã giao thì không
thu hồi được giá trị — thu hồi chỉ chặn cập nhật về sau." Chọn `askEachTime` không cần modal.

## Key work items
1. Grant v2 capabilities mở rộng (`FieldCapability` thêm case passkey; TOTP thêm
   `.totp(.shared)`) — nằm CHUNG version bump với P03 (một lần đổi canonical, không hai).
2. Owner publish: passkey metadata công khai trong display envelope (rpId, credentialId,
   userName — KHÔNG secret) để extension đăng ký `ASPasskeyCredentialIdentity`; seed/key
   sealed riêng theo mode.
3. Owner approve ceremony (askEachTime passkey): mở rộng `ApprovalCeremonyService` — verify
   request (device key pinned, nonce, epoch) → Face ID → `WebAuthn.assertion(...)` với
   clientDataHash NHẬN TỪ request → seal trả về. Counter: passkey counter=0 cố định
   (Vaultify dùng flags legacy) — xác nhận không vỡ RP.
4. Recipient extension ceremony: `PasskeyCeremonyView` thêm nhánh shared-passkey:
   - `shared` mode: giải key từ cache (per-device) → ký local như passkey thường.
   - `askEachTime`: UI "Chờ chủ sở hữu duyệt…" (spinner + huỷ), gửi request qua CK (P04),
     poll response ≤60s; timeout → gợi ý thử lại / deep-link mở app.
5. `SharedCredentialsCache` v2: entries mang optional passkey payload (mode, metadata,
   sealed key nếu shared) — bump version byte, decode back-compat.
6. Online gate (P01/P02) áp lên cả passkey shared: offline → không ký local dù có key
   (gate UI; honesty: kẻ jailbreak vẫn có key — ghi trong plan.md).
7. Recipient app UI: row passkey trong shared item detail ("Sign in with shared passkey" /
   "Request sign-in approval"), trạng thái pending/denied.

## Files (chính)
- `VaultifyCore/Sharing/ApprovalModels.swift` + canonical/verifier, `ApprovalCrypto.swift`
- `VaultifyCore/Sharing/SharedCredentialsCache.swift`, `SharedDisplayEnvelope.swift`
- `Vaultify/Services/Sharing/ApprovalShareService|CeremonyService|RecipientService`
- `Vaultify/Features/Sharing/ShareAccessSheet.swift`, `FieldCapabilityRow.swift` (+passkey row)
- `VaultifyAutoFill/PasskeyCeremonyView.swift`, `CredentialProviderViewController.swift`,
  `CredentialIdentityService.swift` (đăng ký ASPasskeyCredentialIdentity shared)
- Tests: capability codec v2, ceremony assertion vector, cache v2 back-compat

## Success criteria
- Owner share passkey askEachTime → recipient mở site → chọn passkey trong QuickType →
  extension chờ → owner duyệt trên máy owner → site đăng nhập thành công.
- Owner share passkey/TOTP `shared` (qua cảnh báo) → recipient dùng offline-UI-gated,
  không cần owner online.
- Revoke: identity/QuickType biến mất sau refresh; askEachTime chết ngay (epoch bump).

## Risks
- AutoFill session sống đủ lâu để chờ approve? Đo thật; nếu iOS kill sớm → fallback
  deep-link mở app recipient để hoàn tất đăng nhập trong app (WebView? KHÔNG — chỉ hiện
  hướng dẫn thử lại khi owner đã approve sẵn trong cửa sổ ngắn).
- Push tới owner phải là alert push (đường `approvalRequest` sẵn có — tái dùng).
- RP strict counter: một số site từ chối counter không tăng — theo dõi, có thể cần counter
  đồng bộ owner-side cho passkey shared (owner là source of truth khi askEachTime).
