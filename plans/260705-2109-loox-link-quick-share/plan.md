# Loox Link — Quick Share Link (share anywhere)

Spec: `~/Developer/Projects/frontend/looxpassword/workers/loox-link/` (openapi.yaml, schemas/*.json).
Goal: cải tiến màn Share hiện tại (Approval/iCloud) — thêm option "Quick Link": encrypt-on-device
snapshot → POST ciphertext → URL `https://s.looxpassword.com/s/<id>#k=<key>`; key chỉ nằm trong fragment.

## Status

| Phase | Scope | Status |
|-------|-------|--------|
| 01 | Core: envelope + AES-GCM crypto + canonical binding + M0 parity XCTest | ✅ done |
| 02 | API client + App Attest (register/assert, fail-closed) + revoke-token store | ✅ done |
| 03 | UI: chooser trong ShareAccessSheet + QuickLink flow + quản lý/revoke + EN/VI l10n | ✅ done |

## Key decisions (ADR)

- **Placement**: `Vaultify/Features/Sharing/LooxLink/` (app-only; extension không cần, tests
  `@testable import Vaultify` vẫn thấy). Không đưa vào VaultifyCore để khỏi kéo DeviceCheck vào appex.
- **Milestones spec M0–M4 gộp**: M0 (parity test, hard gate) + M1 (create/revoke) + M2 (field
  selection/concealed/limits) + M3/M4 (App Attest client đầy đủ, tự bật khi `isSupported`,
  fail-closed khi assert lỗi — không fallback unauthenticated; simulator/dev không supported →
  gửi không header, hợp lệ với local dev Worker đang open).
- **Never in envelope**: TOTP seed (loại field `.totp` hoàn toàn), field `guard2` (extra-protected),
  `fileRef`. Excluded = absent (không phải hidden).
- **Defaults**: username/email + url + password ON (password `concealed:true`); note/custom OFF.
  Expiry presets 1h/24h/7d/30d, default 24h, max 30d (server cap).
- **revoke_token**: Keychain device-local (`KeychainStore`, account `loox-link-records`, JSON array).
  V1: revoke từ máy tạo link (spec cho phép; cross-device sync là câu hỏi mở của backend).
- **Base URLs**: prod `api.looxpassword.com` / `s.looxpassword.com`; DEBUG override qua
  UserDefaults `loox_link_api_base_url` / `loox_link_viewer_base_url` (trỏ 127.0.0.1:8787 khi dev).
- **Fixture test**: copy `app-attest-create-share-vectors-v1.json` vào `VaultifyTests/Fixtures/`
  (load từ bundle, không retype) + thêm `resources` cho test target trong Project.swift.

## Files

- `Vaultify/Features/Sharing/LooxLink/LooxLinkEnvelope.swift` — model + JSON encode (ordered) + build từ VaultItem
- `.../LooxLinkCrypto.swift` — AES-256-GCM (ct‖tag, iv 12B, fragment key b64url) + decrypt (test)
- `.../LooxLinkCanonical.swift` — transcript length-prefixed BE + SHA-256 requestHash
- `.../LooxLinkConfig.swift` — URLs, limits, expiry presets
- `.../LooxLinkAPIClient.swift` — challenges/register/shares/revoke + error mapping
- `.../LooxLinkAttestation.swift` — DCAppAttestService: keyId persist, register-once, assertion
- `.../LooxLinkRecordStore.swift` — Keychain store {shareId, revokeToken, itemId, expiresAt…}
- `.../LooxLinkService.swift` — orchestration create/revoke/list (MainActor, gắn AppEnvironment)
- `Vaultify/Features/Sharing/QuickLinkView.swift` (+ `QuickLinkResultView.swift`, `QuickLinkFieldRow.swift`) — UI
- Sửa: `ShareAccessSheet.swift` (bước chọn mode), `AppEnvironment.swift` (wire service),
  `Project.swift` (test resources), `Localizable.xcstrings` (EN+VI)
- Test: `VaultifyTests/LooxLinkCanonicalTests.swift`, `VaultifyTests/LooxLinkEnvelopeTests.swift`

## Success criteria

- M0: 5/5 vectors parity (bytes + hash) — XCTest xanh.
- `make check` sạch (app + extension), `make test` pass.
- UI: chọn field → tạo link → copy/share; revoke; đủ EN+VI; token-driven design (Space/Radius/Metric,
  Polaris icons, themed colors).
- Không log URL/fragment/revoke_token.

## Deliverables còn lại cho backend (ngoài scope repo này)

- Capture pack attestation từ real device (debug harness) → `workers/loox-link/fixtures/app-attest-local/`.
- Confirm Team/Bundle: `WDNL2F75V7.com.bervion.vaultify` (khớp AASA).

## Post-QA fixes (260705)

- Bug thực địa: máy thật chạy App Attest → `/v1/attestation/register` **chưa tồn tại trên Worker**
  (openapi: frozen contract, chưa enable — C2c/C7) → 404 → app hiện nhầm "Liên kết này không tồn tại".
- Fix: `LooxLinkConfig.attestationEnabled = false` (bật lại khi backend ship C7); create-404 remap thành
  server error (không còn copy gây hiểu nhầm); DEBUG log `[LooxLink] METHOD path → status code`.
- Env: DEBUG mặc định **staging** (`api-staging`/`s-staging`), Release = prod. Create auth hiện tại =
  interim `X-Loox-App-Token` — đã rotate secret staging qua wrangler, app đọc từ UserDefaults
  `loox_link_app_token` (không commit token). Round-trip staging đã verify bằng curl:
  create 201 → get 200 → revoke 204 → get 404.

## One-time links + short expiries (260705, request bổ sung)

- Presets thêm: 5/10/15/30 phút (client-only; server cap 30d không đổi).
- **One-time (burn after read)**: backend thêm cột `one_time` (migration 0003), GET claim nguyên tử
  bằng `DELETE … RETURNING` (2 reader đua → 1 thắng, 1 nhận 404); response GET thêm `one_time`.
  Viewer: hint `o=1` nằm TRONG fragment (`#k=…&o=1`, server không bao giờ thấy) → hiện nút
  "View share" trước khi fetch, chống link-preview bot đốt lượt xem duy nhất.
- App: toggle "One-time link", badge trong Active links, note ở result; `LooxLinkRecord.oneTime`
  decode tương thích ngược (registry cũ trong Keychain không bị drop).
- Đã migrate + deploy staging, verify curl: one-time GET#1 200 → GET#2 404; link thường không đổi.
- ⚠️ `one_time` KHÔNG nằm trong App Attest transcript V1 (frozen) — backend phải bind vào
  transcript V2 trước khi bật assertion (đã ghi chú trong openapi.yaml).
- Production worker CHƯA deploy bản one-time (migration 0003 + deploy prod là việc backend khi release).

## Prod go-live (260705, tối)

- BE deploy full staging+prod (one_time live cả 2 env, FE verify). App Attest **CHƯA wire**
  (register/assert = C7, còn chờ dev attestation blob đóng C2c) → `attestationEnabled` phải
  giữ **false** (bật true khi C7 ship — đã revert sau yêu cầu bật nhầm thời điểm).
- Prod `APP_CREATE_TOKEN`: đã set (random, qua wrangler) + verify curl trên prod:
  one-time create → GET 200 → GET 404; regular create → revoke 204.
- App đọc token theo thứ tự: UserDefaults `loox_link_app_token` (dev) → Info.plist
  `LooxLinkAppToken` (inject lúc `tuist generate` từ env `TUIST_LOOX_LINK_PROD_TOKEN`,
  set trên CI runner — token không nằm trong git). Đã verify inject/rỗng cả 2 chiều.
- Việc của user: lưu 2 token (staging + prod) vào password manager, set env
  `TUIST_LOOX_LINK_PROD_TOKEN` trên runner, xoá file token trong scratchpad.

## Unresolved questions

- Cross-device revoke: đợi backend chọn (synchronizable keychain vs vault channel) — V1 device-local.
- Viewer copy khi revoked/expired đã chuẩn ("no longer available") — không cần app xử lý thêm.
