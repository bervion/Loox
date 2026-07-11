# Phase 03 — Integrity & hygiene rules (Modules F + G + URL checks)

**Priority:** P1 · **Status:** ☐ · **Ước lượng:** 1-1.5 ngày · **Phụ thuộc:** phase 01

## Context

Đây là nhóm "Loox làm tốt hơn 1Password" (proposal Module G). Toàn bộ local, không network.
Dữ liệu sẵn có: `rotateDays`/`passwordChangedAt` (RotationStatus), `lastUsedAt` (ItemRecord),
multi-website (`item.websites`), TOTP secret, passkey metadata, attachments (AttachmentStore).

## Rules mới (tất cả trong `VaultifyCore/Audit/Rules/`)

| ruleID | Logic | Severity | Group UI |
|--------|-------|----------|----------|
| `integrity.duplicate-exact` | 2+ items trùng title+username+password+URL set (+OTP) — so trên normalized values | low | Maintain |
| `integrity.duplicate-conflict` | cùng domain+username nhưng password khác — hiển thị updatedAt 2 bên, KHÔNG auto-delete | high | Act now |
| `integrity.incomplete` | login không password và không passkey; card thiếu expiry; OTP thiếu issuer/account; note rỗng | low | Maintain |
| `integrity.otp-invalid` | TOTP secret không decode base32 / digits/period bất thường (dùng validate của `TOTPGenerator`) | medium | Improve |
| `integrity.orphan` | attachment mất parent; passkey metadata mất item; duplicate custom field key | low | Maintain |
| `url.malformed` | URL không parse / scheme không hỗ trợ | low | Maintain |
| `url.insecure-http` | scheme `http://` explicit | medium | Improve |
| `url.punycode` | host chứa `xn--` bất ngờ (mixed-script) — low-confidence, wording "review" | medium | Improve |
| `url.ip-login` | host là IP literal | low | Maintain |
| `maintenance.stale` | không update/review lâu (dùng `RotationStatus` baseline; ngưỡng 4 năm như copy proposal) — **Info ONLY**, không phạt score trừ khi kèm weak/reused/leaked | info | Maintain |
| `maintenance.missing-metadata` | login thiếu URL hoặc thiếu username | info | Maintain |

Ràng buộc wording (proposal Module F + §11): không "Danger" cho password cũ; không "Unsafe
website"; domain check chỉ mức normalize/format, KHÔNG reachability/TLS scan.

## Chi tiết đáng chú ý

- **Normalize host**: dùng chung một `DomainNormalizer` (lowercase, strip `www.`, registrable
  domain heuristic như `TwoFactorCatalog` đang làm) — extract từ catalog ra util dùng chung.
- **Conflict detection** chạy trên login items chưa trash; escape hatch: 2 items cùng domain
  nhưng username khác nhau KHÔNG phải conflict.
- **Duplicate fingerprint**: sorted itemID pair + ruleID — xoá 1 item → finding resolve tự nhiên
  ở lần audit sau (status transition phase 05).
- Orphan checks cần đọc AttachmentStore + PasskeyRecord — snapshot builder (phase 01) bổ sung
  các cột này, vẫn giữ nguyên tắc metadata-only.

## Files

- **Tạo:** `Rules/DuplicateRules.swift`, `Rules/IncompleteItemRule.swift`,
  `Rules/InvalidTOTPRule.swift`, `Rules/OrphanedDataRule.swift`, `Rules/URLHygieneRules.swift`,
  `Rules/StaleCredentialRule.swift`, `VaultifyCore/Audit/DomainNormalizer.swift`
- **Sửa:** snapshot builder (thêm attachments/passkey refs/custom field keys), rule registry.

## Todo

- [ ] DomainNormalizer + tests (unicode, punycode, port, subdomain)
- [ ] 6 file rules + đăng ký registry
- [ ] Unit tests mỗi rule: positive/negative/edge (item trash, empty vault, import dup)
- [ ] Localize title/detail keys EN+VI cho mọi ruleID
- [ ] `make check`

## Success criteria

Vault seed test (fixtures) ra đúng bộ finding kỳ vọng; không false positive trên vault sạch;
stale không bao giờ xuất hiện ở Act now.
