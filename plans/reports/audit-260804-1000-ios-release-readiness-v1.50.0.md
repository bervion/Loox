# Loox v1.50.0 — iOS/iPadOS Release Readiness Audit

- Ngày audit: 2026-08-04, múi giờ `Asia/Ho_Chi_Minh`
- Nhánh/commit: `main` tại `cb680df2e1cf8516c3b1afd3896c85c38200dd30`
- Tag hiện tại: `v1.50.0`
- Version/bundle build: `1.50.0 (78)`
- Phạm vi release: iPhone, iPad, AutoFill Credential Provider, Safari Web Extension
- Ngoài phạm vi: macOS app và `VaultifyAutoFillMac`
- Kết luận: **RELEASE HOLD / NO-GO**

> Bản gốc do owner cung cấp 2026-08-04. Lưu lại nguyên văn làm nguồn tham chiếu cho
> kế hoạch khắc phục `plans/260804-1037-release-readiness-remediation/`. Không sửa
> file này khi triển khai — trạng thái thực thi được theo dõi trong plan, không ở đây.

## 1. Tóm tắt điều hành

Code mới nhất đã được fast-forward từ `origin/main`, Tuist generate thành công, cả Debug Simulator và Release device configuration đều compile thành công. Release product vượt bước Xcode `-validate-for-store` ở mức unsigned, nhúng đúng hai iOS extension, cùng version `1.50.0 (78)`, cùng device family iPhone/iPad và không chứa extension Mac. Toàn bộ 1.152 XCTest cũ và 10 Swift Testing test pass; bốn Safari JavaScript harness pass; catalog native và Safari không thiếu bản dịch VI/JA.

Tuy nhiên **không nên gửi App Review ở trạng thái hiện tại**. Các blocker chính đã được xác minh:

1. Privacy manifest của app khai báo sai reason cho App Group `UserDefaults`, thiếu System Boot Time, còn hai extension không có manifest riêng dù trực tiếp chạy shared code dùng required-reason API.
2. Hai URL Terms/Privacy mà paywall mở đang trả HTTP 404. Trang Privacy đúng route vẫn tự nhận là "starter template" và nói không có third-party analytics, trong khi Firebase Analytics/Crashlytics được bật mặc định.
3. Fresh install tự bật vault-item iCloud sync sau khi tạo vault, trái contract "opt-in, off by default" trong README/AGENTS và không có bước xin lựa chọn rõ ràng.
4. Favicon network lookup mặc định bật và gửi hostname của từng login tới Google; cache dùng hostname plaintext và không được xóa khi Erase Vault.
5. Quality gate đang đỏ: 1/3 snapshot test fail và 2/2 UI test fail. CI chỉ chạy unit test và release tag có thể upload mà không phụ thuộc các gate này.
6. Erase Vault xóa key/local state trước khi CloudKit/share/Quick Link revoke hoàn tất; offline hoặc app bị kill có thể để remote data/link sống mà không còn durable retry state.
7. iPad có bug search xác định được và chưa có test/runtime evidence đủ cho fullscreen, landscape, Split View, Stage Manager, keyboard, Dynamic Type và accessibility.

Ngoài các blocker trên còn có rủi ro data safety ở import/export/erase/migration, nhiều gate signed-device/App Store Connect chưa thể xác minh từ máy local, và một số UI/accessibility debt nên xử lý trước review.

**Hành động vận hành ngay:** tag `v1.50.0` đã tồn tại trên remote và `.github/workflows/release-ios.yml` tự upload khi push tag. Audit local không truy cập được GitHub Actions/App Store Connect, nên owner cần kiểm tra ngay liệu build 78 đã lên TestFlight hay chưa, giữ nó ngoài App Review và không mở external testing rộng cho đến khi đánh giá privacy/data-safety xong.

## 2. Phương pháp và giới hạn audit

### Đã thực hiện

- `git pull --ff-only origin main`: fast-forward từ `cf8b0a4` lên `cb680df`; worktree sạch trước audit.
- `tuist generate --no-open`: pass với Tuist `4.200.1`.
- Compile Debug cho generic iOS Simulator: pass.
- Compile Release cho generic iOS device, `CODE_SIGNING_ALLOWED=NO`: pass; Xcode chạy `-validate-for-store` và validate hai embedded binary thành công.
- Unit test trên iPhone 11 simulator, iOS 26.5: 1.152 XCTest pass, 10 Swift Testing test pass.
- Snapshot test: chạy toàn bộ target, 2 pass, 1 fail.
- XCUITest: chạy toàn bộ target, 0 pass, 2 fail.
- Safari JavaScript: field classifier, fill engine, inline menu, signup detector đều pass.
- Kiểm tra string catalog native và Safari EN/VI/JA.
- Kiểm tra bundle Info.plist, embedded extensions, version/device family và resources trong Release product.
- Smoke visual fresh install trên iPad Pro 11-inch simulator ở portrait, light/dark system và Accessibility XXXL.
- Static audit các luồng onboarding, sync, privacy, analytics, import/export, erase, sharing cache, iPad adaptive navigation, AutoFill, Safari bridge, signing/release workflow.
- Xác minh trực tiếp bốn URL pháp lý bằng HTTP.
- Đối chiếu yêu cầu hiện hành bằng tài liệu chính thức của Apple.

### Chưa thể thực hiện hoặc chưa đủ bằng chứng

- Signed App Store archive, `altool`/Transporter validation và App Store Connect privacy report.
- Kiểm tra provisioning profile/certificate thực tế do signing assets nằm ngoài local audit.
- TestFlight processing, crash-symbol upload và trạng thái GitHub Actions vì `gh` chưa được xác thực trong môi trường audit.
- App Store Connect metadata, IAP/subscription state, review screenshots, app privacy answers và availability.
- E2E thực tế trên iPhone/iPad có ký: Face ID, App Group, Keychain sharing, CloudKit production, push, AutoFill, passkey, OTP và Safari native messaging.
- iPad landscape/Split View/Stage Manager end-to-end; smoke visual hiện tại chỉ đủ chứng minh app mở được ở portrait.
- Upgrade một vault thật từ v1.49.1 lên v1.50.0.

Mọi mục bên dưới được đánh dấu **Verified defect**, **Verified process gap**, **Likely defect cần repro**, hoặc **External gate chưa xác minh**.

## 3. Release target matrix

| Target | Product Release hiện tại | Kết quả local | Gate còn lại |
|---|---|---|---|
| `Vaultify` iPhone | Có | Compile/test core pass | Privacy/legal, UI gates, signed device, ASC metadata |
| `Vaultify` iPad | Có, `UIDeviceFamily = [1,2]` | Launch portrait pass | Search bug, orientation/multitasking, full QA matrix, screenshot 13-inch |
| `VaultifyAutoFill` | Có, embedded `.appex` | Compile + embedded validation pass | Privacy manifest, signed real-device capability matrix |
| `VaultifySafari` | Có, embedded `.appex` | Compile + JS harness + embedded validation pass | Privacy manifest, E2E Safari/native bridge, all-sites review note |
| `VaultifyAutoFillMac` | Không | Không có trong iOS product | Giữ ngoài submission; không test trong đợt này |
| iPhone/iPad app trên Apple Silicon Mac | Không mong muốn | Không thể kiểm tra trong repo | Tắt availability trong App Store Connect |

Release product local chỉ chứa:

- `Vaultify.app`
- `Vaultify.app/PlugIns/VaultifyAutoFill.appex`
- `Vaultify.app/PlugIns/VaultifySafari.appex`

Cả ba bundle đều là `1.50.0 (78)` và `UIDeviceFamily = [1,2]`. Không thấy `VaultifyAutoFillMac` trong iOS product.

## 4. Kết quả verification

| Gate | Kết quả | Ghi chú |
|---|---:|---|
| Sync `main` | PASS | `HEAD == origin/main == v1.50.0 == cb680df` |
| Tuist generation | PASS | Workspace/project được generate lại |
| Debug Simulator compile | PASS | Embedded AutoFill/Safari validation pass |
| Release generic iOS compile | PASS | Unsigned; Xcode `-validate-for-store` pass |
| Unit + Swift Testing | PASS | 1.152 XCTest + 10 Swift Testing, 0 failure |
| Safari JS harness | PASS | 4/4 harness |
| Native localization | PASS | 1.826 entries, không thiếu/blank VI; JA cũng đầy đủ theo scan |
| Safari localization | PASS | EN/VI/JA cùng 47 key, không có message rỗng |
| Snapshot | **FAIL** | 2/3 pass; slide-to-unlock light mismatch |
| XCUITest | **FAIL** | 0/2 pass |
| iPad portrait fresh install | PARTIAL PASS | Welcome render được ở normal và AX XXXL; chưa đủ matrix |
| Signed archive/IPA | NOT RUN | Cần signing assets và App Store profile |
| App Store Connect readiness | UNKNOWN | Metadata/IAP/privacy/screenshot ở ngoài repo |

### Cảnh báo compiler Release cần dọn

Xcode 26.5 phát hiện bảy warning code-level duy nhất, ngoài warning AppIntents metadata vô hại:

- `Vaultify/Features/Folders/IconPickerSheet.swift:21`
- `Vaultify/Features/Folders/SpaceSeedIdentity.swift:23`
- `Vaultify/Features/Home/HomeAttention.swift:87`
- `Vaultify/Security/Level2BiometricKeyStore.swift:137`
- `Vaultify/Services/AttachmentStore.swift:33-34`
- `Vaultify/Services/Tutorial/TutorialStore.swift:46`

Sáu warning liên quan actor-isolation có thể thành error khi chuyển sang Swift 6 strict; một warning bỏ qua return value của `remove(group:)`. Không chặn binary hiện tại nhưng nên xử lý trước nhánh release kế tiếp.

## 5. P0 — phải xử lý trước khi submit

### P0-01 — Privacy manifest không đủ cho app và hai extension

**Loại:** Verified defect, nguy cơ App Store Connect từ chối binary.

**Bằng chứng:**

- `Vaultify/Resources/PrivacyInfo.xcprivacy:51-65` chỉ khai báo `NSPrivacyAccessedAPICategoryUserDefaults` với reason `CA92.1`.
- `VaultifyCore/SharedConfig.swift:27` và `VaultifyCore/Theme/ThemeReader.swift:12` dùng App Group `UserDefaults(suiteName:)`. Apple quy định use case App Group là `1C8F.1`; `CA92.1` chỉ cho dữ liệu app tự đọc/ghi và không cho extension/app khác trong group truy cập.
- `Vaultify/Services/Haptics.swift:62` dùng `ProcessInfo.processInfo.systemUptime`, cần `NSPrivacyAccessedAPICategorySystemBootTime` với reason phù hợp, trường hợp đo thời gian giữa event là `35F9.1`.
- `Project.swift:221-230` và `Project.swift:340-358` không đưa `PrivacyInfo.xcprivacy` vào resources của AutoFill/Safari.
- Release product có app-level manifest và manifests của Firebase dependencies, nhưng không có manifest trong `VaultifyAutoFill.appex` hoặc `VaultifySafari.appex`.
- Cả hai extension compile `VaultifyCore/**`, do đó trực tiếp chứa code dùng App Group defaults.

Apple yêu cầu mỗi executable/dynamic library dùng required-reason API phải có manifest trong bundle chứa executable đó. Xem [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) và [UserDefaults/System Boot Time reason values](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

**Yêu cầu triển khai:**

1. Sửa app manifest: giữ `CA92.1` nếu app còn dùng `.standard` cho state app-only, thêm `1C8F.1` cho App Group, thêm System Boot Time/`35F9.1`.
2. Tạo manifest riêng, tối thiểu và đúng behavior cho `VaultifyAutoFill` và `VaultifySafari`; add resource trong `Project.swift`.
3. Scan các required-reason API còn lại ở từng executable. `FileManager.attributesOfItem` hiện chỉ đọc `.size`; không tự suy diễn File Timestamp, hãy lấy Xcode Privacy Report làm nguồn kết luận.
4. Generate signed archive, mở Privacy Report, đảm bảo không còn warning/missing reason và không copy thừa analytics collection sang extension.

**Acceptance:**

- Mỗi app/appex root có đúng một valid `PrivacyInfo.xcprivacy` của target.
- Xcode archive Privacy Report sạch.
- Transporter/App Store Connect không báo invalid/missing required reason.
- Unit test/bundle test xác nhận manifest tồn tại trong cả ba executable bundle.

### P0-02 — Paywall mở link pháp lý 404; privacy policy công khai sai thực tế

**Loại:** Verified defect, App Review/legal/privacy blocker.

**Bằng chứng:**

- `VaultifyCore/Subscription/LooxMembership.swift:21-22` dùng:
  - `https://looxpassword.com/terms` → HTTP 404 tại thời điểm audit.
  - `https://looxpassword.com/privacy` → HTTP 404 tại thời điểm audit.
- Route đang hoạt động:
  - `https://looxpassword.com/policies/terms` → HTTP 200.
  - `https://looxpassword.com/policies/privacy` → HTTP 200.
- Trang Privacy đang hoạt động ghi "This is a starter template" và "No third-party trackers or analytics profiles".
- `Vaultify/App/SettingsStore.swift:238-239` mặc định `analyticsEnabled = true`, `crashReportingEnabled = true`.
- App link `FirebaseAnalyticsCore` và `FirebaseCrashlytics`; app manifest cũng tự khai báo Product Interaction, Crash Data và Other Diagnostic Data.
- `Vaultify/Services/Subscription/LooxEntitlementStore.swift:41-54,133-167` có chủ ý bật purchase surfaces trong TestFlight/App Review sandbox dù `LooxMembership.launchEnabled == false`, nên reviewer rất có thể bấm vào các link lỗi.

Điều này có thể vi phạm tính đầy đủ/chính xác theo [App Review Guidelines 2.1 và 2.3](https://developer.apple.com/app-store/review/guidelines/) và disclosure theo [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).

**Yêu cầu triển khai:**

1. Sửa code sang route 200 hoặc cấu hình redirect vĩnh viễn từ route cũ.
2. Thay privacy starter template bằng policy được legal/product phê duyệt.
3. Chốt quyết định Firebase:
   - Nếu giữ: policy, App Store privacy labels, onboarding/settings copy, website, README và marketing claims phải mô tả chính xác.
   - Nếu bỏ/tắt mặc định: gỡ hoặc đổi initialization/collection defaults và cập nhật manifest/labels theo behavior mới.
4. Audit website claims "no tracking", "zero analytics", "zero backend", "stays on device" so với CloudKit, Firebase, Google favicon và Loox Link/Quick View.
5. Thêm automated HTTP check cho Terms, Privacy, Support URL trong release gate.

**Acceptance:**

- Link trong paywall trả 200, nội dung đúng locale hoặc fallback rõ ràng.
- Không còn "starter template".
- Policy, in-app settings, privacy manifest và App Store Connect answers thống nhất với packet capture/runtime.
- App Review sandbox có thể mở Terms/Privacy mà không lỗi.

### P0-03 — Fresh install tự bật vault-item iCloud sync, trái opt-in contract

**Loại:** Verified privacy/product defect.

**Bằng chứng:**

- `Vaultify/App/SettingsStore.swift:234` mặc định `iCloudSyncEnabled == false`.
- `Vaultify/Features/Onboarding/OnboardingFlow.swift:135-150` gán `env.settings.iCloudSyncEnabled = true` ngay sau `createVault`.
- Emergency Kit task ở `OnboardingFlow.swift:101-109` gọi `env.syncNow()` sau khi tạo recovery envelope.
- `Vaultify/Features/Onboarding/JoinVaultFlow.swift:122` cũng bật sync trong recovery/join flow; cần phân biệt restore bắt buộc với fresh-create consent.
- `README.md:20`, `README.md:62` và `AGENTS.md:138-139` mô tả vault-item sync là optional/opt-in/off by default.

Behavior hiện tại có thể đưa ciphertext, recovery envelope và seeded identity metadata lên CloudKit mà không có một lựa chọn rõ ràng trong fresh-create flow. Dữ liệu có mã hóa không làm mất yêu cầu minh bạch/consent và không khớp product promise.

**Yêu cầu triển khai:**

1. Fresh create phải giữ sync off hoặc trình bày một bước lựa chọn explicit, không preselect theo hướng ép bật.
2. Emergency Kit phải hoạt động hợp lệ khi sync off; copy không được hứa multi-device recovery nếu chưa bật.
3. Join/restore flow được phép cần CloudKit theo chức năng, nhưng phải nói rõ trước khi bật và không được nối nhầm với `approvalModeEnabled`.
4. Thêm regression test fresh install: sau create vault, sync vẫn off khi user chưa đồng ý và không có CloudKit push.
5. Cập nhật docs hoặc product contract chỉ sau quyết định owner; không âm thầm đổi docs để hợp thức hóa behavior.

**Acceptance:**

- Packet/log test chứng minh fresh create không ghi CloudKit trước consent.
- Onboarding EN/VI/JA giải thích đúng local-only, sync và recovery.
- `iCloudSyncEnabled` và `approvalModeEnabled` vẫn độc lập.

### P0-04 — Favicon mặc định làm lộ domain login tới Google và để metadata sau Erase Vault

**Loại:** Verified privacy defect, đặc biệt nghiêm trọng với password manager.

**Bằng chứng:**

- `Vaultify/App/SettingsStore.swift:237`: `showWebsiteIcons` mặc định true.
- `Vaultify/Services/FaviconService.swift:42`: request `https://www.google.com/s2/favicons?...&domain=<host>`.
- File comment của chính service xác nhận bật feature sẽ reveal login domains cho Google.
- Cache nằm trong App Group `Favicons`; filename là `\(host).img`, tức hostname plaintext.
- `FaviconService` ghi cache không dùng explicit file-protection option.
- `Vaultify/App/AppEnvironment.swift:382-418` xóa nhiều cache khi Erase Vault nhưng không xóa favicon cache.
- Shared-item title/URL có thể kích hoạt favicon lookup, làm disclosure lan sang item được share.

**Yêu cầu triển khai:**

1. Tắt website icons mặc định hoặc yêu cầu opt-in với disclosure rõ ràng trước request đầu tiên.
2. Ưu tiên thiết kế không gửi credential-domain inventory cho Google: direct origin favicon với giới hạn an toàn, privacy proxy do team kiểm soát với policy đúng, hoặc icon local/generic.
3. Không dùng hostname plaintext làm cache filename; dùng HMAC/hash keyed hoặc mapping mã hóa.
4. Áp dụng complete file protection và xóa cache/memory trong Erase Vault.
5. Khi toggle off, cho user lựa chọn clear cache ngay; test không request network khi off.
6. Đồng bộ privacy policy và App Store labels nếu vẫn dùng third-party favicon service.

**Acceptance:**

- Fresh install không gửi host nào trước consent.
- Erase Vault xóa hoàn toàn cache favicon.
- Test chứng minh shared/offline/revoked item không trigger disclosure ngoài contract.
- Network/privacy test được đưa vào release evidence.

### P0-05 — Quality gates đang fail nhưng release workflow không chặn tag upload

**Loại:** Verified product/process blocker.

**Snapshot failure:**

- `LockControlSnapshotTests.testSlideToUnlockLight` mismatch trên Xcode/iOS 26.5.
- Reference có arrow rõ và knob/ring tối; actual mất arrowhead, chỉ còn dash ngắn và ring trắng.
- Code/asset không đổi từ v1.49.1, nên có thể là thay đổi SVG rendering/toolchain; dù nguyên nhân nào, actual runtime hiện tại nhìn sai.
- Không được cập nhật golden chỉ để làm xanh. Phải xác nhận UI intent, sửa render/asset rồi mới record baseline.

**UI test failures:**

1. `VaultEditSaveRelockUITests.testEditSaveLockAndUnlockPreservesItem` mở item được nhưng không tìm thấy `item.detail.more` ở toolbar menu. Có thể là iOS 26 accessibility/toolbar grouping regression hoặc identifier không còn gắn vào element mà XCUITest thấy.
2. `VaultPanicRestartUITests.testDeliberateLockSurvivesRelaunch` bị tutorial "Add your first item" chặn `home.settings`; đây là fixture/test isolation defect đã xác minh, chưa đủ để kết luận panic-lock production hỏng.

**Pipeline gap:**

- `.github/workflows/ci.yml` chỉ chạy `VaultifyTests` trên iPhone.
- `.github/workflows/release-ios.yml` trigger trực tiếp trên tag `v*` và không require exact SHA pass snapshot/UI/Release/privacy/iPad/signed-device gates.
- `docs/runbooks/ci-release-operations.md` tham chiếu `.github/workflows/release-evidence.yml` và `quality/release/readiness.yaml`, nhưng hai file không tồn tại.

**Yêu cầu triển khai:**

1. Triage/fix visual regression và cả hai UI tests.
2. Tách fixture state per test, có launch argument tắt tutorial cho test không kiểm tutorial.
3. CI bắt buộc chạy unit, snapshot, UI smoke, Safari JS, localization scan, Release compile và bundle/privacy checks.
4. Release job phải verify exact tag SHA có receipt xanh từ required workflow; tag owner check không thay thế quality gate.
5. Tạo machine-readable release evidence thật hoặc sửa runbook về cơ chế đang tồn tại.

**Acceptance:**

- Snapshot 3/3 pass trên pinned toolchain sau khi human-review actual image.
- XCUITest 2/2 pass ít nhất ba lần liên tiếp trên isolated simulator.
- Một PR cố tình làm fail snapshot/UI không thể vào release upload path.
- Tag mới không upload nếu exact SHA thiếu required receipts.

### P0-06 — Erase Vault fail-open với CloudKit, shares và Quick Links

**Loại:** Verified data-lifecycle/security blocker.

**Bằng chứng:**

- `Vaultify/App/AppEnvironment.swift:352-360` khởi chạy CloudKit erase, owned-share revoke và inbox disarm bằng ba unstructured `Task`, rồi gọi `eraseLocalState()` ngay.
- `Vaultify/Services/Sync/CloudSyncService.swift:136-148` dùng `try?` và nuốt kết quả/lỗi xóa zone/subscription.
- Approval share revoke cũng best effort; không có durable retry state surviving relaunch.
- `eraseLocalState()` xóa vault keys, sync settings và local revoke-token records. Sau đó app không còn đủ state để tự retry đáng tin cậy.
- Comment trong `AppEnvironment.swift:383-386` xác nhận Quick Links không bị revoke; app xóa revoke tokens và chấp nhận link tồn tại đến expiry.
- `Vaultify/Features/Sharing/LooxLink/LooxLinkConfig.swift:74` cho phép link sống tối đa 2.592.000 giây, tức 30 ngày.

**Repro bắt buộc:** tạo Quick Link 30 ngày, bật CloudKit/Approval sharing, chuyển airplane mode, chọn Erase Vault, kill app ngay sau tap. Dùng thiết bị/browser thứ hai kiểm tra link, shared access và CloudKit copy. Behavior hiện tại có thể báo local erase hoàn tất trong khi remote artifacts vẫn sống; reconnect không có durable job để retry.

**Yêu cầu triển khai:**

1. Tách rõ "Erase from this device" và "Erase everywhere", với copy không hứa quá behavior.
2. Với erase everywhere, dùng state machine/durable tombstone: revoke Quick Links, Approval shares/inbox và CloudKit; lưu retry job không phụ thuộc vault key hoặc trì hoãn phá hủy state cần cho revoke.
3. Cho user thấy pending/failed remote cleanup và action retry sau re-auth/network restore.
4. Thiết kế kill/relaunch idempotent; không để old recovery silently resurrect vault đã báo là erased everywhere.
5. Thêm server-side bulk revoke nếu client không thể bảo đảm thu hồi toàn bộ link trước khi xóa tokens.

**Acceptance:**

- Online: mọi remote object/link bị revoke trước khi UI báo erase-everywhere thành công.
- Offline/kill: local UI nói đúng trạng thái và durable retry tự tiếp tục khi có mạng/credential.
- Second-device/browser verification chứng minh link 30 ngày và share không còn truy cập được sau completion.
- Erase-this-device không xóa remote vault ngoài ý muốn.

## 6. P1 — nên chặn RC cho đến khi có fix hoặc evidence

### P1-01 — Import backup không giới hạn kích thước và tin KDF params từ file

**Loại:** Verified security/availability defect.

- `Vaultify/Features/ImportExport/ImportView.swift:99-113` đọc toàn bộ file bằng `Data(contentsOf:)` mà không giới hạn size.
- `Vaultify/Services/ImportExport/VaultBackup.swift:67-73` decode `KdfParams` do file cung cấp.
- Import path đưa trực tiếp `memoryCostKiB`, `timeCost`, `parallelism` vào Argon2 mà không clamp/validate theo policy app.
- Một `.vaultify` độc hại do user chọn có thể yêu cầu RAM/time rất lớn, gây hang hoặc jetsam trước khi authentication fail.

**Fix/acceptance:** giới hạn file/envelope/artifact/row count; validate version, salt/sealed lengths và KDF allowlist/range trước Argon2; test malicious vectors không OOM/hang; lỗi phải localized và không để partial state.

### P1-02 — Import không atomic; backup contract chưa đủ rõ

**Loại:** Verified data-integrity/product gap.

- `ImportView.performImport()` tạo folder trước, sau đó add items, artifacts, passkeys và Level-2 wrap theo nhiều bước; failure giữa chừng có thể để partial restore.
- Backup chỉ bao gồm items/passkeys/L2/artifacts và folder name gắn với item. Empty folders, personas, aliases, forwarding inboxes, audit history/finding state và preferences không được backup.
- Artifact thiếu bytes bị skip "honestly absent", nhưng UI gọi file là backup mà chưa đưa manifest kết quả rõ ràng.
- Nếu vault đích đã có Level-2 wrap khác, `adoptLevel2WrapIfAbsent` có chủ ý không overwrite. Item từ backup có thể chứa ciphertext dưới L2SK khác và trở nên không đọc được sau khi UI vẫn báo import thành công; cần preflight conflict policy.
- Export dùng `try?` khi adopt legacy attachment và `compactMap` bỏ qua artifact có missing/load/manifest error, trong khi item vẫn có thể giữ `fileRef`. Backup có thể hoàn tất nhưng mất attachment mà user chỉ phát hiện khi restore.

**Fix/acceptance:** transaction/staging + rollback hoặc preflight toàn bộ rồi commit; backup scope và completeness manifest hiển thị rõ; backup portable phải fail hoặc yêu cầu user chấp nhận khi attachment thiếu; định nghĩa Level-2 conflict policy; restore report nêu imported/skipped; round-trip test đủ category và fault injection từng phase.

### P1-03 — Plaintext CSV temp file không có lifecycle cleanup

**Loại:** Verified local data-remanence defect.

- `Vaultify/Features/ImportExport/ExportView.swift:164-178` ghi cố định `temporaryDirectory/loox-export.csv` với complete protection nhưng không xóa khi share hoàn tất, dismiss, lock, background hay app launch.
- Encrypted backup cũng dùng fixed temp filename.

**Fix/acceptance:** unique temp directory/file, cleanup theo share completion/dismiss/lock/launch, protection kiểm tra sau write; automated test không còn plaintext export residue.

### P1-04 — Crafted backup có thể path-traverse qua artifact ID/filename

**Loại:** Verified untrusted-input security defect.

- `Vaultify/Services/ImportExport/VaultBackup.swift:323-350` authenticate blob/hash nhưng không validate shape/path của `id`, `ownerItemId` hoặc `filename`.
- `Vaultify/Services/Artifacts/ArtifactStore.swift:333-358` tạo `relativePath = "\(id).enc"` rồi `fileURL` nối trực tiếp vào artifact root.
- `ArtifactStore.exportPlaintext()` nối trực tiếp `manifest.filename` vào random temp directory.
- Crafted backup với passphrase hợp lệ và `id`/filename chứa `../` có thể làm standardized URL thoát khỏi intended artifact/temp subdirectory và ghi file khác trong app sandbox.

**Fix/acceptance:** yêu cầu artifact ID đúng UUID/canonical allowlist, owner ID đúng shape, filename là basename không separator/control character, giới hạn length; resolve standardized/symlink-safe URL và assert descendant của root trước mọi write; crafted traversal tests phải fail trước file write và để filesystem/store không đổi.

### P1-05 — Chưa có migration test từ store v1.49.1

**Loại:** External/verification gate có tác động data-loss.

- `VaultStore` fatalError nếu persistent container/migration fail.
- Schema có entity mới như `ArtifactRecord`; SwiftData có thể lightweight migrate, nhưng repo không có upgrade fixture hay `VersionedSchema/SchemaMigrationPlan` để chứng minh.

Không gọi đây là bug migration đã xảy ra. Đây là release gate bắt buộc: cài v1.49.1, tạo vault đại diện, upgrade in-place lên RC, unlock/read/edit/export/relaunch và kiểm dữ liệu/passkey/artifact/folder/persona. Lặp lại trong low-storage scenario.

### P1-06 — Shared projection giữ metadata snapshot khi offline/revocation chưa reconcile

**Loại:** Verified behavior, cần product/security decision và live-revoke test.

- `Vaultify/Services/Sharing/SharedItemsProjection.swift:178-239` hydrate `items` và `grants` từ snapshot mã hóa trước network refresh.
- Khi offline hoặc CloudKit zone fetch fail, code có chủ ý giữ projection cũ.
- Detail/AutoFill có live authorization mạnh hơn, nhưng title/subtitle/URL/favicon có thể còn hiển thị từ cache cho đến reconcile.

Không thể thu hồi dữ liệu đã từng được decrypt trên thiết bị offline theo nghĩa tuyệt đối. Yêu cầu thực tế là: fail closed cho secret values, purge ngay khi nhận revocation/live check, không gửi cached shared URL tới favicon service và document offline semantics. Chạy test hai thiết bị: revoke khi recipient online/offline, relaunch, lock/unlock, AutoFill/Safari.

### P1-07 — iPad search không clear query/results

**Loại:** Verified UI bug.

- `Vaultify/Features/Main/VaultSidebarView.swift:69-75` chỉ gửi search query khi string không rỗng.
- `Vaultify/Features/Search/SearchScreen.swift:62-77` chỉ cập nhật từ event `.query`.
- Xóa hết nội dung search ở sidebar làm detail tiếp tục hiển thị query/result cũ.

**Fix/acceptance:** dùng binding hai chiều hoặc gửi `.query("")`; UI test iPad clear bằng nút và bàn phím; result/title/empty state reset đồng bộ.

### P1-08 — iPad orientation/multitasking chưa có contract và evidence

**Loại:** Verified config gap + external validation gate.

- `Project.swift:111-119` khai báo portrait + hai landscape, thiếu portrait upside-down cho cả app và không có override `~ipad`.
- Không set Requires Full Screen, trong khi app dùng adaptive split UI và có vẻ muốn multitasking.
- Apple nói multitasking app phải hỗ trợ mọi orientation; iPad nên bật upside-down. Xem [supportedInterfaceOrientations](https://developer.apple.com/documentation/uikit/uiviewcontroller/supportedinterfaceorientations).
- Test targets chỉ có `.iPhone`; CI không có iPad destination.

**Quyết định cần owner:** hỗ trợ iPad multitasking/windowing đầy đủ hay opt-out full screen. Với sản phẩm hiện tại, khuyến nghị hỗ trợ đầy đủ, thêm iPad-specific orientation list gồm cả bốn orientation và test Split View/Stage Manager.

### P1-09 — Navigation continuity có nguy cơ mất khi size class đổi

**Loại:** Likely defect cần repro.

- `Vaultify/Features/Main/AdaptiveRootView.swift:20-28` thay toàn bộ compact shell bằng `NavigationSplitView` khi size class đổi.
- Compact detail đi qua UIKit navigator; `UIStateStore` chủ yếu giữ SwiftUI paths.
- Resize Stage Manager/Split View khi đang ở detail/sheet có thể trả user về root hoặc tab cũ.

**Acceptance:** automated/manual scenario đang mở item/settings/profile/space/search, resize regular ↔ compact nhiều lần, rotate và background/foreground; selection/detail phải giữ đúng hoặc chuyển state có chủ ý.

### P1-10 — Accessibility/Reduce Motion/Reduce Transparency chưa đạt contract

**Loại:** Verified code gaps + cần visual audit.

- App-level "Reduce Motion" setting chủ yếu chỉ ảnh hưởng mesh animation đang bị feature-gate off; nhiều view chỉ đọc system setting.
- `ThemedToggleStyle.swift:38` còn animation trực tiếp; một số nhánh reduce-motion vẫn crossfade.
- `CopyToastOverlay.swift:13-25` luôn dùng material; `EditorFieldRow.swift:449-466` vẫn dùng `.regularMaterial` trong nhánh Reduce Transparency.
- Theme cards thiếu VoiceOver `.isSelected`: `ChooseThemeView.swift:68-90`, `AppearanceSettingsView.swift:46-88`.
- Một số control có khả năng dưới 44pt: `HomeScreen.swift:703-730`, restore links trong `WelcomeLandingView.swift:135-143` và `JoinVaultFlow.swift:185-191`.
- `LooxHubScreen.swift:113-117` dùng `.minimumScaleFactor(0.65)`, `LargeTypeView.swift:156-160` dùng `0.5`, thấp hơn Design DNA floor `0.7`.

**Acceptance:** pass VoiceOver, AX XXXL, Reduce Motion, Reduce Transparency, Increased Contrast trên SE/Pro Max/iPad Split View; không có text bị cắt, invisible control, motion trái setting, hit target dưới 44pt.

### P1-11 — Subscription và signed capability readiness chưa được chứng minh

**Loại:** External gate.

`Loox.storekit` có bốn subscription product ID, nhưng local StoreKit config không chứng minh App Store Connect state. Trước submit phải xác nhận:

- Subscription group và bốn product Ready to Submit/Approved theo release plan.
- Localization, giá, review screenshot, tax/category, terms và privacy hoàn tất.
- IAP được attach vào app version nếu submit lần đầu.
- Review sandbox mua/restore/upgrade/downgrade/cancel hoạt động.
- Nếu chưa sẵn sàng, tắt beta purchase surface; reviewer không được thấy paywall nửa hoàn thiện.

Signed device phải chứng minh profiles chứa App Group, Keychain Group, AutoFill, Associated Domains, CloudKit/iCloud và production APNs đúng target. `match readonly:true` không tự sửa profile stale.

## 7. P2 — nên sửa trước review hoặc ghi follow-up có owner

### UI/copy/design system

- Nhiều string trên iPad vẫn nói "iPhone": `HomeScreen.swift:796`, `JoinVaultFlow.swift:194-201`, `QuickLinkView.swift:117-120`, `AboutView.swift:67-76,94-102`, `ShareAccessSheet.swift:762`, `ShareSpaceSheet.swift:357`, `ShareResumeStepperSheet.swift:79`, `ItemDetailScreen.swift:841-848`. Đổi sang "device" khi chức năng không thật sự iPhone-only và localize EN/VI/JA.
- `WatchtowerEmptyState.swift:11-50` có artwork/Spacer fixed, dễ clip ở AX XXXL hoặc Split View hẹp.
- Restore sheet chưa dùng content-width clamp trên iPad.
- AutoFill UI còn SF Symbols/raw semantic colors ở `VaultifyAutoFill/AutoFillView.swift`, `UnlockGate.swift`, `OneTimeCodeView.swift`, trái Polaris/token contract.
- Onboarding `OnboardingFlow.swift:119` vẫn dùng SF Symbol `chevron.backward`.
- Docs yêu cầu native tab bar, nhưng pre-iOS 26 dùng `LegacyChipTabBar`; cần chốt docs hay implementation là source of truth.
- Safari popup dùng màu cố định; theme parity là polish, không nên chặn extension functionality nếu contrast/accessibility pass.

### Extension/package metadata

- `VaultifySafari/Resources/manifest.json:6` hardcode version `1.0`, không đồng bộ `1.50.0`. App Store dùng CFBundle version cho submission, nhưng manifest drift gây nhầm debug/upgrade; sinh tự động từ `MARKETING_VERSION` hoặc có test parity.
- `Project.swift:18` `defaultKnownRegions` chỉ có EN/VI trong khi product có JA; archive hiện vẫn chứa catalog JA, nhưng config nên thống nhất và có bundle test.
- Safari `host_permissions` là `https://*/*`; đây là hợp lý cho password autofill nhưng App Review Notes phải giải thích, UI xin quyền phải có purpose string rõ.

### Tooling/docs

- `Makefile` vẫn pin `name=iPhone 16` và chạy explicit Xcode action/path trái runbook hiện tại; sửa để gọi các script CI đã được pin.
- Release Fastlane dùng output/derived-data path riêng và workflow không publish đầy đủ receipt. Chuẩn hóa để local/runbook/CI cùng một source of truth.
- `metadata/apple/**` trong repo chỉ có release notes; nếu metadata được quản lý ngoài repo, phải có checklist/export snapshot để audit được.
- Docs nhắc release evidence/readiness files không tồn tại.
- Release compiler warnings đã liệt kê ở mục 4.

## 8. Fresh-install và sample-data review

### Behavior production hiện tại

Sau onboarding fresh create, app:

1. Tạo vault bằng master password.
2. Tự bật iCloud sync.
3. Tạo Space `My Space`.
4. Thu thập tên và email của user.
5. Seed một **Identity thật**, đặt làm default identity, chứa tên/email, welcome note và starter tag.
6. Tạo Emergency Kit/recovery envelope theo best effort.
7. Không seed login/password/passkey/card giả.

Login "Acme" chỉ là DEBUG UI-test fixture, không có trong production. Vì đã seed Identity, copy "Add your first item" ở done screen không còn chính xác; nên là "Add your first login/password" hoặc copy tương đương đã localize.

### Bug/edge case onboarding

- `generateRecoveryKit()` bị bọc `try?`; nếu fail, `recoveryKey` rỗng và flow có nguy cơ không có lỗi/retry đủ rõ.
- `enableBiometric()` bỏ qua error nhưng vẫn advance tới done, có thể khiến user tưởng biometric đã bật.
- Welcome forced-light trước khi user chọn appearance là behavior có chủ ý trong settings migration, nhưng cần xác nhận design; smoke dark-system vẫn render trang welcome sáng.
- AX XXXL trên iPad vẫn mở và scroll được, nhưng feature-card headings hyphenate rất mạnh; cần visual acceptance theo DNA matrix.

### Khuyến nghị sample data cho Apple Review

Không nên âm thầm seed password giả vào vault cá nhân của mọi user. Hai lựa chọn an toàn:

1. **Khuyến nghị:** giữ production không có credential giả, nhưng thêm App Review Notes chi tiết và một public HTTPS form do team kiểm soát để reviewer tạo/test login, AutoFill và Safari trong vài phút.
2. Nếu product muốn demo data: cung cấp action explicit "Add sample login", ghi rõ sample/removable, không dùng credential thật, không gửi analytics domain/value, và user có thể bỏ qua. Không tạo behavior chỉ dành riêng cho reviewer.

Identity seed là dữ liệu thật của user, không nên gọi là sample. Nếu giữ, onboarding phải nói rõ nó sẽ được tạo và nơi lưu/sync của nó.

## 9. App Review readiness checklist

### Binary và signing

- [ ] Tạo tag mới sau fix, ví dụ `v1.50.1` với build number > 78. Không di chuyển hoặc tái sử dụng tag `v1.50.0`.
- [ ] Signed archive từ exact tag SHA.
- [ ] Xcode Validate/Transporter pass.
- [ ] IPA chỉ chứa app + AutoFill iOS + Safari iOS; không có Mac binary.
- [ ] Version/build đồng bộ cả ba bundle.
- [ ] Entitlements trong signed IPA khớp profile và source.
- [ ] Privacy manifest có trong cả ba executable bundle, Privacy Report sạch.
- [ ] dSYM upload Crashlytics thành công và có receipt.
- [ ] `LooxLinkAppToken` production không rỗng; không ghi token vào log/report.

### App Store Connect

- [ ] Kiểm tra trạng thái build 78/tag `v1.50.0`; không submit build này trong khi report còn NO-GO.
- [ ] Description, subtitle, keywords, support URL, marketing URL, privacy URL đúng và hoạt động.
- [ ] Privacy labels phản ánh app + Firebase + favicon/network services + third-party partners.
- [ ] Age rating, category, regions, export compliance được owner/legal xác nhận.
- [ ] iPhone screenshots đầy đủ.
- [ ] iPad 13-inch screenshot set đầy đủ; Apple ghi rõ required nếu app chạy trên iPad. Xem [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
- [ ] App Review contact và notes đầy đủ.
- [ ] Subscription/IAP attach đúng version, review screenshot và sandbox pass.
- [ ] Không tạo/submit macOS version trong đợt này.
- [ ] Tắt "Make this app available on Mac"/Apple Silicon Mac availability nếu product không muốn phân phối bản iPad trên Mac.

### Runtime QA matrix tối thiểu

| Matrix | Required scenarios |
|---|---|
| iPhone SE/375, Pro Max/430 | Fresh install, restore, unlock, CRUD, import/export, lock/relaunch, theme/live switch |
| iPad 11/13 inch | Portrait/landscape, fullscreen, Split View hẹp/rộng, Stage Manager resize, keyboard |
| iOS/iPadOS 17.3 | Password AutoFill + passkeys, deployment floor |
| iOS/iPadOS 18 | OTP AutoFill + passkey upgrade paths |
| iOS/iPadOS 26.2+ | Save/generate credential capabilities, toolbar/accessibility rendering |
| Accessibility | AX XXXL, VoiceOver, Reduce Motion, Reduce Transparency, Increased Contrast |
| Security state | No biometric, Face ID changed/locked out, app group unavailable, offline, iCloud signed out |
| Data | Empty/large vault, artifacts, L2 fields, archived/trashed, v1.49.1 upgrade |
| Sharing | Two Apple IDs/devices, accept/revoke online/offline, ask-each-time, push delay |
| Extensions | AutoFill/Safari on iPhone+iPad, large vault/memory pressure, lock/relock, concurrent access |

## 10. Draft App Review Notes sau khi blocker đã fix

Nên gửi bằng tiếng Anh để giảm ma sát với reviewer. Thay text trong ngoặc vuông trước submission:

> Loox is an offline-first password and passkey manager. No Loox account is required. On first launch, choose Get Started, create a master password, save the Emergency Kit, and complete onboarding. The app creates a default identity from the name/email entered during setup; it does not add a fake password credential.
>
> To test a login, tap Add, choose Login, and use the public test form at [REVIEW TEST URL]. The reviewer may use any non-sensitive sample username/password. To test system AutoFill, enable Loox under Settings > General > AutoFill & Passwords. To test the Safari extension, enable Loox in Settings > Apps > Safari > Extensions and allow it on the review test site. The extension requests HTTPS website access only to detect credential fields and fill a credential after the user explicitly selects it; vault values are returned only through the gated fill command.
>
> Face ID is optional. If biometrics are unavailable, use the master password. iCloud vault sync is optional and remains off until the reviewer explicitly enables it [MUST MATCH FIXED PRODUCT]. Approval Mode sharing uses separate controls. The app remains functional offline for local vault operations.
>
> Subscription surfaces are available in the App Review sandbox. The four products attached to this submission are [LIST PRODUCT IDS/TIERS]. Terms and Privacy links are available from the paywall and resolve to [FINAL URLS].
>
> For assistance during review, contact [NAME, EMAIL, PHONE].

Không đưa master password cố định hoặc credential thật vào notes nếu reviewer tự tạo được. Nếu có state phức tạp cần preloaded data, cung cấp cách tạo deterministic bằng UI hoặc một demo account/QR phù hợp với guideline, không dùng backdoor/reviewer-only behavior.

## 11. Kế hoạch giao cho team agents

### Phase 0 — owner decisions, trước khi agents code

1. Firebase Analytics/Crashlytics: giữ, opt-in hay loại khỏi production?
2. Favicon: default off, direct-site, privacy proxy hay bỏ feature?
3. iCloud fresh-create: default off hay explicit consent step?
4. iPad: full multitasking/windowing hay full-screen-only?
5. Sample data: App Review Notes only hay explicit removable sample login?
6. Subscription: submit trong version này hay tắt toàn bộ purchase surface?
7. Erase contract: "this device" và "everywhere" sẽ được diễn đạt/xử lý thế nào?

### Phase 1 — release blockers, có thể chạy song song

**Agent A — Privacy/legal/subscription**

- Ownership: `PrivacyInfo.xcprivacy`, `Project.swift` target resources, `LooxMembership.swift`, analytics/privacy settings và website/ASC checklist.
- Deliverable: three-target manifests, legal URL fix, privacy behavior inventory, policy/ASC handoff, bundle tests.

**Agent B — Onboarding/privacy defaults**

- Ownership: `OnboardingFlow`, `JoinVaultFlow`, `SettingsStore`, `FaviconService`, favicon cache lifecycle, localization.
- Deliverable: explicit sync choice, recovery/biometric error handling, favicon consent/cache/erase tests, truthful done copy.

**Agent C — Quality/release gate**

- Ownership: snapshot/UI tests, fixtures, `.github/workflows/ci.yml`, `.github/workflows/release-ios.yml`, `scripts/ci/**`, release evidence/runbook.
- Deliverable: all red tests fixed, exact-SHA required gates, machine-readable receipt.

Agents không được sửa cùng `Project.swift` nếu chưa chia commit/ownership rõ; Agent A nên là owner duy nhất của file trong Phase 1.

### Phase 2 — data safety

**Agent D — Import/export/erase/migration**

- Bound untrusted import và KDF params.
- Validate artifact ID/filename và chặn path traversal trước mọi file write.
- Làm restore atomic hoặc staged/rollback.
- Định nghĩa Level-2 conflict và backup completeness/attachment policy.
- Temp export cleanup.
- Durable remote erase semantics, bao gồm Quick Link bulk revoke.
- v1.49.1 migration fixture/e2e.

Nên chia thành các PR nhỏ vì đây là vùng data-loss/security; mỗi PR cần fault-injection tests và independent review.

### Phase 3 — iPad/UI/accessibility

**Agent E — iPad adaptive UX**

- Search clear bug.
- Orientation contract và iPad-specific plist.
- Compact/regular continuity.
- iPad fullscreen/Split View/Stage Manager UI tests.

**Agent F — Design DNA/accessibility**

- Touch targets, VoiceOver selected traits, Dynamic Type floor, Reduce Motion/Transparency, copy "iPhone" → "device".
- AutoFill Polaris/token migration.
- EN/VI/JA translations bắt buộc cho mọi string thay đổi.

### Phase 4 — independent red-team và signed RC

1. Code-reviewer không tham gia implementation rà lại privacy, crypto/data migration, extension command boundary và release workflow.
2. Tạo signed RC từ tag mới.
3. Inspect archive/IPA/privacy report/entitlements.
4. Chạy full device matrix và lưu evidence.
5. Audit App Store Connect cùng owner; chỉ chuyển NO-GO → GO khi checklist mục 9 xanh.

## 12. Definition of Done để đổi sang GO

Release chỉ được coi là ready khi tất cả điều kiện sau đúng trên **cùng một exact SHA/tag**:

1. P0-01 đến P0-06 đóng bằng code + test + evidence.
2. Mọi unit/snapshot/UI/Safari/localization/Release gate pass.
3. Signed archive và Transporter validation pass; three-target privacy report sạch.
4. Upgrade v1.49.1, fresh install và erase/import/export data-safety scenarios pass.
5. iPad portrait/landscape/Split View/Stage Manager/accessibility matrix pass.
6. AutoFill + Safari pass trên iPhone và iPad thật ở OS floor và OS hiện hành.
7. Terms/Privacy/Support URLs trả 200 và nội dung được legal/product phê duyệt.
8. App Store privacy labels khớp runtime/network behavior.
9. IAP/subscriptions attach và sandbox pass, hoặc purchase surfaces bị tắt hoàn toàn.
10. iPad 13-inch screenshots, review notes/contact và toàn bộ metadata hoàn tất.
11. Mac version không được submit và Apple Silicon Mac availability đã tắt theo quyết định release.
12. Owner ký release checklist; tag cũ không bị di chuyển.

## 13. Điểm tốt nên giữ nguyên

- Shared Safari/native bridge có command allowlist rõ; `getFillPayload` vẫn là command duy nhất trả vault values.
- Origin được bind từ trusted Safari sender/tab; fill payload có scope và expiry.
- Save-login có validation, rate limit và duplicate detection.
- AutoFill OTP/passkey/save/generate có compiler/availability guard.
- App/AutoFill/Safari đồng bộ version/build/device family và nhúng đúng trong local Release product.
- iOS archive local không kéo theo `VaultifyAutoFillMac`.
- Unit suite khá rộng và đang xanh hoàn toàn.
- EN/VI/JA catalog parity hiện tốt; Safari locales đồng nhất.
- Release workflow đã pin actions/toolchain, giới hạn actor và verify tag reachable từ `main`; cần bổ sung quality dependency chứ không phải thay toàn bộ.

## 14. Tài liệu Apple dùng làm chuẩn

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Review submission/common issues](https://developer.apple.com/app-store/review/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Required-reason API categories and reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [iPad/iPhone screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Upload screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [In-app purchase information/review assets](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
- [Packaging/distributing Safari Web Extensions](https://developer.apple.com/documentation/safariservices/packaging-and-distributing-safari-web-extensions-with-app-store-connect)
- [Encryption export-compliance Info.plist key](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)

`ITSAppUsesNonExemptEncryption = false` hiện được source giải thích là app chỉ dùng exempt standard encryption cho dữ liệu user. Audit này không kết luận key đó sai; owner cần giữ hồ sơ export-classification/legal rationale để trả lời khi Apple yêu cầu.

## 15. Quyết định cuối

**NO-GO cho App Review ở commit/tag hiện tại.**

Buildability và core logic tests đang ở trạng thái tốt, nhưng privacy manifest/legal disclosure, opt-in behavior, favicon privacy và release quality gates là blocker thực tế. Sau khi xử lý Phase 1 và data-safety P1 quan trọng, team cần tạo **tag/version mới**, không tái sử dụng `v1.50.0`, rồi chạy signed RC + App Store Connect/device matrix trước khi đưa iPhone/iPad lên Store.
