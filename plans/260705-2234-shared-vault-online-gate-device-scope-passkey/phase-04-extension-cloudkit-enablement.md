# Phase 04 — Extension CloudKit Enablement

Priority: trung bình (prereq P05 + verify đầy đủ của P02) · Effort: 0.5 buổi · Depends: —

## Overview
AutoFill extension hiện KHÔNG có CloudKit entitlement (TOTP ask-each-time phải deep-link
mở app). Passkey ask-each-time (P05) và live-grant verify trong extension (P02) cần
extension nói chuyện CloudKit trực tiếp.

## P04-0 — Entitlement verification preflight (thêm theo review P2-11)
Không tin `make check` — entitlement mismatch là loại bug "local Debug OK, CI archive
fail / TestFlight runtime fail". Script assert (chạy cả Debug lẫn archive):
```
codesign -d --entitlements :- <path>/VaultifyAutoFill.appex   # chứa iCloud container?
security cms -D -i embedded.mobileprovision                    # profile có entitlement?
```
Verify riêng cho development build VÀ TestFlight build (match regenerate cả hai).

## Steps
1. `Project.swift` + `VaultifyAutoFill.entitlements`: thêm iCloud container
   `iCloud.com.bervion.vaultify` + aps? (KHÔNG cần push trong appex — poll là đủ).
   Portal: bật iCloud capability cho bundle id `.autofill` + regenerate profiles (match).
2. Move phần request/response core của `ApprovalRecipientService` (build request ký device
   key, poll response, open sealed payload) xuống `VaultifyCore/Sharing/` để cả app lẫn
   extension dùng — app service còn lại là wrapper.
3. Đo memory footprint appex khi thêm CK stack (jetsam ceiling AutoFill khá thấp) — nếu
   sát trần, lazy-init CKContainer chỉ khi user chạm shared entry.
4. Fallback giữ nguyên: nếu CK lỗi trong extension → deep-link mở app như hiện tại.

## Success criteria
- Extension fetch được record trong shared zone (verify grant alive) trên máy thật.
- `make check` + match/CI vẫn sign được cả 2 target.

## Risks
- Provisioning (match) phải regenerate cho entitlement mới — làm trên máy dev trước khi CI.
- Memory: nếu vượt trần → P05 chuyển phương án deep-link-first (mở app approve, quay lại
  extension bằng completion resume là KHÔNG khả thi — khi đó P05 UX phải mở app hẳn).
