# Security Invariants — Shared Vault Hardening V2.1 (FROZEN 260706)

Nguồn chân lý cho mọi PR của gói này. PR description phải reference INV-xx liên quan.
Đổi bất kỳ invariant nào = quay lại user, không tự sửa.

## Invariants

- **INV-01** Shared values never render before CURRENT authorization verification.
  Values không được materialize vào render tree trước state `.authorized`. Cấm pattern
  "render cached rồi verify song song".
- **INV-02** Network path availability alone never authorizes access. Layer A
  (`hasSatisfiedNetworkPath`) chỉ là precondition; Layer B (authoritative grant verify)
  mới cấp quyền.
- **INV-03** Failed/timeout verification is fail-closed → state `unavailable`
  ("Không thể xác minh quyền truy cập lúc này"), phân biệt với `offline`
  ("Cần kết nối mạng") và `revoked` ("Chủ sở hữu đã thu hồi").
- **INV-04** V2 single-device ciphertext is NEVER sealed to legacy synced keys.
  `legacyKeyEligibleForV2Single = false`. Legacy key (đã từng sync iCloud) chỉ được
  decrypt grants v1 — thuộc tính device-bound đã mất là mất vĩnh viễn.
- **INV-05** A device key becomes eligible only after explicit owner authorization
  (Face ID). Không auto-approve theo cùng iCloud account.
- **INV-06** Grant epoch mismatch rejects both requests AND responses/verify-results
  (chống stale authorization: verify result mang epoch, so với epoch hiện hành trước
  khi áp dụng).
- **INV-07** askEachTime secrets never leave the owner device (TOTP seed, passkey
  private key). Chỉ output (code/assertion) rời đi, sealed per-request.
- **INV-08** shared-mode delivered secrets are NOT cryptographically revocable.
  Revoke = Vaultify access revocation only (gỡ identity, chặn updates/official-client).
  Thu hồi thật = rotate tại RP/origin. Mọi UI copy + docs phải nói đúng như vậy.
- **INV-09** Passkey approval response is bound to the exact request transcript
  (requestID + grantID + epoch + credentialID + clientDataHash). Response thiếu binding
  không được chấp nhận.
- **INV-10** Unapproved devices do not receive sensitive display metadata
  (visibility tiers bên dưới).
- **INV-11** Extension completion path re-checks authorization immediately before
  fill/assert (ngay trước `completeRequest`/`completeAssertionRequest`).
- **INV-12** Canonical encoding: deterministic ordering (byte-lexicographic sort cho
  mọi list key/ID), duplicates rejected, unknown fields/trailing bytes rejected.

## Frozen protocol decisions

### Counter strategy (passkey) = **A: always-zero**
Verified: `VaultifyCore/Passkey/WebAuthn.swift:9` — Vaultify đã giữ sign counter = 0
từ ngày đầu (spec cho phép constant zero = "no counter support"). Mọi signer
(owner ceremony, delegated askEachTime, shared key) đều ký counter 0 → không xung đột
monotonic giữa nhiều signer cùng credentialID. RP enforce-monotonic-tăng-dần với
counter 0 hằng số: theo WebAuthn spec, RP chỉ được coi là clone-signal khi counter
regress từ giá trị >0; đã hoạt động production với passkey Vaultify hiện tại.
Không có strategy B/C — nếu gặp RP thực tế từ chối, ghi nhận và xử lý như
compatibility bug riêng.

### Visibility tiers (Tier 1 cụ thể — chờ user duyệt cùng P00)
- **Tier 0 — participant-known (device CHƯA duyệt, single-device)**: chỉ generic state
  "Mục được chia sẻ — thiết bị này chưa được cấp quyền" + tên owner. KHÔNG title,
  KHÔNG username, KHÔNG domain, KHÔNG credentialId, KHÔNG icon site.
- **Tier 1 — approved-device metadata**: title, website host, username, rpId,
  credentialId, field labels/kinds, icon. (Đây là những gì SharedDisplayEnvelope
  hiện có + passkey metadata mới.)
- **Tier 2 — decryptable secrets**: password/TOTP output/seed (mode shared)/
  passkey key (không tồn tại với askEachTime), chỉ sau `.authorized` (INV-01).

### SharedAccessTimingPolicy (config — không magic numbers trong code)
```swift
struct SharedAccessTimingPolicy {
    var grantVerificationDeadline: Duration = .seconds(4)   // verify quá hạn → .unavailable
    var approvalRequestTTL: Duration = .seconds(120)        // server-side TTL của request
    var extensionPollingBudget: Duration = .seconds(45)     // extension ngừng poll (≠ TTL)
    var pollingBackoff: [Duration] = [.seconds(1), .seconds(2), .seconds(3), .seconds(5)]
}
```
Response về sau khi ceremony đã huỷ: vô hại — bind requestID (INV-09), ceremony mới
có requestID mới.

### Frozen schemas

**GrantV2** (signed payload — KHÔNG chứa raw HPKE pubkeys):
```
grantID, itemId, recipientId, epoch: UInt64, deviceScope: multi|single,
allowedDeviceKeyBindings: [DeviceKeyBinding], capabilities: [fieldOrSlotId: CapabilityV2],
createdAtUnixMs, expiresAtUnixMs?, ownerSigningPubKey, ownerSignature
DeviceKeyBinding = { deviceKeyID: Data /* SHA-256(pubkey) truncated 16B? — chốt: FULL 32B */,
                     hpkePublicKeyHash: Data /* SHA-256 full */ }
```
- Canonical: bindings sort theo deviceKeyID bytes; duplicate deviceKeyID → reject.
- Directory (`deviceKeyID → HPKE pubkey`) và envelopes (`deviceKeyID → sealed blob`)
  là record RIÊNG ngoài chữ ký; verifier đối chiếu `hash(pubkey trong directory) ==
  hpkePublicKeyHash trong grant` trước khi dùng (chống substitution).
- CapabilityV2: password/value = none|shared; totp = none|askEachTime|shared;
  passkey = none|askEachTime|shared.
- v1 grants: verify theo canonical v1, ngữ nghĩa deviceScope=multi, capability như cũ.

**PasskeyAssertionApprovalRequestV1**:
```
protocolVersion: UInt8 = 1, requestID: UUID, grantID, grantEpoch: UInt64,
requesterDeviceKeyID: Data, rpID: String, credentialID: Data,
clientDataHash: Data (== 32 bytes), requestedAtUnixMs, expiresAtUnixMs,
nonce: Data(32), requestSignature (P256, device signing key)
```
Owner verify THEO THỨ TỰ, fail bước nào dừng bước đó, TRƯỚC Face ID:
1 version · 2 signature · 3 requester device ∈ grant bindings · 4 grant alive ·
5 epoch exact · 6 capability == passkey.askEachTime · 7 rpID == stored credential rpID ·
8 credentialID exact · 9 clientDataHash.count == 32 · 10 nonce unseen ·
11 not expired · 12 response sẽ bind requestID.

**PasskeyAssertionApprovalResponseV1** (sealed tới requester device key):
```
requestID, grantID, epoch, credentialID, clientDataHash,
authenticatorData: Data, signature: Data, userHandle: Data?, expiresAtUnixMs
```
Extension chấp nhận chỉ khi requestID/epoch/credentialID/clientDataHash khớp request
đang chờ (INV-09) và chưa hết hạn.

## State machine chuẩn (P01/P02 dùng chung)
```
offline → (path satisfied) → verifying → authorized | revoked | unavailable
authorized → (path lost) → offline    · verify result stale-epoch → discard (INV-06)
```
