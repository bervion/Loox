# Phase 01 — Online Gate (app): chặn tuyệt đối khi mất mạng

Priority: cao · Status: planned · Effort: 0.5 buổi

## Overview
Shared items chỉ xem được khi CÓ mạng (quyết định #2 — không grace). Hai tầng:
reachability (tức thì, NWPathMonitor) + live-grant verify (authoritative, fail-closed).
Snapshot 260705 giữ nguyên (tốc độ list); tầng gate quyết định có render VALUES không.

## Files
- Tạo: `VaultifyCore/Platform/NetworkReachabilityMonitor.swift` (NWPathMonitor wrapper,
  `@Observable`, nonisolated core — extension dùng chung ở P02).
- Sửa: `SharedItemsProjection.swift` (thêm `isDisplayGateOpen` + `verifyGrantAlive(itemId:)`
  — fetch nhẹ record grant, CKError.zoneNotFound → remove item + cache + snapshot ngay),
  `ItemDetailScreen.swift` (sharedOrigin + offline → placeholder che values),
  `ItemsScreen/HomeScreen/SearchScreen` (row shared khi offline: mờ + badge "Cần mạng"),
  `SharedWithMeScreen.swift`, `AppEnvironment.swift` (wire monitor).

## Steps
1. `NetworkReachabilityMonitor`: `isOnline: Bool` cập nhật realtime; khởi động cùng env.
2. Detail screen của shared item: `guard isOnline` → nếu offline hiện state
   "Cần kết nối mạng để xem mục được chia sẻ" (icon globe, không render field values);
   đang xem mà rớt mạng → values ẩn NGAY (observe monitor).
3. Mở detail + trước mỗi copy/reveal: `verifyGrantAlive` async — grant chết → item biến mất
   toàn cục (projection + cache + snapshot), toast "Chủ sở hữu đã thu hồi".
4. List rows: offline → disabled + badge; không cho navigate vào detail.
5. l10n EN+VI cho mọi copy mới.

## Success criteria
- Airplane mode → shared values không thể xem ở bất kỳ màn nào; bật mạng lại → xem được ngay.
- Revoke từ owner trong lúc recipient đang mở detail (có mạng) → values biến trong ≤1 lần verify.
- Item OWNED không bị ảnh hưởng gì.

## Risks
- CloudKit verify chậm trên mạng yếu → verify chạy song song với render, fail-closed sau
  timeout ngắn (~3s coi như offline). KHÔNG block copy của owned items.
