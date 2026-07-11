# Phase 3 — Scanner: khung placeholder thẻ + nút rõ trên camera

Status: pending · Priority: P1

## Files

- Modify: `Vaultify/Features/ItemEditor/CardScannerSheet.swift`

## Steps

1. Reticle overlay (camera surface — exempt semantic-color rules theo DNA, trắng/đen literal
   cho phép):
   - Khung rounded-rect tỷ lệ thẻ ISO 1.586:1, width ≈ 78% màn, căn giữa hơi cao.
   - Dim phần ngoài khung: shape even-odd (Rectangle + RoundedRect cut-out) đen 45%.
   - Viền khung: stroke trắng 70%, 4 góc bracket đậm hơn (trắng 100%, dày 3) — chuẩn
     scan-UI quen thuộc.
   - Radius khung dùng `Radius` scale; motion không cần (tĩnh; Reduce Motion OK).
2. Guidance: "Point the camera at your card" đưa xuống DƯỚI khung (không đè), trắng, shadow
   giữ.
3. Cancel: `.foregroundStyle(.white)` explicit (không ăn accent tint app) — nút luôn nổi
   trên preview đen bất kể theme/accent.
4. VI cho string mới nếu có (khung không thêm string; giữ string cũ đã localize — verify
   trong xcstrings).

## Success

- Nhìn phát biết đặt thẻ vào đâu; Cancel rõ ràng mọi theme; không đổi hành vi capture.

## Risks / skip

- KHÔNG set VisionKit regionOfInterest theo khung (A6 — YAGNI, rủi ro lệch toạ độ giữa
  overlay SwiftUI và coordinate space của DataScanner).
