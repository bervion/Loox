# Phase 03 — Device Scope: seal per-device + owner toggle

Priority: cao · Status: planned · Effort: 1 buổi · Depends: P01

## Overview
Owner chọn "Cho phép nhiều thiết bị" hay "Chỉ 1 thiết bị" khi share (quyết định #3 —
crypto cứng). Single-device: sealed blobs seal RIÊNG cho HPKE key của từng device được
phép; device ngoài danh sách không giải mã được (không chỉ bị từ chối ở tầng request).

## Key changes
1. **ParticipantIdentity per-device**: hiện tại 1 HPKE keypair per-participant, private key
   escrow SYNC qua iCloud (multi-device recipient dùng chung). Đổi: mỗi device sinh keypair
   riêng, private key KHÔNG BAO GIỜ rời device (Keychain local); escrow chỉ còn sync danh
   sách PUBLIC keys + device labels. Migration: identity cũ coi như "device key chung" —
   grants v1 tiếp tục hoạt động.
2. **Grant v2**: thêm `deviceScope: multi|single` + `sealedForDeviceKeys: [Data]` (danh sách
   HPKE pubkeys được seal). ĐỔI CANONICAL BYTES → version bump trong signed payload;
   verifier: v1 grants → deviceScope=multi mặc định. Vector tests bắt buộc (encode/verify
   v1 cũ + v2 mới).
3. **ApprovalCrypto**: `sealShared` nhận N recipient pubkeys → map keyId→ciphertext.
   Recipient giải bằng key của device mình; miss → state "Owner giới hạn thiết bị".
4. **Owner UI** (`ShareAccessSheet` config): toggle "Cho phép dùng trên nhiều thiết bị"
   (default ON = multi). Single: seal cho device ĐẦU TIÊN accept; device sau hiện
   "Thiết bị này không được cấp quyền".
5. **Multi mode + device mới của recipient**: device mới publish pubkey → owner nhận
   notification "Thiết bị mới xin quyền truy cập" → approve = re-seal (re-publish blobs).
   V1 đơn giản: KHÔNG auto — owner mở share detail thấy banner và bấm "Cấp cho thiết bị mới".

## Files
- `VaultifyCore/Sharing/ParticipantIdentity.swift`, `ApprovalCrypto.swift`,
  `ApprovalModels.swift` (+canonical), `ApprovalVerifier.swift`
- `Vaultify/Services/Sharing/ApprovalShareService.swift`, `ParticipantEscrowService.swift`
- `Vaultify/Features/Sharing/ShareAccessSheet.swift`, `ShareRecipientDetailSheet.swift`
- Tests: grant v1/v2 canonical vectors, seal-N round-trip, wrong-device fail-closed

## Success criteria
- Single-device share: device 2 của recipient thấy item nhưng KHÔNG giải mã được values
  (state rõ ràng), request ask-each-time từ device 2 bị owner-side từ chối (key không pinned).
- Grants v1 cũ vẫn verify + hoạt động như multi.

## Risks
- Đụng chữ ký grant — sai canonical là vỡ toàn bộ share cũ (mitigate: vectors + QA hai máy).
- Escrow migration: device đã sync private key chung trước đây → giữ tương thích đọc,
  ngừng ghi mới.

## Unresolved
- Recipient mất máy (single): V1 = owner revoke + re-share (đề xuất, cần user xác nhận).
