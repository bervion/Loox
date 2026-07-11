# Design DNA audit — các screen Vault Audit mới — 260711

Chuẩn: `docs/design-dna-standard.md` (adversarial protocol). Exemplar idiom:
`QuickLinkResultView` (completion screen chuẩn: 1 primary + 1 tinted secondary, utility row
demoted, left-aligned top-anchored). Tất cả fix đã compile + 560/560 tests.

## Root cause "button to"

`ThemedProminentButtonStyle` TỰ SỞ HỮU typography (`vaultType(.headline)`), width
(`maxWidth: .infinity`) và height (`padding(.vertical, Space.s4)`). Các screen mới lại set
`.vaultType(.headline).frame(maxWidth: .infinity, minHeight: Metric.controlLarge)` TRONG label
→ padding chồng minHeight → button ~70pt thay vì ~50pt. Quy tắc rút ra: **label của themed
button style chỉ là `Text(...)` trần (+ `.frame(maxWidth: .infinity)` khi cần full-width)**.

## Findings per screen (protocol Q1-Q5) → fixes

### VaultAuditFlowScreen
- Q1 protagonist result = "điểm + việc tiếp theo" nhưng có 2 filled primary (Fix + Done) +
  1 bordered (View full report) = button wall, vi phạm DNA #7. → Fix: có issues thì Fix =
  primary duy nhất, Done = `.themedTinted`; không issues thì Done = primary; View full report
  demote thành inline disclosure link (accent subhead + chevron, hitMin).
- Q4 score block centered float → leading, baseline row `874 / out of 1000`.
- Start Audit / Cancel oversized label → Text trần; Cancel → `.themedTinted` pill.
- Running screen giữ centered (progress state hợp lệ), copy calm ✓.

### WatchtowerScreen (Security overview)
- Run Vault Audit label oversized + icon thừa → Text trần + `.themedProminent`.
- Continue fixing: bordered custom → `.themedTinted` (đúng rank primary/secondary kề nhau).

### AuditFixQueueScreen / FindingDetailView
- 4 button stacked (Open website + Edit item bordered controlMedium, Next issue oversized,
  Dismiss footnote) = button wall → Open/Edit thành `.themedCompact` utility pill row
  (idiom "occasional extras"), Next issue = primary duy nhất (Text trần), Dismiss = quiet
  subhead text (hitMin giữ).
- Completed state centered float + `minWidth: 160` + icon size 44 literal → top-anchored
  leading, icon `Metric.iconUtility`, Done full-width primary.

### WhyThisScoreScreen
- Score header centered → leading baseline row (khớp result screen). Pillar rows giữ.

### AuditHistoryScreen
- Empty state centered float + icon 40 literal → leading card cùng shape empty state của
  Security overview, icon `Metric.iconInline`.

### AuditFullReportScreen
- Pass: sections + stat rows leading, không button, tokens đúng. Không đổi.

## Không đổi (có lý do)
- Running screen centered: trạng thái chờ, protagonist là tiến độ.
- Bar height 6 trong PillarRow: khớp PasswordStrengthMeter hiện có (idiom sẵn).
- History row card 1 dòng: cùng shape strength card link hiện có.

## Còn nợ
- Verify bằng mắt trên sim iOS 26.3: light/dark, VI, Dynamic Type XL (đã nằm trong mục
  "Còn nợ" device QA của plan).
