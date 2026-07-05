# Phase 06 — Tests, QA 2 thiết bị, docs

Priority: bắt buộc trước merge · Effort: 0.5 buổi · Depends: P01–P05

## Test matrix (unit)
- Grant v1→v2 canonical vectors: v1 cũ verify OK (deviceScope=multi mặc định), v2 sign/verify,
  tamper fail. Capability codec round-trip (passkey/TOTP modes mới).
- Per-device seal: N-key seal → đúng device mở được, device lạ fail-closed.
- SharedCredentialsCache v2: version bump + back-compat decode v1.
- Reachability gate logic: offline → shared values inaccessible (unit hoá state machine).

## QA 2 thiết bị (owner A + recipient B, checklist)
1. Online gate: B airplane-mode → shared item ẩn values cả app + extension; bật mạng → hiện lại.
2. Revoke race: A revoke trong lúc B đang mở detail → biến mất ≤ 1 verify; B tắt mạng TRƯỚC
   khi A revoke → mở lại phải có mạng → thấy đã revoke (đúng mục tiêu chống né thu hồi).
3. Device scope: share single-device → B device 2 không đọc được values + copy rõ ràng;
   multi-device → B device 2 xin cấp → A approve → đọc được.
4. Passkey askEachTime: full round-trip QuickType → chờ duyệt → login (đo thời gian sống
   extension); owner offline → timeout copy tử tế.
5. Passkey/TOTP shared: cảnh báo hiện đúng lúc chọn; dùng không cần hỏi; revoke chặn từ
   lần verify sau.
6. Regression: owned items + Quick Link (Loox Link) không bị gate ảnh hưởng.

## Docs
- `docs/codebase-summary.md`: mục Approval Mode Sharing cập nhật (gate, device scope,
  passkey capability) — giữ ≤ hạn mức dòng.
- Release notes EN+VI nêu rõ hành vi online-required (users sẽ hỏi "sao offline không xem
  được share nữa" — đây là feature, không phải bug).
