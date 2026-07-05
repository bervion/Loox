# Phase 03 — Device Scope (V2.1: tách 03a/03b, DeviceKeyBinding, cấm legacy key)

Priority: cao · Effort: 1.5–2 buổi · Depends: P00

## P03a — Device identity migration (1 buổi)

- Mỗi device sinh HPKE keypair riêng; private key ở Keychain LOCAL, không bao giờ sync.
- Escrow chỉ sync: danh sách `DeviceKeyBinding { deviceKeyID (digest cố định),
  hpkePublicKeyHash }` + labels + pubkey directory (`deviceKeyID → pubkey`).
- **Legacy synced key (INV-04)**: đã sync qua iCloud = đã MẤT thuộc tính device-bound
  vĩnh viễn — không có cách "đổi tên" lấy lại property. Quy tắc cứng:
  - legacy key CHỈ được decrypt grants v1;
  - `legacyKeyEligibleForV2Single = false` — v2 single-device KHÔNG BAO GIỜ seal tới nó;
  - v2 multi-device cũng chỉ seal tới device keys được owner duyệt tường minh (INV-05).
- Test bắt buộc (P06): legacy key tồn tại trên device A+B; owner tạo v2 single-device
  grant pin A → ciphertext KHÔNG decrypt được bằng legacy key; device B fail.

## P03b — Grant v2 + per-device envelopes (1 buổi, canonical bump MỘT lần chung schema P05)

- GrantV2 signed payload: `grantID, epoch, deviceScope, allowedDeviceKeyIDs, capabilities`
  — **IDs + hash binding, KHÔNG raw pubkeys** (review P1-6): tránh coupling
  policy/directory/ciphertext/signature; rotate/re-seal không đổi signed grant.
- Canonical (INV-12): `allowedDeviceKeyIDs` sort lexicographic theo raw bytes trước khi
  encode; duplicates → reject; trailing bytes → reject. Vector fixtures từ P00.
- Envelope riêng: `deviceKeyID → sealed blob`; recipient decrypt bằng key device mình;
  miss → Tier 0 state "Thiết bị này chưa được cấp quyền".
- **Visibility tiers (INV-10)**: device chưa duyệt = Tier 0 (generic state; KHÔNG
  username/credentialId/notes; title tuỳ P00 chốt). Approved device = Tier 1 metadata +
  Tier 2 secrets.
- Owner UI: toggle "Cho phép dùng trên nhiều thiết bị" (default ON); banner "Thiết bị mới
  xin quyền truy cập" → owner duyệt (Face ID) → re-seal.
- **Replace Device flow (quyết định #6)**: new device publish key → owner "Thay thiết bị"
  (Face ID) → atomic: epoch++ , remove old deviceKeyID, add new, re-seal secrets,
  old request authority chết. Giữ capability config/history — không bắt re-share.

## Files
- `VaultifyCore/Sharing/ParticipantIdentity.swift`, `ApprovalCrypto.swift`,
  `ApprovalModels.swift` (+canonical v2), `ApprovalVerifier.swift`
- `Vaultify/Services/Sharing/ApprovalShareService.swift`, `ParticipantEscrowService.swift`
- `Vaultify/Features/Sharing/ShareAccessSheet.swift`, `ShareRecipientDetailSheet.swift`

## Success criteria
- v1 grants verify + hoạt động như multi (legacy path);
- v2 single: device 2 = Tier 0, không decrypt, request bị từ chối (key không allowed);
- Replace Device round-trip 2 máy;
- vectors v1-compat + v2 + tamper pass.

## Risks
- Canonical sai 1 byte = vỡ share cũ → vectors trước, code sau (P00 gate).
- Escrow migration: ngừng GHI legacy key, còn ĐỌC cho grants v1 tới khi owner re-share.
