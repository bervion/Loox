# Phase 02 — Online Gate (extension)

Priority: cao · Status: planned · Effort: 0.5 buổi · Depends: P01

## Overview
Extension áp cùng luật: offline → shared credentials không dùng được. V1 phase này =
reachability gate (NWPathMonitor); live-grant verify trong extension cần CloudKit → hoàn
thiện sau P04 (ghi TODO rõ trong code).

## Files
- Sửa: `VaultifyAutoFill/AutoFillView.swift` (CredentialListView: offline → shared rows
  thay bằng 1 row disabled "Mục được chia sẻ cần kết nối mạng"; preferredRecordID trúng
  shared entry khi offline → KHÔNG auto-fill, hiện state cần mạng),
  `OneTimeCodeView.swift` (nhánh shared TOTP tương tự),
  dùng `NetworkReachabilityMonitor` từ VaultifyCore (P01).

## Steps
1. Monitor khởi tạo trong extension (nhẹ, không giữ battery — extension sống ngắn).
2. Gate cả 3 đường: list picker, preferredRecordID auto-select, passkey→password fallback.
3. Sau P04: trước khi complete fill một shared entry → verify grant alive (CK fetch),
   fail-closed như app.
4. l10n EN+VI.

## Success criteria
- Airplane mode → extension vẫn fill OWNED items bình thường; shared entries hiện disabled
  + lý do; không có đường nào lấy được password share khi offline.

## Risks
- NWPathMonitor cần vài trăm ms cho path đầu tiên → default `.requiresConnection` (coi như
  offline) tới khi path satisfied — fail-closed, không fail-open.
