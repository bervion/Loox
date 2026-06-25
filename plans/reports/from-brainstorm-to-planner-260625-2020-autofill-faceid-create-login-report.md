# AutoFill — Face ID unlock + Create-login from extension (design)

Source: /brainstorm session, branch `feat/identity-profile`, 2026-06-25.
Status: APPROVED by user → handoff to `/ck:plan` (default mode).

## Problem statement

AutoFill password suggest works on device. User wants:
1. Mở khoá extension bằng **Face ID** (không gõ master password mỗi lần). Pain: app vừa unlock rồi ẩn nền, sang web đăng ký vẫn bắt gõ master password.
2. Khi đăng ký web mới: **tạo password mạnh + lưu login** (site/username/email/password) vào vault, prefill từ default identity.
3. (Mong muốn) gợi ý + điền nhiều field identity (name/email/DOB).

## iOS reality constraints (brutal honesty — shaped scope)

- **Reuse app's unlocked in-memory state sang extension = KHÔNG được** (tiến trình riêng, không share RAM). Giải pháp đúng: Face ID 1 chạm trong extension via shared keychain.
- **Multi-field identity fill trên web cho app bên thứ 3 = KHÔNG được** (chỉ iCloud Keychain + Contacts). App bên thứ 3 chỉ trả `ASPasswordCredential` (user+password) / passkey / OTP. → chỉ email-as-username.
- **Auto-bắt password user gõ tay khi đăng ký = KHÔNG được**. Chỉ lưu được cái đi QUA extension → flow "Create login" do extension tự gen + lưu + trả.

→ ~80% yêu cầu khả thi; 20% (multi-field identity, auto-capture) bị iOS chặn → OUT of scope.

## Current-state findings (scout)

- Extension chỉ READ vault (`VaultReader`) + unlock bằng master password (Argon2). `CredentialProviderViewController` + `AutoFillView` (đã thêm os_log lifecycle markers).
- App có `BiometricKeyStore` (Face ID → Vault Key, Secure Enclave, `.biometryCurrentSet`, `WhenUnlockedThisDeviceOnly`).
- **Keychain KHÔNG có shared access group** (`KeychainStore.service=com.bervion.vaultify`, no `kSecAttrAccessGroup`) → extension (bundle `...autofill`) không đọc được biometric key của app. **Rào cản chính cho Phase 1.**
- `PasswordGenerator` ở target app (`Vaultify/Services/`) → extension không compile được → cần move xuống `VaultifyCore/`.
- Identity feature có default identity + email/name fields. `ASCredentialIdentityStore` đã chạy cho password (`CredentialIdentityService`).
- `VaultStore`/`ItemRecord` dùng chung cả 2 target (sources glob `VaultifyCore/**`).

## Approved solution — 2 phases

### Phase 1 — Face ID trong AutoFill extension (priority 1)

1. Thêm **Shared Keychain Access Group** (`$(AppIdentifierPrefix)com.bervion.vaultify.shared`) vào entitlements **cả 2 target** + Apple Developer portal + fastlane match.
2. `KeychainStore` + `BiometricKeyStore`: gắn `kSecAttrAccessGroup = shared group` cho item biometric key (account `vault.biometricKey`). Không sync iCloud (giữ zero-knowledge).
3. `AutoFillView` onAppear: nếu `BiometricKeyStore.isEnrolled` → gọi Face ID `retrieve` → Vault Key → vào thẳng credential list, bỏ qua master password. Fail/cancel/not-enrolled → form master password cũ.
4. Bonus: đường biometric không chạy Argon2 → nhanh + nhẹ memory (tốt cho extension memory limit).
5. **Migration:** key biometric cũ ở keychain riêng app → app tự **re-store im lặng** vào shared group lần unlock biometric kế tiếp (không bắt user bật lại).

Files: `Project.swift`, `Vaultify/Vaultify.entitlements`, `VaultifyAutoFill/VaultifyAutoFill.entitlements`, `VaultifyCore/Keychain/KeychainStore.swift`, `VaultifyCore/Keychain/BiometricKeyStore.swift`, `VaultifyAutoFill/AutoFillView.swift`, app biometric-enable path (`VaultSession` / Settings / onboarding).

Risk: đổi provisioning → match/CI ký lỗi thì extension không build → **bắt buộc test device thật**. Mitigation: verify entitlement + provisioning trước khi merge.

### Phase 2 — Create & save new login từ extension (priority 2)

1. Move `PasswordGenerator` → `VaultifyCore/PasswordGenerator.swift` (DRY).
2. `AutoFillView` credential list thêm hàng đầu **"＋ Tạo login mới"** (sau unlock).
3. `CreateLoginView` (mới): site/title prefill từ `serviceIdentifiers` domain; username/email prefill từ **default identity** (editable); password auto-gen + regenerate + strength; nút **Lưu & điền**.
4. `VaultWriter` (mới, đối xứng `VaultReader`) trong VaultifyCore: seal `ItemRecord` mới bằng Vault Key đang có → insert shared store (`updatedAt=now`) → cập nhật `ASCredentialIdentityStore` → trả `ASPasswordCredential`.
5. App mở sau thấy item mới; CloudKit sync pick up nhờ `updatedAt` mới (khớp LWW updatedAt gate đã biết).

Files: `VaultifyCore/PasswordGenerator.swift` (moved), `VaultifyCore/VaultWriter.swift` (new), `VaultifyAutoFill/CreateLoginView.swift` (new), `VaultifyAutoFill/AutoFillView.swift`, `VaultifyAutoFill/CredentialProviderViewController.swift`.

Out of scope: multi-field web identity fill; auto-capture manually typed password; copy-identity-fields buttons (YAGNI, để sau).

Risk: extension WRITE vào SwiftData store → model phải khớp app (đang dùng chung `ItemRecord` ✓); ghi đua app↔extension hiếm.

## Success criteria

- Phase 1: trên device thật, mở Vaultify ở field password → Face ID prompt (không phải master password) → unlock → list logins. Fail Face ID → fallback master password. App + extension build & ký OK.
- Phase 2: trên form đăng ký → "Tạo login mới" → gen password + prefill identity → Lưu & điền → field được điền; mở app thấy item mới đúng site/username/password.

## Decisions locked (user-confirmed)

- Phasing: Face ID trước, rồi Create-login. (Recommended)
- Shared keychain access group: **OK thêm** (chấp nhận đổi entitlement + portal + match/CI).
- Create-login save: **user xác nhận trước khi lưu** (form sửa được).
- Prefill source: **default identity** (email/name).
- Localization: mọi string mới EN + VI (bắt buộc theo project).

## Open questions

- Migration biometric key: re-store im lặng có cần xử lý case key cũ `.biometryCurrentSet` đã invalidate? (plan nên cover fallback: nếu re-store fail → bật lại Face ID 1 lần).
- `VaultWriter` có cần đụng `RotationNotificationService` / favicon fetch cho item mới tạo từ extension không, hay để app xử lý lần sau? (đề xuất: để app, giữ extension nhẹ).
