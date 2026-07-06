# Report: Xác minh 5 yêu cầu A–E (Persona / Relay Principal / Cloudflare / Security primitives / DNS)

Ngày: 2026-07-06 · Trả lời proposal author sau round 2 · Nguồn: code audit iOS repo + BE repo + DNS live + Cloudflare docs hiện hành (last-updated 2026-06-09)

## TL;DR

| Yêu cầu | Kết quả |
|---|---|
| A. Folder semantics | **App ĐÃ brand Folder = "Space" toàn bộ UI.** Hybrid nghiêng workspace. Promotion đúng hướng, cần close 3 gap. |
| B. Relay Principal | **Highly feasible, gần như zero crypto mới** — `ParticipantIdentity` + `ParticipantEscrowService` là blueprint drop-in. P256 (Ed25519 không dùng ở đâu). |
| C. Cloudflare 2026 | Xác nhận toàn bộ claims của proposal author, **1 caveat quan trọng: Email Sending vẫn BETA** (Routing GA). Account plan cần dashboard. |
| D. Primitive extraction | Khả thi, có bảng module-by-module. Phát hiện thêm 1 parity gap ngoài `one_time`. Workspace pnpm chưa formal. |
| E. DNS | Zone trên Cloudflare NS. **Zero MX/SPF/DMARC — domain hiện KHÔNG nhận được email nào**, kể cả `support@looxpassword.com` đang in trên marketing site (bug độc lập). Rollback risk = không có (không có mail flow để phá). |

## A. Folder semantics audit

**Verdict: hybrid, nghiêng workspace — và product đã tự quyết một nửa rồi.**

Bằng chứng workspace-like:
- Model doc + toàn bộ UI strings gọi Folder là **"Space"** (`Folder.swift:3-5`, `ManageFoldersScreen.swift:36` titled "Spaces", `HomeHeaderBar.swift:145` "Manage Spaces & Members").
- Home có **Space switcher** filter toàn bộ Home feed (`HomeScreen.swift:20,404-438`); single-Space auto-scope (`:60-68`); item mới default vào Space đang chọn hoặc primary = `folders.first` (`ItemEditorScreen.swift:144-154`).
- "Shared with Me" render như pseudo-space ngang hàng (`ItemsScreen.swift:96-105`).
- Fixtures/tests dùng tên org/project: "Acme", "Acme Corp", "Work", "My Vault" — **không có** "Banks/Social/Shopping" taxonomy style.

Bằng chứng chưa-đủ-workspace (3 gap phải close nếu promote):
1. `selectedFolderId` là `@State` thuần — **không persist qua launch** (không @AppStorage/SceneStorage).
2. **Search global**, không scope theo Space (`VaultRepository+Folders.swift:230-241`; Space name lại searchable như text).
3. Không có primary/default flag trên `FolderRecord` — "primary Space" chỉ là `folders.first` theo sortIndex.

Khác: seed "My Vault" rename/delete tự do, không guard; item optional-single-folder ("None"/Unfiled); delete folder → items về Unfiled.

**Khuyến nghị dev team:** promotion (harden Space đang có) thay vì entity mới — codebase đã chọn tên và UX. Model `Persona → Space → Folder` 3 tầng của bạn sẽ là **thêm 1 tầng mới lên trên UX hiện có** chứ không phải promotion, và hiện chưa có tín hiệu user cần 2 tầng grouping (+1 entity, +1 navigation level, YAGNI). P0A decision còn lại thu hẹp thành: (a) thêm `isPrimary`/persona-scope vào Space nào, (b) search scope theo Space hay giữ global, (c) persist selected Space. Lưu ý string "Manage Spaces & Members" cho thấy vision Space-as-sharing-boundary đã manh nha — khớp P5.

## B. Relay Principal feasibility

**Đồng ý với blocker của bạn, và tin tốt: pattern này đã tồn tại 3 lần trong codebase.**

Precedents "secondary secret sealed under Vault Key":
1. `PasskeyEnvelope` — Curve25519 private key sealed dưới Vault Key, trong `VaultKeyBundle` (`PasskeyEnvelope.swift:89-95`).
2. **`ParticipantIdentity.escrowSealed`** (`ParticipantIdentity.swift:29-42`) — key thuộc về USER (không phải device), mở được trên mọi device đã unlock. **Đây là analog gần nhất của Relay Principal.**
3. `SharedCredentialsCache` blob.

Blueprint drop-in: **`ParticipantEscrowService`** (`Vaultify/Services/Sharing/ParticipantEscrowService.swift`) — singleton CloudKit record trong private DB zone `Vault`, transactional create với `.ifServerRecordUnchanged` + **first-writer-wins** collision adoption (chống fork khi 2 device đua), local Keychain cache, **tự tạo zone** nên hoạt động kể cả khi `iCloudSyncEnabled` OFF (chỉ cần `VAULTIFY_ICLOUD` compile flag). Clone service này, thay Curve25519-agreement bằng `P256.Signing`, thêm record type `RelayPrincipalEscrow`.

Curve: codebase dùng **P256.Signing** cho mọi chữ ký (`DeviceSigningIdentity`, grant signatures, WebAuthn) và Curve25519 chỉ cho HPKE/agreement. **Ed25519 = 0 hit.** → Relay Principal nên là P256, khớp convention + reuse `DeviceSigningIdentity.signature/verify` shape.

Scenario analysis:
- **Reinstall same device**: Keychain + App Group wipe khi uninstall → principal mất local, **tự phục hồi từ CloudKit escrow** sau unlock. ✅
- **New device**: join qua QR pairing (HPKE handoff) hoặc Emergency Kit → có Vault Key → fetch-or-adopt escrow → cùng 1 principal. ✅
- **Total device loss**: Emergency Kit restore Vault Key; principal ciphertext đã sync nên mở lại được. ✅ **Điều kiện: escrow phải là CloudKit record synced** — nếu chỉ nằm local bundle/Keychain thì KHÔNG survive.
- **Revoke/rotation**: ❌ chưa có primitive. Bump-and-overwrite singleton thì dễ, nhưng để relying party (relay backend) REJECT key cũ cần epoch/pin machinery kiểu `AccessGrant.epoch` — phải design. Lưu ý device identities hiện throw-not-regenerate khi corrupt chính vì silent key replacement phá pin.
- **Erase Vault**: `eraseRemote` drop nguyên zone `Vault` → principal escrow chết theo. Cần quyết: đó là "revoke everything" mong muốn, hay principal phải outlive erase (dev team nghiêng: chết theo là đúng — erase = user muốn biến mất; backend cần endpoint disable-all-aliases-by-principal để dọn phía server).

Open design questions cho bạn:
1. Principal cần thêm role HPKE-decrypt không (2 keys như device identities), hay chỉ signing?
2. Escrow trong `VaultKeyBundle` (tự động ride recovery) vs dedicated CloudKit record (hoạt động khi item-sync off, theo ParticipantEscrowService)? Dev team khuyến nghị **dedicated record** — đã có blueprint + independent lifecycle.
3. Non-`VAULTIFY_ICLOUD` builds: escrow no-op → relay feature phải gate trên iCloud availability (hợp lý: relay vốn cần mạng).

Request model đồng ý 2 chữ ký: `LOOX-RELAY-AUTHZ-V1` (principal signs command) + App Attest assertion (device admission, transcript riêng phủ đúng HTTP command). Defense in depth, mỗi lớp một câu hỏi.

## C. Cloudflare 2026 spike (docs last-updated 2026-06-09)

Đối chiếu docs hiện hành, xác nhận:
- Email Routing limits: **200 rules/domain, 200 verified destinations/account, 25 MiB/message** — đúng như bạn nói. Sends tới verified destinations **free, không tính quota, mọi plan**.
- `forward()` **chỉ tới verified destinations** — xác nhận, Path A ceiling giữ nguyên.
- `reply()` **tồn tại** với restrictions: incoming phải pass DMARC, 1 reply/event, recipient = sender gốc, sender domain = domain nhận, References ≤ 100 entries. → Xác nhận correction của bạn: quyết định receive-only V1 nên ghi là **product decision** (UX/thread-routing chưa kiểm soát được), không phải "Cloudflare không reply được". P5 nghiên cứu Cloudflare-native reply là hướng hợp lệ.
- Email Sending (arbitrary recipients): Workers Paid ($5/mo), **3.000 emails included/tháng/account**, sau đó **$0.35/1k**. Suppression-list rejects không tính quota. 3 integration: Workers binding, REST API, authenticated SMTP.

**⚠️ Caveat dev team bổ sung: Email Sending status = BETA** (Email Routing GA, Sending beta trên overview page hiện hành). Hệ quả cho P4C: Path B (Cloudflare Email Sending) là candidate benchmark chính đáng nhưng **chưa được coi là production-committed** — spike P4C giữ nguyên thiết kế "đo cả A/B" của bạn, thêm tiêu chí: beta SLA/GA timeline. Fallback SES/Postmark từ "mặc định" hạ xuống "contingency" — khớp verdict của bạn.

Bổ sung: Workers **Free** plan có CPU/memory limit có thể fail email handlers (`EXCEEDED_CPU`) → ingress worker nên chạy Workers Paid bất kể, cùng plan mở Email Sending.

**Không verify được từ repo/CLI: account hiện Free hay Paid, Email Sending beta access cho account.** Cần dashboard (account `f318e1b1b12cfff2570858cd0ba3f8e5`).

## D. Security primitive extraction audit

Bảng extractability (`workers/loox-link/src/`):

| Module | Verdict |
|---|---|
| `errors.ts`, `authdata.ts`, `attestation.ts`, `assertion.ts`, `chain-verify.ts` (trust anchor đã là param), `apple-root.ts` | **Generic — move as-is (Tier 1, pure, no I/O)** |
| `security.ts` nửa util (`safeEqual`, `sha256Hex`, `randomId`, `nowSeconds`, `securityHeaders`, `json`) | **Generic (Tier 1)** |
| Transcript **framing** (u16/u32/u64/concat/textField + canonicalHash) | **Generic (Tier 1)** — MAGIC + field list ở lại từng worker |
| Challenge store + `key-store.ts` (sign_count CAS) | **Needs-parameterization (Tier 2)**: nhận `D1Database` thay vì `Env`, table name config; `envFromHost` heuristic phải inject |
| `register.ts` | Thin handler ở lại worker, gọi shared verifier |
| `env.ts`, `index.ts`, `shares.ts`, `viewer.ts`, `create-assertion.ts`, VIEWER_CSP | **Share-specific — không extract** |

**Gap `one_time` exact** (`create-assertion.ts:9-11`): transcript V1 phủ MAGIC, method, path, challengeId, SHA-256(ciphertext), iv, u32(cryptoVersion), u64(expiresInSeconds), envelope — **thiếu `one_time`** (thêm ở migration 0003, được `shares.ts:61,95` đọc/ghi nhưng không nằm trong transcript lẫn body type của verifier). Hệ quả dưới `required`: attacker có assertion hợp lệ flip được burn-after-read flag. Phải build transcript V2 trước khi bật `required`.

**Phát hiện parity gap thứ 2 (mới):** `generate-attest-vectors.mjs` **tự re-implement transcript** thay vì import `buildCreateShareTranscript` — không có test nào assert encoder thật khớp vectors JSON (file Swift-parity 59k). Generator claim "byte-for-byte" nhưng là hand-mirror. Khi extract: generator phải import shared encoder + thêm parity test (mirror cách assertion-vectors test đang làm đúng).

Replay inventory đầy đủ: sign_count CAS (`key-store.ts:54-68`), challenge single-use atomic UPDATE + TTL 180s, attestation counter==0, nonce binding, rpIdHash binding, request binding qua clientDataHash. **Không có timestamp window riêng** — freshness dựa hoàn toàn vào challenge; ghi chú cho relay protocol design.

Build implications: pnpm workspace **chưa formal** (`pnpm-workspace.yaml` không có `packages:` glob; worker có lockfile riêng). Extraction cần formalize workspace hoặc path-dependency. `@peculiar/x509` + `cbor-x` đi theo package — tách X.509 path thành optional sub-export để relay (nếu chỉ verify assertion, không register) tree-shake được. `reflect-metadata` phải import đầu tiên tại mọi entry đụng x509 — package phải document.

D1: share DDL text (`attest_challenges`/`attest_keys`) như shared migration file, **mỗi worker own DB riêng** (giữ trust model hiện tại). Câu hỏi cho bạn: relay có cần cross-worker key reuse không (device đã register với loox-link có được relay tin luôn)? Dev team khuyến nghị **không** — separate DB, register lại per-service, tránh coupling trust.

## E. DNS ownership

Live DNS (dig, 2026-07-06):
- NS: `alexis.ns.cloudflare.com` / `vita.ns.cloudflare.com` — zone trên Cloudflare. ✅
- **MX apex: KHÔNG CÓ. TXT/SPF apex: KHÔNG CÓ. `_dmarc`: KHÔNG CÓ. `relay.` subdomain: trống.**

Hệ quả:
1. Email infra greenfield xác nhận ở tầng DNS — khớp code audit.
2. **Rollback risk cho apex khi bật Email Routing: gần như zero** — không có mail flow production nào tồn tại để phá. Lo ngại "apex có production surfaces" đúng với HTTP (marketing/api/s/invite qua Workers custom domains — Email Routing không đụng A/AAAA records) nhưng không có email surface nào cả.
3. 🔴 **Bug độc lập phát hiện:** marketing site đang in `support@…` (và policy pages có thể in security@) — **các địa chỉ này hiện không thể nhận mail** (no MX). Fix rẻ nhất: bật Email Routing apex + 2 routing rules support@/security@ → inbox thật. Việc này tiện thể onboard zone vào Email Routing trước cả relay, tách rủi ro làm 2 bước nhỏ.
4. DNS không as-code (repo không quản lý; Workers `custom_domain: true` chỉ tự tạo record của chính nó). Khuyến nghị: trước P4B, export zone file + đưa DNS vào Terraform/`cf-terraforming` hoặc tối thiểu commit zone snapshot vào BE repo docs — điều kiện bạn đặt ("không bật thủ công trước khi có rollback plan") thành: rollback plan = zone snapshot + revert steps, đủ vì không có mail flow hiện hữu.
5. Account owner: repo ghi `chinhphamnhu@gmail.com` (`docs/deployment-guide.md:10`) — cần bạn confirm quyền dashboard (kiểm tra plan + Email Sending beta access cùng lúc).

## Unresolved questions

1. Account Cloudflare: Free/Paid? Email Sending beta access available? (dashboard-only)
2. Relay Principal: cần HPKE role không, hay signing-only? Escrow dedicated record (khuyến nghị) — confirm?
3. Erase Vault → principal chết theo zone: chấp nhận? (cần backend endpoint disable-all-by-principal để dọn server side)
4. Principal rotation: bump-and-overwrite + server-side re-pin, hay full epoch machinery như AccessGrant? (ảnh hưởng schema relay DB)
5. Search scope theo Space + persist selected Space: 2 quyết định UX cho P0B — bạn chốt hay để dev team đề xuất default?
6. Transcript V2 (`one_time`) build trước khi extract package, hay extract trước rồi V2 sau? (dev team khuyến nghị: V2 trước, package ship encoder đã fix)
7. Relay register App Attest riêng per-service (khuyến nghị) — confirm để chốt D1 boundary?
