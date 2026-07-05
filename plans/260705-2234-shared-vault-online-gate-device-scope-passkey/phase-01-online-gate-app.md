# Phase 01 — App Gate State Machine (V2.1: KHÔNG render trước verify)

Priority: cao · Effort: 0.5–1 buổi · Depends: P00
Patched theo review 260705: bỏ hẳn "verify song song với render" (vi phạm INV-01).

## State machine (bắt buộc, INV-01/02/03)

```swift
enum SharedValueAccessState: Equatable {
    case offline                       // network path chưa satisfied
    case verifying                     // đang authoritative verify — values CHƯA materialize
    case authorized(VerifiedGrantContext)
    case unavailable                   // verify lỗi/timeout — KHÔNG phải offline
    case revoked
}
```

- Values **không bao giờ vào render tree** trước `.authorized`:
  `guard case .authorized = accessState else { renderLockedState(); return }`.
  CẤM pattern `if hasSatisfiedNetworkPath { renderCachedSecret(); Task { verify() } }`.
- Mở detail: path chưa satisfied → `.offline`. Path OK → `.verifying` → verify grant
  (fetch record, đối chiếu epoch) → `.authorized` (decrypt + render) / `.revoked`
  (purge projection + cache + snapshot, toast) / `.unavailable` (lỗi/timeout —
  copy "Không thể xác minh quyền truy cập lúc này", KHÔNG nói "cần mạng").
- Đang `.authorized` mà path rớt → về `.offline` ngay (values gỡ khỏi tree).
- Copy/reveal: mỗi action re-check state; stale verify response phải bị loại bằng
  epoch/version guard (INV-06 — verify kết quả mang epoch, so với epoch hiện hành).
- Bật mạng lại → `.verifying`, KHÔNG "xem ngay". Snapshot chỉ được hiện metadata Tier 1
  (title/site/icon) trong lúc verifying — value-bearing fields thì không.

## Naming (review P1-3)
- `NetworkReachabilityMonitor.hasSatisfiedNetworkPath` (KHÔNG đặt `isOnline`) —
  NWPathMonitor là network-path precondition (Layer A), không phải oracle CloudKit.
  Layer B = authoritative grant verify. Không có đường nào từ Layer A thẳng tới render.
- Timeout verify lấy từ `SharedAccessTimingPolicy.grantVerificationDeadline` (P00) —
  không hardcode 3s.

## Files
- Tạo: `VaultifyCore/Platform/NetworkReachabilityMonitor.swift`,
  `Vaultify/Services/Sharing/SharedAccessAuthorizer.swift` (state machine + verify,
  unit-testable thuần logic).
- Sửa: `SharedItemsProjection.swift` (purge on revoked), `ItemDetailScreen.swift` (render
  theo state), lists (row shared: badge theo state, không navigate khi offline),
  `AppEnvironment.swift`.

## Success criteria
- Airplane mode → `.offline`, không màn nào lộ values; bật mạng → `.verifying` →
  chỉ hiện sau verify pass.
- Race test (P06): revoke lúc app background → foreground → tap copy NGAY → fail
  (state chưa kịp `.authorized` thì copy không có gì để lấy — vì values chưa render).
- Owned items không đổi hành vi.

## Risks
- Verify thêm ~0.3–1s mỗi lần mở detail shared item khi mạng chậm — chấp nhận (đúng
  yêu cầu "chặn tuyệt đối"); UX: skeleton + spinner ngắn, metadata Tier 1 hiện trước.
