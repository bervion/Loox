# Phase 02 — zxcvbn-lite: pattern-aware strength engine

**Priority:** P0 · **Status:** ☐ · **Ước lượng:** 1.5-2 ngày · **Phụ thuộc:** không (song song 01)

## Context

`Vaultify/DesignSystem/PasswordStrength.swift` chấm bằng character-class × length →
`Password1!` được chấm cao sai (proposal Module B). NIST: đối chiếu blocklist thay vì
composition rules. Consumer: Generator, ItemEditor, Watchtower strength screens, Home.

## Thiết kế

`VaultifyCore/Audit/Strength/` — thuần Swift, offline, deterministic, `nonisolated`:

```swift
enum PasswordGrade: Int, Sendable, Comparable { case veryWeak, weak, fair, strong, excellent }
struct StrengthResult: Sendable {
    let grade: PasswordGrade
    let log10Guesses: Double
    let matchedPatterns: [String]   // ["dictionary", "year", "keyboard"] — cho detail UI
}
enum PasswordStrengthEngine {
    static func evaluate(_ password: String, context: StrengthContext = .empty) -> StrengthResult
}
struct StrengthContext: Sendable {   // context-aware checks, chỉ dữ liệu trong vault
    let usernames: [String]; let emailLocalParts: [String]
    let domains: [String]; let itemTitle: String?
}
```

Matcher subset (đủ bắt lỗi phổ biến, không port full zxcvbn):

1. **Common-password dictionary** — top ~30k (xkcd/rockyou-derived public list), lưu dạng
   binary sorted (một file resource trong VaultifyCore, ~250-300KB), binary search. Kèm
   l33t-normalize trước khi tra (`P@ssw0rd` → `password`).
2. **Dictionary words** — english top 10k + tên phổ biến + **VN wordlist nhỏ** (tên, "matkhau",
   "bongda"…, tự curate ~2k).
3. **Sequences** (`abcdef`, `12345`, `98765`), **repeats** (`aaa`, `abcabc`), **keyboard
   patterns** (qwerty/qwertz rows, adjacency walk).
4. **Dates/years** (1900-2035, ddmmyyyy variants).
5. **Context match** — chứa username / email local-part / domain / title → cap grade ≤ weak.

Scoring: mỗi đoạn matched có guess estimate, non-matched dùng brute-force pool như cũ;
tổng log10 guesses → grade: <6 veryWeak, <8 weak, <10 fair, <12 strong, ≥12 excellent
(tinh chỉnh bằng KAT).

## Rewire

- `PasswordStrength` (weak/medium/strong) **giữ nguyên API** cho UI cũ, nhưng `evaluate()`
  delegate sang engine mới: veryWeak+weak→`.weak`, fair→`.medium`, strong+excellent→`.strong`.
  `hasWeakPassword` giữ hành vi (empty ≠ weak).
- `PasswordStrengthRule` (phase 01) dùng thẳng `PasswordGrade` 5 mức:
  veryWeak→critical, weak→high, fair→info (KHÔNG cảnh báo fair thành issue — proposal), kèm
  `quality.contains-context` finding riêng khi context match.
- Generator/Editor strength bar: map 5 grade → fraction (0.2/0.4/0.6/0.8/1.0), label mới
  localize EN+VI (Very weak/Weak/Fair/Strong/Excellent).

## Files

- **Tạo:** `VaultifyCore/Audit/Strength/PasswordStrengthEngine.swift`, `Matchers/…` (mỗi matcher
  1 file <200 dòng), `Resources/common-passwords.bin`, `Resources/dictionary-words.bin`,
  script sinh resource `scripts/generate-strength-wordlists.sh` (one-off, commit output).
- **Sửa:** `Vaultify/DesignSystem/PasswordStrength.swift` (delegate), Generator/Editor strength
  UI labels, `Localizable.xcstrings` (5 grade EN+VI).
- Resource nằm trong VaultifyCore glob — check Tuist resource handling cho cả 2 target
  (extension cũng compile VaultifyCore; nếu resource làm phình extension, gate bằng target
  membership trong `Project.swift`).

## Todo

- [ ] Engine + matchers + wordlist resources (kèm script sinh)
- [ ] KAT tests: bảng ~40 password mẫu → grade kỳ vọng (`Password1!`→weak, `Tr0ub4dor&3`→fair,
  diceware 5 từ→excellent, `qwerty123`→veryWeak, username-echo→≤weak…)
- [ ] Parity report: chạy cả engine cũ + mới trên bộ mẫu, ghi diff vào plans/reports/
- [ ] Perf test: 500 password < 100ms trên device class thấp (chạy off-main)
- [ ] Rewire PasswordStrength + UI labels EN+VI, `make check`

## Success criteria

`Password1!` không còn "Strong"; KAT pass; Generator/Editor vẫn chạy đúng; không regress perf.
