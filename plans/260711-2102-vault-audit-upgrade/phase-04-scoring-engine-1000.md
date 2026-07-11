# Phase 04 — ScoringEngine: 1000 điểm, 6 pillar, giải thích được

**Priority:** P0 · **Status:** ☐ · **Ước lượng:** 1 ngày · **Phụ thuộc:** 01, 02, 03

## Context

Score hiện tại: `1 - (weak+reused)/count` × 100, ring hiển thị ×10 (giả thang 1000,
`WatchtowerScoreRing.swift:130`). Thay bằng thang 1000 thật theo proposal §6-7.

## Thiết kế

`VaultifyCore/Audit/ScoringEngine.swift` + `AuditReport.swift`:

```swift
struct PillarScore: Sendable, Codable { let pillar: AuditPillar; let earned: Int; let max: Int }
enum AuditPillar: String, Codable, CaseIterable {
    case exposure        // 300
    case quality         // 220
    case reuseIsolation  // 180
    case authReadiness   // 140
    case integrity       // 100
    case maintenance     // 60
}
struct AuditReport: Sendable {
    let score: Int                 // sum pillars, 0…1000
    let pillars: [PillarScore]
    let findings: [AuditFinding]
    let analyzedItemCount: Int, uniquePasswordCount: Int, domainCount: Int
    let startedAt: Date, completedAt: Date
    let onlineChecksCompleted: Bool
    let ruleVersions: [String: Int]
}
```

Công thức (deterministic, mọi hằng số đặt tại một `ScoringWeights` struct, có comment):

- **Exposure 300**: base 300; mỗi unique leaked password −60; leaked+reused thêm −20 (2-3 items)
  / −40 (4+, cap). Phạt theo GROUP không theo item. Offline (HIBP chưa chạy) → pillar tính trên
  dữ liệu có, report gắn cờ `onlineChecksCompleted=false`, UI ghi "Online checks unavailable".
- **Quality 220**: weighted distribution theo share veryWeak/weak/fair/strong+ (không trừ vô
  hạn). Password đã leaked KHÔNG double-penalty nặng ở đây (giảm weight 50%).
- **Reuse isolation 180**: unique ratio + số group + largest group + reuse trên critical
  category (category weight tĩnh: email/finance/identity 1.5, cloud/dev 1.3, social 1.1…).
  Category suy từ domain qua bảng nhỏ trong `ScoringWeights` — không AI.
- **Auth readiness 140**: chỉ chấm **confirmed protection** (TOTP/passkey Loox đang giữ) mạnh;
  **available improvement** (catalog nói site hỗ trợ mà Loox chưa lưu) chỉ trừ nhẹ (proposal:
  không phạt chắc chắn vì "không có OTP trong Loox").
- **Integrity 100**: trừ theo count từng loại (conflict nặng hơn exact dup), cap sàn 0.
- **Maintenance 60**: last completed audit tuổi, unresolved critical còn open, missing metadata.

### Safeguards (proposal §7)

- Vault < 5 items: report kèm `confidenceNote` "Based on N items" — UI hiển thị, KHÔNG scale điểm.
- Xoá item liên quan finding → status `noLongerMonitored`, KHÔNG cộng "fixed"; score tính lại
  tự nhiên trên vault còn lại.
- Band label mới: ≥800 "Good/Fairly secure", 500-799 "Needs attention", <500 "At risk"
  (map từ `scoreBand(for:)` hiện tại — đổi ngưỡng, giữ role màu). Không copy "secure" tuyệt đối.

## Files

- **Tạo:** `VaultifyCore/Audit/ScoringEngine.swift`, `ScoringWeights.swift`, `AuditReport.swift`
- **Sửa:** `AuditCoordinator` output → `AuditReport`; `WatchtowerScoreRing` bỏ nhân ×10, nhận
  score 1000 thật + đổi ngưỡng band (UI wiring đầy đủ ở phase 07).

## Todo

- [ ] Engine + weights + report model
- [ ] Property tests: monotonic (fix 1 issue → score không giảm), bounded 0-1000, deterministic
  (cùng input → cùng output), không nhảy >150 điểm khi đổi 1 item (stability guard)
- [ ] Golden tests: 5 vault fixtures (rỗng, sạch, leaked+reused, dup-heavy, nhỏ 2 items) →
  score + pillar kỳ vọng ghi cứng
- [ ] `make check`

## Success criteria

Score giải thích được bằng pillar breakdown; golden tests khoá hành vi; không double-penalty
leaked ở Quality; auth readiness không phạt vắng OTP ngoài catalog.
