# Phase 02 — Extension Authoritative Gate COMPLETE (V2.1)

Priority: cao · Effort: 0.5 buổi · Depends: **P01 + P04** (đổi theo review P0-2)

## Scope split (review)
- **P02a — Reachability UX** (có thể land sớm sau P01): offline → shared rows disabled
  + lý do; `hasSatisfiedNetworkPath` từ P01; default coi như offline tới khi path
  satisfied (fail-closed).
- **P02b — Authoritative fill gate** (cần P04): NGAY TRƯỚC khi
  `completeRequest`/`completeAssertionRequest` với một shared entry → live grant verify
  qua CloudKit (INV-11), state taxonomy như app (offline / verificationUnavailable /
  revoked). Verify fail bất kỳ lý do gì → KHÔNG fill.
- **Release gate: chỉ ship production khi P02a + P04 + P02b đủ.** Reachability-only
  không được tuyên bố là "online gate" (nó chỉ là Layer A — INV-02).

## Files
- `VaultifyAutoFill/AutoFillView.swift` (gate cả 3 đường: list, preferredRecordID
  auto-select, passkey→password fallback), `OneTimeCodeView.swift` (shared TOTP),
  verify helper dùng chung từ core (P04 move).

## Success criteria
- Owner revoke → recipient extension (có mạng, cache còn entry) → chọn fill →
  verify fail → không điền, hiện "Chủ sở hữu đã thu hồi". Cached credential không có
  đường nào ra ngoài mà không qua verify.
- Airplane mode → owned items fill bình thường, shared entries disabled + lý do.

## Risks
- Verify thêm độ trễ ngay trước fill (~0.3–1s) — hiện spinner trên nút; timeout theo
  `SharedAccessTimingPolicy`, fail-closed thành `verificationUnavailable`.
