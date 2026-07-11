# Phase 01 — Audit engine core: finding model, rule protocol, coordinator

**Priority:** P0 (nền của mọi phase sau) · **Status:** ☐ · **Ước lượng:** 1-1.5 ngày

## Context

- Hiện tại: `Vaultify/Services/Watchtower/PasswordAudit.swift` — `analyze()` monolithic, trả
  `VaultHealth` (4 mảng issue + score 0-100). `VaultIssue.id = UUID()` mỗi lần scan → không
  track được status.
- Consumer hiện có: `WatchtowerScreen`, `WatchtowerCategoryScreen/Components/StrengthScreen`,
  `HomeScreen`, `SearchScreen`/`SearchOperators`.

## Thiết kế

Tạo `VaultifyCore/Audit/` (mọi type `nonisolated`, `Sendable` — chạy off-main):

```swift
// AuditFinding.swift
enum AuditSeverity: Int, Codable { case info, low, medium, high, critical }
enum AuditCategory: String, Codable { case exposure, quality, reuse, authentication, integrity, maintenance }
enum FindingStatus: String, Codable { case open, resolved, ignored, acceptedRisk, noLongerMonitored, needsRecheck }
enum RemediationType: String, Codable { case changePassword, removeDuplicate, reviewItem, addTOTP, addPasskey, fixData }

struct AuditFinding: Identifiable, Sendable {
    let id: UUID                    // ephemeral, UI identity
    let ruleID: String              // "reuse.exact", "exposure.leaked"…
    let ruleVersion: Int
    let severity: AuditSeverity
    let category: AuditCategory
    let affectedItemIDs: [String]
    let fingerprint: String         // hex SHA-256, xem dưới
    let titleKey: String            // key localization, KHÔNG hardcode text
    let detail: String?             // đã localize sẵn khi build ("Used by 4 items")
    let remediation: RemediationType
    let estimatedFixSeconds: Int    // static per rule (proposal §4)
    let detectedAt: Date
}
```

**Fingerprint** = SHA-256(`ruleID` + `ruleVersion` + sorted `affectedItemIDs` + salient marker).
Salient marker per rule: reuse group → SHA-256 riêng của password (KHÔNG lưu, chỉ vào hash);
weak → không cần; duplicate → cặp itemID đủ. KHÔNG bao giờ đưa plaintext vào fingerprint lưu trữ.

```swift
// AuditRule.swift
protocol AuditRule: Sendable {
    var id: String { get }
    var version: Int { get }
    var category: AuditCategory { get }
    var requiresNetwork: Bool { get }   // tách local/network (proposal §9)
    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding]
}
```

```swift
// VaultAuditSnapshot.swift — minimal, không giữ live DB (proposal §10)
struct VaultAuditItem: Sendable {
    let id: String; let category: ItemCategory; let title: String
    let usernames: [String]; let password: String?      // chỉ sống trong scope audit task
    let normalizedDomains: [String]; let rawURLs: [String]
    let hasTOTP: Bool; let totpSecret: String?; let hasPasskey: Bool
    let createdAt: Date; let updatedAt: Date; let lastUsedAt: Date?
    let rotateDays: Int; let passwordChangedAt: Date?
    let isTrashed: Bool
}
struct VaultAuditSnapshot: Sendable { let items: [VaultAuditItem]; let personaID: String? }
```

```swift
// AuditCoordinator.swift
// - registry [AuditRule], chạy local rules trước, network rules sau (skippable)
// - progress callback theo stage (cho Running screen phase 07): (stage, completed, total)
// - cancellable: Task cancellation check giữa các rule; cancel → KHÔNG ghi report
// - output: AuditRunResult { findings, startedAt, completedAt, onlineChecksCompleted }
```

## Migrate 4 check hiện có thành rules

| Rule mới | Nguồn logic cũ | Severity |
|----------|----------------|----------|
| `quality.weak` (PasswordStrengthRule) | `PasswordStrength.evaluate` (phase 02 nâng engine, phase này wrap engine cũ) | very-weak→critical, weak→high, fair→info (proposal Module B) |
| `reuse.exact` (PasswordReuseRule) | counts dict trong `analyze()` — chuyển sang **group finding** (1 finding/group, không phải 1/item) | high; medium nếu 2 items thường |
| `auth.totp-missing` (TwoFactorRule) | `TwoFactorCatalog.supports2FA` | info/low — wording "not saved in Loox" |
| `exposure.leaked` (PwnedPasswordRule) | `HIBPService` (naive; phase 06 nâng) | critical nếu leaked+reused, high nếu leaked |

## Files

- **Tạo:** `VaultifyCore/Audit/AuditFinding.swift`, `AuditRule.swift`, `VaultAuditSnapshot.swift`,
  `AuditCoordinator.swift`, `Rules/PasswordStrengthRule.swift`, `Rules/PasswordReuseRule.swift`,
  `Rules/TwoFactorRule.swift`; `Vaultify/Services/Watchtower/Rules/PwnedPasswordRule.swift`
  (network, app-only).
- **Sửa:** `PasswordAudit.swift` — giữ làm adapter: `analyze()` gọi coordinator local rules rồi
  map về `VaultHealth` (Home/Search không vỡ). Đánh dấu migrate hẳn ở phase 07.
- **Move `TwoFactorCatalog`** sang `VaultifyCore/Audit/` (phase 10 mở rộng).
- Chạy `tuist generate` sau khi thêm file (globbed sources).

## Todo

- [ ] Models + protocol + coordinator (nonisolated, Sendable, bounded task)
- [ ] Snapshot builder từ `[VaultItem]` (map passwordField/totpField/websites/rotate metadata)
- [ ] 4 rule migrate + fingerprint từng rule
- [ ] Adapter `VaultHealth` giữ Home/Search hoạt động
- [ ] Unit tests: fingerprint stability (2 lần scan cùng data → cùng fingerprint; đổi 1 item →
  chỉ finding liên quan đổi), reuse grouping, cancellation không ghi report
- [ ] `make check` compile cả 2 target

## Success criteria

Audit chạy qua coordinator ra kết quả giống hệt logic cũ (parity test), fingerprint ổn định,
UI hiện tại không đổi hành vi.
