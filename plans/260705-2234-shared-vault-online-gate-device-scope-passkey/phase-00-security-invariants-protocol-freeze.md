# Phase 00 — Security Invariants + Protocol Freeze (BẮT BUỘC trước mọi code)

Priority: cao nhất · Effort: 0.5 buổi · Depends: — · Added by security review 260705

## Deliverable 1 — `security-invariants.md` (nguồn chân lý, mọi PR đối chiếu)

- INV-01 Shared values never render before CURRENT authorization verification
  (không materialize vào render tree trước khi `.authorized`).
- INV-02 Network path availability alone never authorizes access.
- INV-03 Failed/timeout verification is fail-closed (state `unavailable`, không phải `offline`).
- INV-04 V2 single-device ciphertext is NEVER sealed to legacy synced keys
  (`legacyKeyEligibleForV2Single = false`, có test bắt buộc).
- INV-05 A device key becomes eligible only after explicit owner authorization (Face ID).
- INV-06 Grant epoch mismatch rejects both requests and responses (chống stale-authorization).
- INV-07 askEachTime secrets never leave the owner device.
- INV-08 shared-mode delivered secrets are NOT cryptographically revocable — revoke =
  Vaultify access revocation only; thu hồi thật = rotate tại RP/origin. Mọi UI copy tuân theo.
- INV-09 Passkey approval response is bound to the exact request transcript (requestID,
  epoch, credentialID, clientDataHash).
- INV-10 Unapproved devices do not receive sensitive display metadata (visibility tiers).
- INV-11 Extension completion path re-checks authorization immediately before fill/assert.
- INV-12 Canonical encoding: deterministic ordering (sort lexicographic theo raw bytes),
  duplicates rejected, unknown-field/trailing-bytes rejected.

## Deliverable 2 — Frozen schemas (spec + vector fixtures, chưa code)

1. **GrantV2**: `grantID, epoch, deviceScope, allowedDeviceKeyIDs: [Data] (sorted, no dup),
   capabilities` — KHÔNG nhét raw HPKE pubkeys vào signed payload. Binding chống
   substitution: grant ký `deviceKeyID + hash(hpkePublicKey)` (DeviceKeyBinding).
   Directory `deviceKeyID → pubkey` và envelope `deviceKeyID → sealed blob` sống NGOÀI
   signed grant (rotate/re-seal không đổi chữ ký policy).
2. **PasskeyAssertionApprovalRequestV1**: protocolVersion, requestID, grantID, grantEpoch,
   requesterDeviceKeyID, rpID, credentialID, clientDataHash (đúng 32 bytes), requestedAt,
   expiresAt, nonce, requestSignature. Owner verify 12 bước THEO THỨ TỰ (version → sig →
   device pinned → grant alive → epoch exact → capability đúng → rpID khớp credential →
   credentialID exact → hash length → nonce unseen → chưa hết hạn → response bound) rồi
   MỚI Face ID.
3. **PasskeyAssertionApprovalResponseV1**: requestID, grantID, epoch, credentialID,
   clientDataHash, authenticatorData, signature, userHandle?, expiresAt — seal đúng
   requester device key. Không bao giờ trả trần `signature + authenticatorData`.
4. **SharedAccessTimingPolicy** (config, không magic numbers): grantVerificationDeadline,
   approvalRequestTTL, extensionPollingBudget, pollingBackoff. Request TTL ≠ UI wait ≠
   poll deadline; response muộn không được dùng cho ceremony mới (bind requestID).
5. **Visibility tiers**: Tier 0 participant-known (generic state) · Tier 1 approved-device
   (title/username/rpId/credentialId metadata) · Tier 2 decryptable secret. Single-device:
   device chưa duyệt = Tier 0.
6. **State taxonomy** (UI + support): `offline` ("Cần kết nối mạng") ≠
   `verificationUnavailable` ("Không thể xác minh quyền truy cập lúc này") ≠
   `revoked` ("Chủ sở hữu đã thu hồi"). Không gom chung.
7. **Counter strategy passkey (quyết định protocol, chốt tại P00)**: chọn A
   always-zero-from-creation / B synchronized authoritative counter / C compatibility
   restrictions — kèm test matrix RP (accept-zero / store-current / enforce-monotonic).
   Nhiều signer cùng credentialID (owner + delegated + shared) là lý do phải chốt sớm.

## Success criteria
- `security-invariants.md` + schema spec + vector fixture skeletons merge trước khi bất kỳ
  phase nào code. Mọi phase sau reference INV-xx trong PR description.
