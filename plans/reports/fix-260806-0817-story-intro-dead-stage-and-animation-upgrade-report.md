# Story Intro: Dead Stage Fix + Animation Upgrade

Date: 2026-08-06 · Branch: main (working tree) · Owner report: storytelling đầu app "không có animation, text đen khó nhìn, dot trắng chói"

## Root cause (đúng cả 3 triệu chứng, một cơ chế)

`StoryIntroScreen` đo scroll bằng GeometryReader trong `.background` của content + PreferenceKey. Trên runtime iOS 18+/26, pattern này **không cập nhật khi cuộn** → `beatPosition` kẹt 0 vĩnh viễn:

- Không scrap nào sinh ra (birth cần beat ≥ 0.2), gather/ring/mark không bao giờ chạy → "chỉ đơn thuần scroll"
- Canvas không bao giờ crossfade sang nền theme → beat 5-6 (sanctuary/commitment) vẽ `theme.primary` (đen của light theme) trên canvas đen → "text màu đen khó nhìn" (chụp được ở beat5, run chẩn đoán đầu)
- Dot gốc chỉ tan khi beat ≥ 0.45 → sáng mãi sau mọi trang chữ → "dot trắng phía sau chói"

Compile + unit tests không thấy được lớp lỗi runtime này. Chẩn đoán bằng UI test walkthrough tự cuộn + chụp từng beat (fixture `vault-panic-restart` + `-ui-test-story`).

## Fixes

1. **Scroll plumbing** (`StoryIntroScreen`): iOS 18+/macOS 15+ dùng `.onScrollGeometryChange` (offset = contentOffset.y + contentInsets.top; span = contentSize − containerSize); nhánh PreferenceKey chỉ còn cho floor 17.3 qua `#available`.
2. **StoryScrapCard crossfade ngược** (`StoryStageView`): lớp `theme.controlBackground`/`theme.separator` từng vẽ đục 100% từ beat 0 → light theme thành 90 card sáng chói trên nền đen. Giờ mọi lớp theme nhân `opacity(mix)`, lớp dark-world nhân `1 − mix`.
3. **Text trang Turn** (`StoryBeatView`): trắng cố định trên canvas đã resolve trắng = tàng hình. Giờ 2 lớp text (trắng ↔ theme role) crossfade theo đúng cửa sổ resolve của canvas, tính từ scroll phase của chính trang (render-side, không đọc model).
4. **Skip button** (`StorySkipButton` mới): child view riêng đọc `beatPosition` (chỉ invalidate mỗi capsule), blend màu label/scrim từ dark-world sang theme bằng `RGBMath.blend`.
5. **Ripple/amber gate**: ripple + pool + ghost copies giới hạn trong cửa sổ beat consequence — tap xong cuộn ngược không còn để lại khói amber ở hook.

## Animation upgrade

- Origin dời (0.5, 0.40) → (0.5, 0.30): dot/mark/ring tách hẳn khỏi cột chữ; mỗi beat có `artClearance` đẩy copy xuống nửa dưới (sanctuary/commitment 0.24, turn 0.10, hook 0.06)
- **Ring tròn thực**: unit-space hiệu chỉnh aspect (`ringScale`) + cap 0.17×height cho iPad landscape; ring 96pt đồng tâm với 2 sigil arc + orbit line accent mới (0.16 alpha, siết theo tighten)
- Scrap card: nghiêng ±8° seed + wobble khi trôi, thẳng hàng lại khi gather; depth alpha 0.72–1.0; drift 0.022; fill/stroke/glyph dark-world tăng hiện diện (0.10/0.18/0.78)
- Consequence: spotlight — swarm lùi 30% khi chip sáng lên; 4 ripple ring 1.5pt; ghost copies pop-in scale; amber pool 0.28
- Sanctuary: sigil arc 2pt alpha 0.5; glow mark 132pt; seal burst bloom halo ×1.6 khi ring văng ra
- Glow dot hook: nhỏ hơn (76pt), dịu hơn (0.45) — hết chói
- Hint "Scroll": pulse thêm opacity 0.55↔1 cùng nhịp lift (tắt hẳn dưới Reduce Motion)
- Canvas resolve window 2.2→3.0 đổi thành 2.5→3.0 (hằng chia sẻ `themeResolveStart/End`) để copy trắng của consequence kịp mờ trước khi nền sáng lên

## Verification (iPhone 17 Pro sim, iOS 26.5)

- Walkthrough EN light: swarm ✓ spotlight+amber ✓ ring tròn + chữ đen-trên-trắng ở turn ✓ sanctuary mark+arcs ✓ tighten ✓ seal burst ✓ arrival vào Home ✓
- Walkthrough VI (`-ui-test-language vi` mới, DEBUG-only): "Một chỗ lộ, mở mọi cánh cửa", "Một kho duy nhất. Của riêng bạn.", "Bỏ qua" — không tràn/cắt dòng
- Reduce Motion pass: scene vẫn compose đầy đủ (mọi vị trí scrub theo scroll; tap consequence land full state ngay vì clock đóng băng)
- `StoryIntroTests` 10/10 pass (ring giờ so với `StoryField.ringRadius`); walkthrough UI test pass 2 lần
- `make check` (app + appex) ✓
- macOS slice: story files không lỗi nào; target FAIL sẵn trên main vì `ItemTypePickerSheet.swift:127` dùng `.textInputAutocapitalization` (API iOS-only, từ feature vault types e5815f6, 8 lỗi cùng nhóm, không liên quan story) — đã tạo task chip riêng để sửa
- Dark theme: không chạy runtime (isolation pin theme Day; app tự pin interface style) — an toàn theo cấu trúc: beats 1-3 dùng palette cố định giống hệt light; beats 4-6 chỉ dùng semantic roles chuẩn của theme system. Owner có thể xác nhận nhanh trên máy thật.

## Files

`StoryIntroScreen.swift` `StoryStageView.swift` `StoryBeatView.swift` `StoryParticleField.swift` (app target) · `AppEnvironment.swift` (+`-ui-test-language`, DEBUG) · `StoryIntroTests.swift` · `StoryIntroWalkthroughUITests.swift` (mới — công cụ chẩn đoán/verify runtime, giữ lại làm lưới an toàn cho lớp lỗi runtime-only)

Screenshots (ephemeral): /tmp/story-shots-{light,vi,rm}/ · trước-fix: scratchpad story/beat1-light.png + ảnh trong transcript phiên này

## Unresolved

- Dark-theme runtime walkthrough chưa chạy được trong isolation (cần cơ chế `-ui-test-theme` nếu muốn tự động hóa; hiện verify bằng phân tích + để owner xem trên máy)
- Instruments perf pass trên máy thật (iPhone 12 baseline theo concept) chưa làm — thêm rotation transform + 1 circle stroke mỗi frame, chi phí không đáng kể nhưng chưa đo thực
