# Loox Hub ẩn trên App Store, hiện trên TestFlight (v1.57.2)

Ngày: 2026-10-21. Code: `main` @ f71a281 (v1.57.2). Chỉ đọc, không sửa code.

## Kết luận

- Nguyên nhân nằm ở client, cố ý từ commit 4adf79b (#167, có từ v1.38.0). Không phải lỗi BE, không thiếu cấu hình ASC.
- BE không bật được: không có remote flag nào điều khiển Hub. Cần build mới + App Review.

## Chuỗi gate (Release)

1. Lối vào DUY NHẤT tới `LooxHubScreen` = row "Loox" ở Profile (`ProfileScreen.swift:59-66`), iPhone/iPad/Mac dùng chung.
2. Row chỉ hiện khi `tier > .free || purchasesEnabled` (`ProfileScreen.swift:22-23`, "owner request 260723").
3. `purchasesEnabled = launchEnabled || (betaPreviewEnabled && betaPurchaseAccess)` (`LooxEntitlementStore.swift:48-57`).
4. `launchEnabled = false` (`LooxMembership.swift:29`, test-pinned `LooxMembershipTests.swift:92`).
5. `betaPurchaseAccess` = receipt `sandboxReceipt` hoặc `AppTransaction.environment != .production` (`LooxEntitlementStore.swift:155-177`).
   - TestFlight/App Review: sandbox -> true -> row hiện.
   - App Store: production -> false -> row ẩn.
6. Production không mua được -> mọi user là Free -> 100% user App Store không thấy Hub.
7. Cùng binary: lane `submit` dùng `skip_binary_upload: true` (`fastlane/Fastfile:129-140`).

Mâu thuẫn: `LooxMembership.swift:3-7` ghi launch gate "never hides the membership screen itself". Hub đã tự ẩn phần thương mại khi purchases tắt (`LooxHubScreen.swift:29`, `:367-375`).

Hệ quả phụ: `PersonaAliasesScreen` (quản lý Private Email), `ShareLinksScreen`, `SendToBrowserScreen` chỉ mở được từ Hub (`LooxHubScreen.swift:238-264`). Release notes v1.57.x nhắc màn Member mà user App Store không vào được.

## Phương án

- **B (khuyến nghị):** luôn hiện row Loox, thương mại vẫn tắt. Bỏ `showsMembershipRow` + `if` (`ProfileScreen.swift:18-23`, `:59`), sửa comment, cập nhật `docs/codebase-summary.md`. Không chuỗi mới, dự kiến không test nào hỏng. Đảo quyết định 260723 -> cần owner OK. Ra bằng `make hotfix`.
- **A (không khuyến nghị lúc này):** `launchEnabled = true`. Mở paywall + chặn quota cho user Free (profile thứ 2, alias thứ 2, link thứ 4/30 ngày, Quick View thứ 4/30 ngày, Watchtower full). Checklist §5.6 (`phase-05-membership-launch.md`) chưa tick. Test pin sẽ fail.
- Không đặt `betaPreviewEnabled = false` (TestFlight/App Review cũng mất Hub).

## Rủi ro BE/vận hành (không gây lỗi hiện tại)

- Send to Browser trên App Store phụ thuộc manifest ký số `quick_view.exposure = ga` (`QuickViewExposure.swift:33-44`, cohort `QuickViewExposureProvider.swift:9-16`). GET 2026-10-21: manifest v13 = `ga`, ổn. BE phải giữ `ga`.
- Hạn tài liệu ký số (theo GET live): QV signer keyset hết hạn 2026-11-30 09:40 +07 (~40 ngày); manifest + domain registry hết hạn 2027-02-28. Hết hạn -> Quick View ẩn/lỗi trên mọi build. Cần ký lại + cập nhật mirror CloudKit `LooxCapabilityManifest/current`.
- Khi bật `launchEnabled` sau này: 4 subscription Cleared for Sale; ASSN v2 Production URL -> `https://entitlement.looxpassword.com/v1/apple/notifications`; prod worker có `IAP_KEY_P8`, `IAP_KEY_ID`, `IAP_ISSUER_ID`, `APP_APPLE_ID`; kiểm tra lại App Store Server API production (từng trả 401 trước release); `ENTITLEMENT_MODE` giữ off/shadow tới B5.

## Ghi chú minh bạch

Trong lúc điều tra, ngoài các GET chỉ đọc, một agent đã gửi 1 POST body rỗng tới `entitlement.looxpassword.com/v1/entitlement/attach` để kiểm tra endpoint; server trả 400 `invalid_body`, không thay đổi dữ liệu.

## Câu hỏi mở

1. Owner đồng ý phương án B (hiện Hub cho Free, thương mại vẫn tắt)?
2. Hotfix patch hay gộp vào minor kế tiếp?
3. Ai ký lại QV signer keyset trước 2026-11-30?
4. Repo BE (`workers/*`) không có trên máy: chưa xác minh `ENTITLEMENT_MODE`, `ASSERTION_MODE`, cấu hình ASSN từ code BE.
