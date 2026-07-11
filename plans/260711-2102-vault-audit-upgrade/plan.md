# Vault Audit — nâng cấp Watchtower thành Security Audit có cấu trúc

**Ngày:** 2026-07-11 · **Branch:** `feat/vault-audit` · **Trạng thái:** IMPLEMENTED (chờ review + commit)

## Mục tiêu

Biến Watchtower (4 check rời rạc, score 0-100 hiển thị ×10) thành **Vault Audit**: rule engine
deterministic, finding model có fingerprint/status, score 1000 điểm 6 pillar giải thích được,
audit flow (preflight → running → result), remediation queue, audit history, HIBP incremental,
capability catalog (passkey/2FA opportunities). Scope = proposal V1.0 + V1.1 + V1.2.

## Quyết định đã chốt (user, 2026-07-11)

| # | Quyết định | Giá trị |
|---|-----------|---------|
| D1 | Scope | Full V1.0 → V1.2 (local engine + HIBP upgrade + capability catalog). V1.3 email-breach NGOÀI scope |
| D2 | Naming | UI đổi: tab **Security**, action **Vault Audit**, kết quả **Vault Health**. Code giữ prefix `Watchtower*` |
| D3 | Persistence | SwiftData record mới trong vault store, sealed payload, **CÓ sync CloudKit** (LWW updatedAt) |
| D4 | Strength engine | **zxcvbn-lite tự viết** thuần Swift trong VaultifyCore, thay `PasswordStrength.entropyBits` |

## Phases

| Phase | Nội dung | Phụ thuộc | Status |
|-------|----------|-----------|--------|
| [01](phase-01-audit-engine-core-finding-model.md) | Finding model + rule protocol + AuditCoordinator + migrate 4 check hiện có | — | ✅ |
| [02](phase-02-zxcvbn-lite-strength-engine.md) | zxcvbn-lite strength engine + context checks + rewire toàn app | — | ✅ |
| [03](phase-03-integrity-hygiene-rules.md) | Rules: duplicates, conflicts, incomplete, invalid OTP, URL hygiene, stale | 01 | ✅ (trừ OrphanedDataRule — xem Deviations) |
| [04](phase-04-scoring-engine-1000.md) | ScoringEngine 1000 điểm 6 pillar + safeguards | 01,02,03 | ✅ |
| [05](phase-05-audit-persistence-cloudkit-sync.md) | AuditReportRecord + FindingStateRecord, sealed, CK sync | 01 | ✅ |
| [06](phase-06-hibp-incremental-upgrade.md) | HIBP: prefix-group, bounded concurrency, cancellable, cache device-local | 01,05 | ✅ (on-save hook dời — xem Deviations) |
| [07](phase-07-audit-flow-ui.md) | UI: rename Security, preflight/running/result, ring 1000 thật, Act now/Improve/Maintain | 04,05,06 | ✅ |
| [08](phase-08-remediation-finding-detail.md) | Fix queue, finding detail, ignore/accepted-risk, score delta verify-first | 07 | ✅ |
| [09](phase-09-audit-history.md) | Audit history screen (list + diff resolved/new) | 05,07 | ✅ |
| [10](phase-10-capability-catalog.md) | ServiceCapabilityCatalog (passkey/2FA/settings URL), versioned JSON | 01 | ✅ (embed Swift thay JSON — xem Deviations) |
| [11](phase-11-qa-design-dna-docs.md) | Tests tổng, Design DNA sweep, localization audit, docs update | tất cả | 🔶 (device QA + DNA sweep thủ công còn nợ) |

## Deviations (so với plan gốc)

1. **Adapter VaultHealth (P01):** giữ nguyên `PasswordAudit.analyze` sync cho Home/Search thay vì
   adapter async qua coordinator — tránh asyncify call sites; parity đảm bảo bằng test so sánh
   trực tiếp rule output vs legacy. Legacy vẫn dùng engine strength mới.
2. **Wordlists (P02):** embed Swift array (~450 common passwords + ~350 words EN/VI) thay binary
   resource 30k — tránh resource plumbing 2 target; matchers gánh long tail. KAT pass đủ các case
   proposal nêu (Password1!, qwerty123, Summer2026...).
3. **OrphanedDataRule (P03):** BỎ V1 — snapshot chưa có attachment/passkey linkage (PasskeyRecord
   không có itemID plaintext). Passkey linkage cho auth rules suy từ relyingParty↔host ở
   controller. Bổ sung khi có cột linkage.
4. **Card-expiry/incomplete sâu (P03):** incomplete chỉ check login-without-credential; card
   expiry không nằm trong snapshot model.
5. **HIBP on-save hook (P06):** chưa gắn vào editor save; cache warm chạy qua full audit.
6. **Capability catalog (P10):** embed Swift versioned thay file JSON bundled (cùng semantics,
   `fingerprintMarker` = "capability-catalog-v1" tham gia fingerprint).
7. **Fix queue actions (P08):** [Generate replacement] thay bằng [Edit item] (generator nằm sẵn
   trong editor); duplicate không trash trực tiếp từ queue — đi qua ItemDetail.
8. **PolarisModal:** không tồn tại trong repo iOS (convention của project Flutter) — dùng
   `confirmationDialog` chuẩn SwiftUI.

## Code review (2026-07-11, code-reviewer subagent — DONE_WITH_CONCERNS, đã xử lý)

Đã fix ngay trong đợt này: (1) engine chạy MainActor do Approachable Concurrency →
`Task.detached`; (2) `eraseEverything()` wipe thêm `AuditLocalCache` (file + Keychain secret);
(3) `secretMarker` chuyển HMAC theo khóa dẫn xuất từ Vault Key (fix TRƯỚC khi deploy CK schema —
đổi sau sẽ reset toàn bộ dismissals); (4) cancel audit khi lock + fresh-key check trước save;
(5) context-echo không double-fire quality.weak; (6) StrengthScreen cache @State; (7) meter bits
từ log10Guesses; (8) catalog longest-suffix match. Chi tiết:
`plans/reports/from-code-reviewer-to-orchestrator-260711-2102-vault-audit-review-report.md`.

## Còn nợ (theo dõi ở phase 11)

- Device QA thủ công: light/dark, Reduce Motion/Transparency, Dynamic Type, VI-longest, ring intro
  trên iOS 26.3 sim + device thật.
- CloudKit dashboard: deploy schema 2 record type mới (`AuditReport`, `AuditFindingState`) lên
  production TRƯỚC khi TestFlight build bật sync.
- HIBP on-save incremental hook (deviation 5).
- Home/Search migrate hẳn sang AuditReport summary (đang dùng legacy quick stats).
- Review nits low-priority chưa làm: `titleKey` dead field trên AuditFinding; history ForEach id
  theo completedAt (collision hiếm); `try? save` nuốt lỗi persist; retry HIBP cả với 4xx; vài
  literal size 44/40/160 chưa token-hóa; Calendar.current timezone nit.

Thứ tự thi công: 01 → 02+03 (song song) → 04 → 05 → 06 → 10 → 07 → 08 → 09 → 11.
Phase 10 độc lập, chỉ cần 01; xếp trước 07 để UI có đủ finding nguồn.

## Kiến trúc tổng

```
VaultAuditSnapshot (từ items đã decrypt, không persist plaintext)
   → AuditCoordinator (nonisolated, bounded Task)
       → local rules (strength, reuse, duplicate, integrity, age, capability)
       → network rules (HIBP pwned range) — optional, offline vẫn ra kết quả partial
   → [AuditFinding] (fingerprint ổn định, không chứa plaintext)
   → ScoringEngine → AuditReport (score 1000, 6 pillar)
   → persist metadata (AuditReportRecord sealed + FindingStateRecord) → CK sync
```

Layout code: engine + models trong `VaultifyCore/Audit/` (dùng được cho cả extension nếu cần
sau này); UI trong `Vaultify/Features/Watchtower/`; service network trong
`Vaultify/Services/Watchtower/`.

## Ngoài scope (chốt theo proposal §19-20)

- V1.3 email breach lookup (cần HIBP paid API + consent flow riêng)
- Similar-password detection, domain reachability/TLS scan, phishing verdict
- Auto-change password, AI advice, fake scan animation
- KHÔNG phạt score vì "password cũ" đơn thuần (NIST), KHÔNG claim "secure"

## Rủi ro chính

1. **CK sync record type mới** — phải theo đúng LWW pattern (`updatedAt` gate, changeTag no-op,
   dirty re-push); quên bump `updatedAt` khi đổi cột synced = mất data khi pull (bài học cũ).
2. **zxcvbn-lite đổi kết quả strength toàn app** — Generator/Editor/Home đều đổi phân loại;
   cần KAT tests + snapshot so sánh trước/sau để chủ động biết diff.
3. **Score 1000 thật thay ring ×10** — band thresholds đổi (800/500 thay 80/50), giữ nguyên
   choreography gauge PR #81.
4. **Fingerprint ổn định** — sai cách băm là mọi finding thành "mới" sau mỗi scan, phá status.

## Câu hỏi chưa chốt

- Remote refresh cho capability catalog (weekly fetch) hay chỉ ship theo app update? Phase 10
  mặc định: bundled + cấu trúc versioned sẵn, remote fetch để stretch.
- Home quick stats (`VaultHealth`) migrate sang AuditReport ngay hay giữ adapter? Phase 1 mặc
  định giữ adapter, migrate ở phase 07.
