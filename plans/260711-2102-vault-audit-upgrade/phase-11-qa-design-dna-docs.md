# Phase 11 — QA tổng, Design DNA sweep, localization audit, docs

**Priority:** P0 (gate trước ship) · **Status:** ☐ · **Ước lượng:** 1 ngày · **Phụ thuộc:** tất cả

## Test tổng

- [ ] `make test DEST=<sim UDID>` toàn bộ VaultifyTests pass (nhớ CKContainer trap trong test
  host — theo pattern hiện có)
- [ ] Integration: seed vault fixture 50 items (weak/reused/dup/leaked-mock/OTP hỏng) → run
  full audit → assert findings + score + persist + re-run resolved diff
- [ ] Perf: full local audit 500 items < 2s off-main, UI không khựng (Instruments spot check)
- [ ] Sync: 2 store giả lập push/pull FindingState + Report, LWW đúng, erase sạch
- [ ] Cancellation + offline matrix: local-only, HIBP fail giữa chừng, cancel ở mỗi stage

## Design DNA / UX sweep (docs/design-dna-standard.md — bắt buộc)

- [ ] Từng screen mới qua adversarial checklist: light+dark, Reduce Motion, Reduce
  Transparency, increased contrast, Dynamic Type lớn, VI-longest labels
- [ ] Copy audit: không "!", "—", "·"; không claim "secure"/"safe" tuyệt đối; wording
  "not saved in Loox" đúng chỗ; haptics vocabulary cho audit complete / issue resolved
- [ ] Icons Polaris SVG only; token-driven (Space/Radius/Metric/Motion/vaultType), không
  hardcode; hit target 44pt
- [ ] Ring intro giữ nguyên cảm giác PR #81 trên iOS 26.3 sim + device thật (glass traps đã ghi memory)

## Localization audit

- [ ] Script grep string literals mới trong Features/Watchtower + VaultifyCore/Audit → đối
  chiếu `Localizable.xcstrings` đủ cặp EN+VI (VI thiếu = bug)

## Docs (documentation-management)

- [ ] `docs/codebase-summary.md`: mục Vault Audit (engine, store records, sync types mới)
- [ ] `docs/design-guidelines.md`: pattern screen audit flow nếu có component mới tái dùng
- [ ] `docs/project-changelog.md` + roadmap status
- [ ] `README.md` feature list

## Ship checklist

- [ ] `make check` cả 2 target, lint sạch
- [ ] Conventional commits, không AI reference; PR mô tả map phase → commit
- [ ] Nhắc user: CK record type mới ("AuditReport", "AuditFindingState") cần deploy schema
  CloudKit dashboard production trước khi release TestFlight build bật sync

## Success criteria

Tests xanh, DNA checklist pass từng screen, docs sync, sẵn sàng `/ck:ship`.
