# Approval Mode — Share Passkey (recipient sign-in bằng passkey được share)

Trạng thái: **SUPERSEDED** bởi `plans/260705-2234-shared-vault-online-gate-device-scope-passkey/`
(user chốt 260705: passkey mặc định ask-each-time như TOTP + option giao-key kèm cảnh báo,
gộp chung gói online-gate + device-scope). Giữ file này làm bối cảnh thiết kế ban đầu.

## Bối cảnh & yêu cầu (260705)

User: share username/password qua Approval Mode đã chạy, nhưng "đang thiếu share passkey" —
recipient cần đăng nhập site bằng passkey của owner.

Hai bug liên quan đã fix cùng ngày (không thuộc plan này):
- Projection snapshot sealed (share không còn "biến mất" sau lock/kill/offline).
- Cancellation guard trong `SharedItemsProjection.refresh` (hết race ghi đè cache AutoFill rỗng).

## Vì sao khả thi

- Passkey của Vaultify là software-backed (`PasskeySecret.privateKeyRaw` — vendored WebAuthn,
  không bind Secure Enclave) → private key CÓ THỂ seal + gửi qua kênh shared-value hiện có
  (HPKE tới `participantPubKey`, cùng đường với password `shared`).
- Extension recipient đã có pipeline `SharedCredentialsCache` + `CredentialIdentityService` —
  passkey cần thêm `ASPasskeyCredentialIdentity` + đường assertion đọc từ cache.

## Thiết kế đề xuất (phase)

1. **Model + grant**: capability mới `passkey(.shared)` (FieldCapability mở rộng — cẩn thận
   canonical bytes của grant: thêm case = đổi signed payload → cần version grant hoặc encode
   backward-compatible; verifier fail-closed sẵn).
2. **Owner side**: `ShareAccessSheet` liệt kê passkey của item (từ `PasskeyVault`) như một
   capability row; publish seal `PasskeySecret` (rpId, userName, userHandle, credentialId,
   privateKeyRaw) như một sealed shared blob riêng.
3. **Recipient projection**: giải HPKE → giữ trong projection (RAM) + snapshot sealed;
   detail screen hiện row passkey (read-only, "Shared passkey · rpId").
4. **AutoFill extension**: `SharedCredentialsCache` thêm optional passkey payload;
   `CredentialIdentityService` đăng ký `ASPasskeyCredentialIdentity`; assertion path trong
   extension ký bằng `privateKeyRaw` (tái dùng `WebAuthn.swift`). RP thấy credential như trên
   máy owner (cùng credentialId).
5. **Revoke honesty**: private key đã giao thì revoke chỉ chặn bản cập nhật — recipient có
   thể đã sao chép key. Copy UI phải nói thẳng (giống shared password). Khuyến nghị owner
   rotate passkey trên site khi cần thu hồi thật.
6. **Tests + QA 2 máy**: envelope round-trip, grant canonical không vỡ chữ ký cũ,
   assertion từ cache, revoke làm biến mất identity.

## Rủi ro chính

- **Grant canonical/signature compatibility** (mục 1) — sai một byte là mọi share cũ fail
  verify. Cần vector test trước khi merge.
- Sync passkey giữa 2 THIẾT BỊ của recipient: snapshot là device-local; chấp nhận V1.
- Apple policy: chia sẻ passkey credential ngoài iCloud Keychain family-sharing là vùng xám
  UX (không vi phạm API nào — mình tự quản private key), nhưng nên ghi chú release notes.

## Estimate

~1 buổi làm việc tập trung (5 phases + QA 2 thiết bị). Không nên gộp chung release với
các thay đổi hôm nay.

## Unresolved questions

- Passkey share nên là `shared` vĩnh viễn (giao key) hay "ask each time" (owner ký hộ
  assertion qua approval round-trip — an toàn hơn NHƯNG cần online + latency ~giây,
  và extension timeout của AutoFill khá ngắn)? V1 đề xuất: `shared` (giao key) + copy trung thực.
- Có cần gate sau Face ID mỗi lần recipient dùng passkey share không?
