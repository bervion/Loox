# Brainstorm — Approval Mode Sharing (capability delegation, not secret sharing)

Date: 2026-07-05 · Status: design approved by user · Next: `/ck:plan` (full build, 1 PR)

## Problem

Item detail header có nút share (hiện chỉ là `ShareLink` text non-secret). Muốn: owner A chia sẻ
quyền dùng credential cho người B mà **secret không rời vault của A**. B chỉ *request* xác thực; A
approve/reject từng lần (hoặc theo session). Mô hình: **Grant → Request → Approve → Ephemeral
capability** ("share access, not secrets"), thay cho "share secret".

## User decisions (locked)

1. **Full cross-user build trong 1 PR** (không tách nhịp same-user→cross-user).
2. **Per-field share config**: owner cấu hình từng field TRƯỚC khi share — mỗi field một trong
   `none` / `shared` (B thấy trực tiếp) / `askEachTime` (approval mỗi lần).
3. **iCloud bắt buộc** cho feature (Apple-only, cả A và B phải bật iCloud).
4. V1 credential scope: TOTP + password/username qua per-field config. **Passkey approval = R&D,
   OUT of scope** (extension lifecycle + browser timeout chưa chứng minh — xem Risks).

## Codebase findings (đã verify)

- Nút share hiện tại: `ItemDetailScreen.swift:50-54` — `ShareLink` text, không liên quan.
- **Crypto ~90% sẵn**: HPKE `Curve25519_SHA256_ChachaPoly` seal-to-ephemeral + `info` binding chống
  replay đã dùng ở `VaultKeyPairing.swift` và `PasskeyEnvelope.swift`. Tái dùng cho ApprovalResponse.
- **Sync hiện tại = single-user private DB** (`CloudSyncService.swift`), Vault Key cấp cho thiết bị
  CÙNG chủ qua QR pairing (`VaultKeyEscrowService`, `VaultKeyPairing`). **Không có cross-user.**
- **CKShare / shared DB = ZERO** (grep confirm). Net-new subsystem.
- **Không có device signing identity** cho control plane → thêm mới (dùng `P256.Signing`, pattern có
  sẵn `WebAuthn.swift:35`).
- `AppPushDelegate.swift` đã handle `CKNotification` + `registerForRemoteNotifications` — base để mở
  rộng subscription sang shared DB.
- Loox **đã là passkey provider thật** (`PasskeyVault`, `WebAuthn`) — nền cho passkey-approval sau này.
- iCloud entitlement hiện **giữ OUT khỏi app target** vì crash-khi-unprovisioned (CLAUDE.md); container
  lazy (`CloudSyncService`). Feature này buộc bật iCloud → phải provision container + guard no-launch-crash.

## Architecture

### Hai mặt phẳng (giữ nguyên nguyên tắc của user)
- **Secret Plane**: seed/password/passkey vẫn nằm trong vault A đã seal bằng Vault Key A. B **không bao
  giờ** có Vault Key A. Không share seed.
- **Control Plane**: một CloudKit **custom zone chia sẻ qua CKShare**, một share cho mỗi recipient.
  Mọi message tự-chứng-thực bằng chữ ký device (B không sửa state tuỳ ý).

### Transport: CKShare zone-level (serverless, Apple-only)
- A tạo custom zone "approval per-recipient", đặt `CKShare` lên zone. B accept qua share URL
  (`CKShare.Metadata` → `acceptShares`) → thấy zone trong **shared database** của B.
- A owns zone → request records B ghi vào nằm trong zone của A → A subscribe zone-change nhận push.
- B subscribe shared DB nhận response push.

### Identity & keys
- Mỗi device sinh **signing identity** `P256.Signing` (control-plane), publish public key.
- **B participant keypair** (HPKE) sinh khi accept share; **private key ride B's own vault/sync** (B là
  full Loox user) → nhất quán trên các máy của B mà A không cần biết. A seal tới participant pubkey của B.
- ApprovalResponse: HPKE per-request ephemeral (từ request của B), tái dùng pattern `VaultKeyPairing`.

### Data model (records trong shared zone, per recipient)
```
ShareGrant       { itemRef, capabilities:[field: none|shared|askEachTime], epoch,
                   expiresAt?, ownerSigningPubKey, participantPubKey, ownerSignature }
SharedFieldBlob  { field, hpkeSealed(value → participantPubKey) }   // chỉ field 'shared'; A cập nhật khi item đổi
ApprovalRequest  { requestID, grantRef, requesterDeviceID, context(.totp itemRef | .field),
                   nonce, ephemeralPubKey, createdAt, expiresAt, requesterSignature }   // B ghi
ApprovalResponse { requestID, decision, hpkeSealed(payload), ownerSigningPubKey, ownerSignature } // A ghi
   TOTPPayload   { code, validUntil, requestNonce }
```

### Approve gate (A)
signature hợp lệ ∧ grant active (đúng epoch) ∧ device authorized ∧ request chưa hết hạn ∧ nonce chưa dùng
→ Face ID → đọc seed local → sinh code → HPKE-seal tới ephemeral key B. CloudKit chỉ thấy ciphertext.

### Revocation
A bump `epoch` trên grant / stop sharing (delete share) → mọi request epoch cũ bị từ chối. Không cần
reset TOTP seed.

### Latency mitigation (baked in, không gate)
Response mang `validUntil` thật; B hiển thị theo đó, hết hạn → "Request again". **Approval Session
(15 phút)** là luồng chính giảm phiền: trong session, request B auto-issue không spam A.

## Surface / phases (đề xuất cho plan — 1 PR, phase nội bộ)
1. **iCloud enablement**: provision container, entitlement vào app target, guard no-launch-crash, gỡ/điều
   chỉnh gating `VAULTIFY_ICLOUD` cho path bắt buộc-iCloud của feature.
2. **Control-plane crypto core** (VaultifyCore, nonisolated): device signing identity, request/response
   canonical encoding + sign/verify, HPKE response seal (tái dùng), nonce store, epoch.
3. **CKShare transport**: custom zone per-recipient, tạo/accept share, subscriptions (A: zone-change;
   B: shared DB), push routing trong `AppPushDelegate`.
4. **Share config UI** (từ nút share ItemDetail): sheet chọn recipient + per-field capability; tạo grant
   + share; seal SharedFieldBlob.
5. **Owner approval UX**: push → sheet context (service/device/time/security-code) + Face ID approve/reject
   + Approval Session policy.
6. **Recipient UX**: item chia-sẻ hiện trong vault B ("requires approval"); nút Request; hiển thị code
   ephemeral + countdown; field `shared` hiện trực tiếp.
7. **Revocation + management**: màn "Shared with / Shared to me", revoke, epoch bump, expiry.
8. **Localization EN+VI**, design-system compliance, DEBUG file-based self-test cho crypto round-trip.

## Risks
1. **CKShare push latency** cho cửa sổ TOTP 30s — rủi ro #1. Mitigation baked (validUntil + session +
   Request-again). QA on-device có thể buộc session-mode thành path chính.
2. **iCloud mandatory vs pillar "no account/no server"** — mâu thuẫn marketing; feature phải opt-in rõ,
   không ép user thường bật iCloud, không crash khi chưa provision.
3. **1 PR lớn** → review nặng; giữ crypto core tách module, test độc lập.
4. **CKShare participant onboarding** (invite/accept) nhiều edge (B chưa cài app, hai máy của B, mất mạng).
5. **Passkey approval** cố tình OUT — extension lifecycle/timeout chưa chứng minh.

## Open questions (cho plan / cần user khi tới)
- B nhận diện qua đâu: iCloud share URL gửi tay (Messages/AirDrop) hay in-app directory? (đề xuất: share
  URL qua system share sheet — KISS).
- Field `shared` có auto-cập-nhật khi A đổi item không, hay snapshot lúc share? (đề xuất: auto qua
  SharedFieldBlob re-seal khi item mutate).
- Password có nên cho `askEachTime` không, hay chỉ `none|shared`? (user trước đánh giá password ask ít
  giá trị — đề xuất password chỉ none|shared, ask-each-time chỉ cho TOTP).
