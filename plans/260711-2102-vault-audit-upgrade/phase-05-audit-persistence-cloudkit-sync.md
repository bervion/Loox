# Phase 05 — Persistence: AuditReportRecord + FindingStateRecord, CloudKit sync

**Priority:** P0 · **Status:** ☐ · **Ước lượng:** 1.5-2 ngày · **Phụ thuộc:** 01

## Context (verified)

- Store: SwiftData `VaultStore` (`VaultifyCore/Store/VaultStore.swift`), `cloudKitDatabase: .none`,
  sync THỦ CÔNG qua `CloudSyncService` per record type ("VaultItem", Folder, Persona, Alias,
  Inbox). LWW 2 gate: content theo `updatedAt`, meta theo `metaUpdatedAt`; `ckChangeTag`
  short-circuit; local-win → re-mark `dirty`.
- Bài học đã ghi memory: **cột synced đổi mà không bump `updatedAt` = bị drop khi pull.**
- Quyết định D3: sealed payload, per-persona, CÓ sync CloudKit.

## Thiết kế

### 2 record type mới (`VaultifyCore/Store/`)

```swift
@Model final class AuditReportRecord {      // 1 dòng / lần audit HOÀN TẤT
    var id: String                          // UUID string
    var personaID: String?
    var sealed: Data                        // AuditReportPayload mã hoá Vault Key (JSON):
                                            //   score, pillars, counts, ruleVersions,
                                            //   findingFingerprints (open/resolved/new)
    var completedAt: Date
    var createdAt: Date; var updatedAt: Date
    var dirty: Bool; var ckChangeTag: String?
}
@Model final class FindingStateRecord {     // trạng thái user cho 1 fingerprint
    var id: String                          // = fingerprint (hex) — natural key, idempotent merge
    var personaID: String?
    var sealed: Data                        // payload: status, ignoreReason, ruleID, ruleVersion
    var status: String                      // plaintext CHỈ enum status (không lộ nội dung finding)
    var createdAt: Date; var updatedAt: Date
    var dirty: Bool; var ckChangeTag: String?
}
```

Nguyên tắc dữ liệu (proposal §10): KHÔNG lưu password/hash/HIBP suffix/raw API response ở bất kỳ
record nào. Fingerprint là SHA-256 không đảo được và không chứa plaintext (phase 01).

- Immutable-ish semantics: report là append-only (không sửa sau khi ghi) → sync đơn giản, không
  conflict thực; LWW theo `updatedAt` vẫn áp dụng cho an toàn. Retention: giữ tối đa 50
  report/persona, prune cũ (cả local lẫn CK delete tombstone theo pattern hiện có).
- FindingState: đổi status → bump `updatedAt` + `dirty = true` (bắt buộc, xem bài học trên).
  Rule version tăng hoặc dữ liệu đổi → coordinator hạ status về `needsRecheck` (ghi mới).

### CloudSyncService

- Thêm `auditReportRecordType = "AuditReport"`, `findingStateRecordType = "AuditFindingState"`
  cùng zone với VaultItem; push/pull theo pattern hiện có (fields: sealed, personaID,
  completedAt/status, updatedAt; changeTag).
- Chỉ chạy khi `iCloudSyncEnabled` (vault-item sync flag) — audit data là vault data, KHÔNG
  dính `approvalModeEnabled` (ADR-2).
- Eraser: thêm 2 model vào `makeContainer` + `eraseAll`.

### HIBP cache — DEVICE-LOCAL, không sync (chuẩn bị cho phase 06)

`AuditLocalCache` (file sealed trong App Group, KHÔNG vào CK): map
`HMAC-SHA256(localSecret, password)` → `(pwnedCount, checkedAt)`. `localSecret` random per
device trong Keychain. Lý do không sync: cache chứa tín hiệu về password; per-device rẻ và an
toàn hơn.

## Files

- **Tạo:** `VaultifyCore/Store/AuditReportRecord.swift`, `FindingStateRecord.swift`,
  `VaultifyCore/Audit/AuditReportPayload.swift` (Codable + seal/unseal helpers theo pattern
  sealed hiện có), `Vaultify/Services/Watchtower/AuditLocalCache.swift`
- **Sửa:** `VaultStore.swift` (container, eraseAll, upsertFromRemote overloads cho 2 type),
  `CloudSyncService.swift` + `SyncPushService`/`ZoneDeltaSyncHelper` nếu cần đăng ký type.

## Todo

- [ ] 2 @Model + payload seal/unseal + retention prune
- [ ] AuditStore API: `saveReport`, `latestReport(persona:)`, `history(persona:)`,
  `state(fingerprint:)`, `setState(…)` (bump updatedAt+dirty)
- [ ] CK push/pull + LWW + changeTag cho 2 type; tombstone delete
- [ ] Status lifecycle trong coordinator: open → resolved (fingerprint biến mất sau re-audit) /
  noLongerMonitored (item xoá) / needsRecheck (ruleVersion đổi); ignored/acceptedRisk chỉ user set
- [ ] Tests: merge LWW (2 device đổi status), changeTag no-op, needsRecheck khi bump version,
  eraseAll sạch, payload không chứa secret (grep assertion trên JSON)
- [ ] `make check` + chạy `VaultifyTests` (lưu ý CKContainer trap trong test host — dùng pattern
  test hiện có)

## Success criteria

Report/status sống qua restart, sync 2 chiều đúng LWW, không plaintext nhạy cảm trong bất kỳ
record/CK field nào.
