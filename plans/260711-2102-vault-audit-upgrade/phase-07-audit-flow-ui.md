# Phase 07 — UI: rename Security, audit flow, ring 1000, nhóm Act now/Improve/Maintain

**Priority:** P0 · **Status:** ☐ · **Ước lượng:** 2-3 ngày · **Phụ thuộc:** 04, 05, 06 (10 nên xong trước)

## Naming (D2)

User-facing đổi, code prefix `Watchtower*` GIỮ:
- Tab label + accessibility (`VaultTab`): "Watchtower" → **Security** (VI: "Bảo mật")
- Header screen: **Security**; score block: **Vault Health**; CTA: **Run Vault Audit**
  (VI đề xuất: "Kiểm tra kho lưu trữ" — chốt khi làm xcstrings, design cho label VI dài nhất)
- Mọi string mới vào `Localizable.xcstrings` EN+VI; titles `LocalizedStringResource` dùng
  `.inAppLocalized`; copy KHÔNG "!", "—", "·" (design-dna-standard).

## Cấu trúc màn hình (proposal §3, §16)

```
WatchtowerScreen (Security overview — sửa)
├─ VaultHealth block: ring 1000 THẬT + band + "Last audited N days ago"
│    + confidenceNote nếu vault nhỏ. Tap ring → Why this score (pillar breakdown)
├─ [Run Vault Audit] CTA (primary)  /  [Continue fixing] nếu còn issue open
├─ Act now (critical+high)   ┐ 3 section card, mỗi finding 1 row
├─ Improve (medium)          ├ (thay 4 category row hiện tại)
├─ Maintain (low+info)       ┘ collapsed mặc định nếu >5
├─ HIBP toggle card (giữ, thêm link "How it works" sheet)
└─ Audit History link (phase 09)
Screens mới (push trong NavigationStack watchtowerPath hiện có):
├─ AuditPreflightScreen  — checklist sẽ review + privacy note + [Start Audit]
├─ AuditRunningScreen    — stage list THẬT từ coordinator progress, "N of M items",
│                          Cancel (cancel → không ghi report)
├─ AuditResultScreen     — score, delta vs report trước, N important + M improvements,
│                          estimated fix time (sum static), [Fix important issues] [View full report]
├─ AuditFullReportScreen — Reviewed/Important/Improve/Healthy sections (proposal §16)
└─ WhyThisScoreScreen    — 6 pillar bar (earned/max), giải thích 1 câu mỗi pillar
```

- KHÔNG fake scan: local rules xong trong <1s thì stage tick nhanh thật; chỉ HIBP là stage
  chạy lâu. Reduce Motion: bỏ stagger.
- Ring: bỏ nhân ×10 (`WatchtowerScoreRing.swift:130`), nhận 0-1000, band ngưỡng 800/500,
  GIỮ nguyên choreography intro + IntroGate. Score delta chỉ animate sau khi RE-AUDIT xác
  nhận (verify-first, không optimistic).
- `UIStateStore.watchtowerPath`: thêm route enum mới (state restoration tự theo).
- Empty vault / all-clear states giữ, cập nhật copy ("Excellent vault health", không "secure").
- Category drill-down cũ (`WatchtowerCategoryScreen`) thay bằng finding-group screens; strength
  screen giữ, đổi 5 grade.
- Home quick stats: migrate từ `VaultHealth` adapter sang `latestReport` summary (gỡ adapter
  phase 01). Search operators (`is:weak`…) rewire sang engine mới.

## Files

- **Sửa:** `WatchtowerScreen.swift` (viết lại phần content), `WatchtowerScoreRing.swift`,
  `WatchtowerComponents.swift`, `WatchtowerStrengthCard/Screen`, `VaultTabItem/MainTabView`
  (label), `HomeScreen`, `SearchOperators`, `UIStateStore`
- **Tạo:** `Features/Watchtower/AuditPreflightScreen.swift`, `AuditRunningScreen.swift`,
  `AuditResultScreen.swift`, `AuditFullReportScreen.swift`, `WhyThisScoreScreen.swift`,
  `AuditFindingGroupSection.swift` (mỗi file <200 dòng, tách components)
- `Localizable.xcstrings` — toàn bộ copy proposal §22 EN+VI.

## Todo

- [ ] Rename UI strings + tab (EN+VI, VI-longest layout check)
- [ ] Ring re-map 1000 + band mới, giữ intro
- [ ] 5 screen mới + 3-group overview + wiring coordinator progress
- [ ] Cancel path + offline partial state UI
- [ ] Verify: light+dark, Reduce Motion/Transparency, increased contrast, 44pt targets,
  design-dna checklist từng screen
- [ ] `make check`

## Success criteria

Flow Run Audit → Result → báo cáo đầy đủ chạy thật trên sim; tab đổi tên; không còn score ×10;
mọi string có VI.
