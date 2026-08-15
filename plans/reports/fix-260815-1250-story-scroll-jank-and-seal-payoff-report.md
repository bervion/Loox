# Story intro: fix khựng khi cuộn + payoff cho đoạn kết

Owner feedback 260815: cuộn story chưa mượt (hơi khựng), animation vòng tròn ở cuối "thiếu gì đó, chưa đã".

## Jank khi cuộn — root cause

Không nằm ở phép vẽ (Canvas đã tối ưu tốt từ #203: 1 canvas, symbol resolve 1 lần/pass, cap 60fps). Nằm ở OBSERVATION:
- `journeyProgress` observed → mỗi sự kiện scroll (120Hz) invalidate body `StoryStageView` (qua `themeMix`) + `StorySkipButton` → re-eval + diff cả cây TimelineView/Canvas/13 symbol view, CHỒNG lên 60fps tick của canvas.
- Nặng nhất: symbol `StoryScrapCard(mix:)` tham số hóa theo themeMix → 5 card view RE-RASTER mỗi tick suốt resolve window (beat 2.5→3.0) — đúng đoạn turn user scrub mạnh nhất.

## Fix (3 lớp)

1. `journeyProgress`/`beatPosition` → `@ObservationIgnored`: canvas POLL giá trị mới nhất trong closure TimelineView mỗi tick 60fps (fidelity y hệt — canvas vốn cap 60). Scroll không còn invalidate SwiftUI view nào.
2. `coarseBeat` observed mới, lượng tử 0.02 (`coarseQuantum`, test pin): cho 2 consumer thật sự cần invalidation — Skip capsule (blend màu ~25 bước qua resolve window) và đường scrub khi TimelineView pause (Reduce Motion/background — không có tick để poll). Publish thêm tại end-stop 0/5.
3. Symbol tách 2 biến thể TĨNH per scrap kind (`.scrap(kind, themed:)`, mix pin 0/1) — canvas crossfade 2 raster bằng opacity lúc stamp (cùng phép blend complementary-opacity card từng làm nội bộ). Theme veil cũng vẽ trong canvas (fill rect đầu pass) để body hết phụ thuộc beat.

## Đoạn kết — 4 nhịp mới

- **Inhale**: `sealPhases` thay `burstProgress` — 0.12s đầu cluster nén 5% (áp vào `reach` → cả lattice tự đồng dạng: bubble, mark, sigil, mote) rồi mới bung. Anticipation làm cú thả có lực.
- **Sigil khép vòng**: khi bung, 2 arc sweep từ 4.4rad → 2π (vòng tròn kín), lineWidth 2→2.8, opacity tăng theo inhale — "ổ khóa vặn chặt" là giọng thứ hai của exit.
- **Flash**: bloom accent tại mark decay ~0.15s ngay khoảnh khắc seal — đồng bộ `Haptics.tap` có sẵn = một cú click nghe-thấy-chạm.
- **Glint lap**: khi cluster nghỉ (beat ≥3.4), một vệt sáng pow(cos,8) chạy quanh orbit (~7s/vòng, +5% scale) — vault "sống" chứ không đứng im. `StoryOrbitLattice.angle(slot:t:)` tách từ `point` (DRY).

## Sự cố verification tìm thấy giữa chừng (quan trọng hơn cả fix)

Walkthrough UI test cũ **không có assertion** — chỉ chụp ảnh. Từ khi owner fix persistence deliberate-lock (~08/2026), fixture `vault-panic-restart` boot vào GATE KHÓA, story không bao giờ mount, và walkthrough vẫn pass trong khi chụp toàn màn lock. Test "xanh" rỗng suốt nhiều ngày.

Fix: walkthrough giờ (1) unlock có điều kiện (gate khóa persist NGOÀI vùng isolation nên lần chạy lẻ/chẵn khác trạng thái — phải chịu cả hai), slide + password fixture; (2) assert story mount sau unlock; (3) assert TỪNG beat trên màn hình bằng frame của title mang id `story.beat.N` (SwiftUI đóng dấu id lên StaticText con — query `staticTexts.matching(identifier:)`, không phải `otherElements`); (4) assert Home (`home.settings`) sau seal. Đã chứng minh fail to tiếng ở cả 2 chế độ hỏng trước khi pass thật.

## Verification

- StoryIntroTests 23/23 (thêm `testCoarseBeatPublishesPerQuantumAndAtEndStops`)
- Walkthrough hardened pass 42s: unlock → 6 beat assert + shot → seal → Home
- Video sim 68s quay tay cú seal (drive bằng simulator MCP): montage 38 frame + frame flash full-res xác nhận inhale → sigil khép kín + flash + fling → Home crossfade
- Chaos/sanctuary/commitment shots: swarm + cluster nguyên vẹn sau refactor symbol
- `make check` pass. Disk dọn về 5.0Gi sau khi xóa toàn bộ derived data + video.

## Unresolved

- Độ mượt CẢM NHẬN cuối cùng cần tay thật trên máy thật (simulator không đại diện GPU/ProMotion) — cấu trúc đã loại bỏ nguồn khựng scroll-correlated; owner sờ thử trên TestFlight là phán quyết cuối.
- Chưa commit — chờ owner duyệt ảnh/montage.
