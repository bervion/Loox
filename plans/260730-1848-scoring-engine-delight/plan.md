# Scoring engine: điểm số thú vị hơn thang x1000 phẳng

- **Status:** proposed (owner yêu cầu 260730, PR #189)
- **Scope:** cách TÍNH và TRÌNH BÀY điểm Vault Health — không đổi rule engine, không đổi finding.
- **Owner decision cần trước khi code:** chọn Option B (đề xuất) hay A/C; duyệt bảng band mới.

## Hiện trạng

`ScoringEngine.report` cộng thẳng 6 pillar, max cố định (`ScoringWeights`):
exposure 300 · quality 220 · reuse 180 · auth 140 · integrity 100 · maintenance 60 = **1000**.
Band 800/500 → "Fairly secure / Needs attention / At risk". Điểm lưu trong
`AuditReportPayload.score` (sealed, có history + diff).

Vấn đề owner nêu: tổng-cộng-đến-1000 đọc như bài kiểm tra, không có cảm giác
"đạt chuẩn rồi vẫn còn thứ để với tới" như 1Password (score của 1P vượt 1000 —
1001/1002 — nhờ điểm thưởng).

## Nguyên tắc (giữ từ thiết kế hiện tại)

1. **Giải thích được**: điểm luôn = tổng các phần nhìn thấy trong Why This Score.
2. **Verify-first**: điểm chỉ đổi khi audit hoàn tất.
3. **So sánh được theo thời gian**: history/diff không được gãy khi công thức đổi.

## Options

### A — Giữ 0-1000, thêm curve

Điểm thô qua curve lũy tiến (điểm cao khó nhích hơn). Rẻ nhất, nhưng không có
"vượt 1000", không giải quyết cảm giác phẳng. Không đề xuất.

### B — Base 0-1000 + Bonus vượt trần (đề xuất)

Giữ nguyên 6 pillar = **base**. Thêm lớp **bonus 0-100** cho những thứ VƯỢT
chuẩn — chỉ cộng khi base ≥ 800 (chuẩn phải đạt trước khi thưởng):

| Bonus | Điều kiện | Điểm |
|---|---|---|
| Passkey adoption | ≥1 passkey đang dùng / mỗi 25% item eligible có passkey | +10…+30 |
| Two-factor đủ phủ | 100% item mà site hỗ trợ 2FA đã có TOTP | +25 |
| Zero reuse | không còn cặp mật khẩu trùng nào | +20 |
| Audit đều tay | 3 audit liên tiếp trong cadence 14 ngày | +15 |
| Extra Protection | ≥1 field sealed L2 | +10 |

Trần hiển thị **1100**. Ring: fraction = score/1100; vượt 1000 đổi trạng thái
hiển thị (band "Fantastic", tick vàng/hologram — TBD design). Band mới:

| Điểm | Band |
|---|---|
| ≥ 1000 | Fantastic (mới — chỉ đạt được nhờ bonus) |
| 800–999 | Fairly secure |
| 500–799 | Needs attention |
| < 500 | At risk |

Vì sao B: đúng cái owner chỉ ("lên tới 1001"), mọi bonus đều là hành vi bảo mật
THẬT (không gamification rỗng), và base không đổi nên history so sánh được.

### C — Đổi hẳn sang thang chữ (A+/A/B…)

Đọc nhanh nhưng mất tính liên tục của history, mất "con số để khoe" (Share My
Score). Không đề xuất.

## Impact map (Option B)

- `VaultifyCore/Audit/ScoringEngine.swift` — thêm `bonus: [BonusAward]` vào report; `score = base + bonus` (bonus 0 khi base < 800).
- `AuditReportPayload` — thêm field `bonus` (optional, decode-tolerant: payload cũ đọc bonus = 0, KHÔNG migrate).
- `WhyThisScoreScreen` — section "Bonus" liệt kê từng award (đạt/chưa, còn thiếu gì).
- `WatchtowerScoreRing` — `targetFraction` /1100; trạng thái ≥1000.
- `AuditHistoryDiff` — diff hiển thị base/bonus tách nhau để đổi công thức không đọc thành "score tụt".
- Tests: `ScoringEngine` bonus gating (base<800 → 0), payload back-compat, band thresholds.
- Dữ liệu cần thêm: passkey coverage (đã có `passkeyItemIDs` trong snapshot), audit streak (đọc từ history plaintext `completedAt`), L2 fields (snapshot đã thấy `isExtraProtected`).

## Phases

1. **Spec + copy** — chốt bảng bonus với owner; EN/VI/JA cho band "Fantastic" + tên các bonus. (0.5d)
2. **Engine** — BonusAward + gating + payload field + tests. (1d)
3. **UI** — Why This Score section bonus; ring 1100 + trạng thái Fantastic; history diff tách base/bonus. (1-1.5d)
4. **Polish** — motion khoảnh khắc vượt 1000 (một lần mỗi lần vượt, tôn trọng Reduce Motion), copy khoe điểm. (0.5d)

## Rủi ro

- Bonus dễ bị đọc thành "điểm ảo" → mọi award phải mở được ra hành vi cụ thể trong Why This Score.
- Ring fraction đổi mẫu số → ảnh chụp cũ/screenshot marketing lệch; chấp nhận.
- Đừng để bonus che base tụt: diff phải tách 2 dòng.

## Câu hỏi chờ owner

1. Chốt Option B? Trần 1100 hay 1050?
2. "Fantastic" giữ tiếng Anh hay dịch (VI "Tuyệt hảo"?) — Share My Score dùng chữ này.
3. Audit streak có đáng làm ngay (cần đọc history) hay để phase sau?
