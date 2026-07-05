# Phase 05 — Passkey + TOTP capability v2 (V2.1: frozen transcripts, honest revoke)

Priority: cao · Effort: 2–3 buổi · Depends: P03b (grant v2), P04 (extension CK)

## Preflight — ĐÃ VERIFY (P2-9 đóng)
Passkey private key của Loox là software exportable: `PasskeySecret.privateKeyRaw: Data`
(`VaultifyCore/Passkey/PasskeyModels.swift`), ký qua `WebAuthn.assertion(privateKeyRaw:)`
— không Secure Enclave binding → shared-mode khả thi trực tiếp, không cần re-registration.

## Capabilities (grant v2, canonical bump chung với P03b — MỘT lần duy nhất)
- Passkey: `none | askEachTime | shared` · TOTP: thêm `.shared` cạnh `.askEachTime`.
- Modal cảnh báo khi chọn `shared` (TOTP hoặc passkey) — copy theo INV-08.

## Revoke semantics (SỬA theo review P1-4 — trung thực, INV-08)
- `askEachTime`: revoke = cryptographic/authorization stop (secret chưa từng rời owner).
- `shared`: revoke = **Vaultify access revocation ONLY** — gỡ identity sau verified
  refresh, chặn updates + official-client use; KHÔNG vô hiệu được seed/key đã giao.
  Thu hồi thật = rotate tại RP/origin (UI revoke nói thẳng + gợi ý rotate).
- Success criteria/QA không được viết "revoke chặn từ lần verify sau" cho shared mode.

## Protocol (schemas FROZEN tại P00 — không tự chế trong lúc code)
- `PasskeyAssertionApprovalRequestV1` + owner verify 12 bước THEO THỨ TỰ rồi mới Face ID;
  `PasskeyAssertionApprovalResponseV1` transcript-bound (requestID/epoch/credentialID/
  clientDataHash), seal đúng requester device key (INV-09). Không response trần
  `signature+authenticatorData`.
- Counter strategy: dùng quyết định A/B/C đã chốt ở P00 + test matrix RP
  (accept-zero / store-current / enforce-monotonic). KHÔNG ship shared passkey rộng
  khi chưa chốt — không "theo dõi rồi tính".
- Timing từ `SharedAccessTimingPolicy`: approvalRequestTTL ≠ UI wait ≠ polling budget;
  response muộn bind requestID nên không dùng nhầm được ở ceremony mới.

## Work items
1. Owner side: capability rows (passkey từ `PasskeyVault`, TOTP mode picker) +
   warning modal; publish metadata theo tiers (Tier 1: rpId/credentialId/userName —
   CHỈ tới approved devices; Tier 0 không có gì nhạy cảm).
2. Owner approve ceremony: `ApprovalCeremonyService` mở rộng — verify 12 bước →
   Face ID → `WebAuthn.assertion` với clientDataHash từ request → response sealed.
3. Recipient extension: shared mode = ký local từ cache per-device; askEachTime =
   UI "Chờ chủ sở hữu duyệt…" + huỷ, gửi request qua CK (P04), poll theo policy,
   timeout copy tử tế + deep-link fallback. **INV-11**: re-verify ngay trước
   completeAssertionRequest.
4. QuickType (quyết định #7): đăng ký `ASPasskeyCredentialIdentity` khi grant known +
   device allowed + capability ≠ none + not tombstoned; single-device unapproved KHÔNG
   đăng ký; revoked gỡ ngay sau verified refresh.
5. `SharedCredentialsCache` v2: optional passkey payload, version byte bump,
   decode back-compat (test).
6. Recipient app UI: passkey row theo mode + pending/denied states.

## Files (chính)
Như V2 cũ + `ApprovalModels`/canonical theo schema P00; l10n EN+VI toàn bộ copy mới.

## Success criteria
- askEachTime round-trip 2 máy: QuickType → chờ duyệt → owner Face ID → login OK;
  đo extension lifetime thực tế; owner offline → timeout đúng policy.
- shared mode: qua modal cảnh báo; dùng không cần hỏi; revoke gỡ identity/updates
  (KHÔNG claim thu hồi secret).
- Stale response (epoch cũ / requestID khác) bị loại — test P06.

## Risks
- Extension lifetime khi chờ approve — đo thật; quá ngắn → UX chuyển hẳn sang app.
- RP enforce-monotonic counter với nhiều signer cùng credentialID — xử lý theo
  strategy P00, có thể phải giới hạn compatibility (option C).
