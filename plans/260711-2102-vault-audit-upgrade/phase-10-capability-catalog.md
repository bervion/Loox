# Phase 10 — ServiceCapabilityCatalog: passkey/2FA opportunities (V1.2)

**Priority:** P1 · **Status:** ☐ · **Ước lượng:** 1 ngày · **Phụ thuộc:** 01 (nên xong trước 07)

## Context (verified)

`TwoFactorCatalog` (Vaultify/Services/Watchtower/) hardcode ~70 domain + title fragments, chỉ
biết TOTP, match registrable-domain đúng cách. Proposal Module E: mở rộng thành catalog
versioned biết passkey + securitySettingsURL, wording không khẳng định trạng thái server-side.

## Thiết kế

```swift
// VaultifyCore/Audit/ServiceCapabilityCatalog.swift
struct ServiceCapability: Codable, Sendable {
    let domain: String
    let supportsTOTP: Bool
    let supportsPasskey: Bool
    let supportsRecoveryCodes: Bool
    let securitySettingsURL: String?
    let aliases: [String]?          // domain phụ (accounts.google.com…)
}
struct CapabilityCatalogDocument: Codable, Sendable {
    let version: Int                // bump khi data đổi → findings needsRecheck đúng cách
    let updatedAt: String
    let services: [ServiceCapability]
}
```

- **Data**: bundled JSON `VaultifyCore/Audit/Resources/service-capability-catalog.json`,
  curate từ 2fa.directory + passkeys.directory cho ~150-200 service phổ biến (giữ nhóm VN:
  ngân hàng, momo/zalopay). Đây là dataset curate, KHÔNG fetch tự do.
- **Remote refresh**: NGOÀI scope đợt này (câu hỏi mở trong plan.md) — cấu trúc version sẵn,
  ship data theo app update. Nếu sau này bật: static JSON trên loox.pw, signature check.
- `TwoFactorCatalog` refactor thành facade đọc catalog (giữ API `supports2FA` cho code cũ),
  matching logic registrable-domain + title fragment GIỮ NGUYÊN (đã tốt).

## Rules

| ruleID | Điều kiện | Severity | Wording bắt buộc |
|--------|-----------|----------|------------------|
| `auth.totp-available` | catalog supportsTOTP, item login không TOTP | low (Improve) | "No verification code is saved in Loox" — KHÔNG "2FA is off" |
| `auth.passkey-available` | catalog supportsPasskey, item không passkey Loox quản lý | low (Improve) | "…supports passkeys. Loox does not currently have one saved for this account" — KHÔNG "Passkey is disabled" |

- Scoring phase 04: 2 rule này là "available improvement" — trừ nhẹ pillar Auth readiness.
- Remediation phase 08: [Open security settings] dùng `securitySettingsURL`.
- Fingerprint gồm catalog `version` → catalog update tự re-evaluate.

## Files

- **Tạo:** `ServiceCapabilityCatalog.swift`, `Resources/service-capability-catalog.json`,
  `Rules/AuthenticationOpportunityRules.swift`
- **Sửa:** `TwoFactorCatalog.swift` (facade), rule registry, `Project.swift`/tuist resource
  nếu cần khai báo resources cho VaultifyCore.

## Todo

- [ ] Model + loader (parse 1 lần, cache static) + JSON dataset curate
- [ ] 2 rules + wording localize EN+VI đúng ràng buộc trên
- [ ] Tests: domain match không false-positive (x.com vs netflix.com case đã có), version bump
  → fingerprint đổi, item có passkey/TOTP → không finding
- [ ] `make check`

## Success criteria

GitHub login không passkey → finding Improve wording đúng; item có TOTP → im lặng; catalog
update không làm trùng finding.
