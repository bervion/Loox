# Report: Xác minh 8 câu hỏi + đánh giá proposal Persona / Email Alias

Ngày: 2026-07-06 · Branch: feat/shared-vault-hardening-v2 · Người xác minh: dev team (Claude)

## Phần A — Trả lời 8 câu xác minh (đối chiếu code thật)

### 1. Space ownership hiện tại

**"Spaces" KHÔNG tồn tại như proposal giả định.** Thực tế:

- App có đúng **1 vault** (1 Vault Key, 1 SwiftData store). Không có multi-vault.
- Grouping = **Folder** (`VaultifyCore/Models/Folder.swift:10`, `VaultifyCore/Store/FolderRecord.swift:9`): mỗi item thuộc **tối đa 1 folder** qua `VaultItem.folderId` (`VaultItem.swift:8`), `nil` = Unfiled, move được. Tên folder sealed; icon/color/sortIndex plaintext.
- **Tags** = nhiều-per-item, nằm trong sealed `ItemSecret` (`ItemSecret.swift:120`).
- **Không có ownerUserId** — app không có account. Sharing (Approval Mode) là **capability delegation per-ITEM** qua CKShare (`VaultifyCore/Sharing/ApprovalModels.swift`), owner = `ownerSigningPubKey`/`ownerSignature` (`:222,311`). "Shared with Me" chỉ là space ảo trong UI, không phải folder thật. Secret không rời vault owner; recipient nhận projection read-only, không sync/backup.
- Onboarding seed folder "My Vault" mặc định (rename được).

### 2. Identity vault type hiện tại

- Enum: `ItemCategory` = login/note/card/identity/sshKey/recoveryCodes/securityQuestions/custom (`ItemCategory.swift:5`).
- Identity template (`ItemCategory.swift:69-78`): Full Name, Email, Phone, Address, DOB, ID Number (protected). **Không phải typed struct** — là `[DynamicField]` trong sealed `ItemSecret` (`VaultItem.swift:115-135`).
- Cột riêng trên `ItemRecord`: `isDefaultIdentity: Bool` (plaintext, SYNCED, `ItemRecord.swift:40`) + `avatarSealed: Data?` (ciphertext, `:50`).
- Invariant: đúng 1 identity active là default — `normalizeDefaultIdentity()` (`VaultRepository.swift:147-168`) hội tụ conflict theo max(updatedAt, createdAt); gate chặn trash identity active cuối (`VaultRepository+Identity.swift:32-43`).
- Onboarding seed: `IdentitySeed.make` (`IdentitySeed.swift:13-31`) tạo identity item từ tên+email user **tự nhập** (không có Sign in with Apple → không có Apple relay-email concern).
- Encryption: toàn bộ value (name/email/phone/...) sealed; chỉ `isDefaultIdentity` plaintext.

### 3. Vault Item ↔ Space relation

- 1 item ↔ tối đa 1 folder (`folderId` optional, **nằm TRONG sealed blob** → move = re-seal).
- Không share cross-folder; sharing là per-item, độc lập folder.
- Tags là cơ chế multi-group duy nhất.

### 4. AutoFill suggestion engine hiện tại

Hai tầng:

- **QuickType index** (`CredentialIdentityService.swift:69-93`): 1 `ASPasswordCredentialIdentity` per host per login (+ shared, + passkey/OTP). iOS tự rank.
- **In-extension** (`AutoFillView.swift:174-177`): binary match/no-match qua `VaultItem.matchesAutoFill` (`VaultReader.swift:103-113`, heuristic subdomain/substring 2 chiều), sort alphabet. **Không có scoring engine** — không recency/useCount weighting dù data có sẵn.
- **Email suggestion khi create-login**: đúng 1 nguồn — `VaultReader.defaultIdentityUsername` (`VaultReader.swift:41-51`) đọc **email của default Identity item**, prefill vào `CreateLoginView` (`:26`). Không ranking, không recents, không lấy từ login usernames. In-app editor: không suggest email (chỉ autocomplete URL website).
- Identity item KHÔNG được dùng cho address autofill — chỉ làm nguồn prefill username.

→ Ranking engine trong proposal là **greenfield**, không phải sửa engine cũ.

### 5. User account/auth model

- **KHÔNG có account system.** Không Sign in with Apple, không Supabase, không server login. Local vault + CloudKit **private database** (Apple ID ngầm định).
- Vault Key = random 256-bit, chỉ tồn tại dạng wrapped (Argon2id KEK / recovery KEK / biometric keychain). Plaintext key **không bao giờ** sync; escrow lên CloudKit chỉ dạng wrapped (`VaultKeyEscrowService.swift:5-18`).

### 6. Encryption model cho metadata (server thấy gì)

CloudKit CKRecord (`CloudSyncService.swift:159-177`): chỉ thấy `sealed` (ciphertext), timestamps, `favorite/pinned/archived`, `isDefaultIdentity`, `avatarSealed` (ciphertext), tombstones. **Title, type, domain, email đều nằm trong sealed blob — server không thấy.** `useCount/lastUsedAt` cố ý không upload. Folder: tên sealed, icon/color plaintext. Stance: "secrets sealed, not zero cleartext".

→ Trust boundary hiện tại cực hẹp. Relay backend (phải biết alias→destination lúc forward) là **bước nhảy trust model lớn nhất trong lịch sử app** — proposal có thừa nhận, nhưng chưa đối chiếu với positioning "zero-backend" của Vaultify.

### 7. Cloudflare stack hiện tại

- Worker code ở **sibling repo** `~/Developer/Projects/frontend/looxpassword/workers/loox-link/` (không trong repo này).
- Domains: `api.looxpassword.com` / `api-staging.` (Worker), `s.looxpassword.com` / `s-staging.` (viewer), `invite.looxpassword.com` (Cloudflare **Pages**, rendezvous chạy trên CloudKit public DB).
- Storage: **D1** (migrations, `DELETE…RETURNING`). Không thấy KV/R2/DO/Queues. **Free vs Paid: chưa xác nhận** (mọi thứ đang dùng đều Free-tier compatible).
- API auth: interim `X-Loox-App-Token` + **App Attest** (`LooxLinkAttestation.swift`) đang shadow mode (`attestationEnabled=true, attestationRequired=false`, `LooxLinkConfig.swift:23,31`), canonical transcript + fail-closed khi required. **Không có email infra** (không SMTP/SendGrid). Push = APNs qua CloudKit subscription, không phải Worker.
- ⚠️ Discrepancy: `plan.md:89-91` (loox-link) nói `attestationEnabled` phải giữ `false` tới C7, nhưng source hiện là `true` (comment 260706). Cần đối chiếu build đang ship.

### 8. Sync conflict model

- `CloudSyncService`: private DB, 1 zone `Vault`, record types `VaultItem` + `VaultFolder`, delta fetch bằng change token.
- **Whole-record LWW theo `updatedAt`** (`VaultStore.upsertFromRemote`, `VaultStore.swift:72-135`) + meta gate riêng theo `metaUpdatedAt` (pinned/archived). Soft tombstone, không CK delete.
- **Trap đã biết**: cột synced mới phải bump `updatedAt` nếu không sẽ bị drop khi pull. Sync OFF by default (`iCloudSyncEnabled`), compile-gated `VAULTIFY_ICLOUD`.
- Persona sync: nếu là record type CK mới trong cùng zone → tránh được whole-record LWW của item; nếu nhét vào ItemRecord → dính trap trên.

## Phần B — Đánh giá proposal theo kiến trúc thật

### Đồng ý (giữ nguyên)

1. **Tách Persona ≠ Profile item** — đúng, và codebase đã chứng minh: `isDefaultIdentity` là "system role bolted onto an item record", chính là tension proposal mô tả. Persona first-class + `primaryProfileItemId` là hướng đúng. Migration path có sẵn: default identity hiện tại → seed thành Persona `.personal` đầu tiên.
2. **Không dùng chữ "Identity" user-facing** — đúng, `ItemCategory.identity` đã chiếm tên. Rename UI item type thành "Personal Profile / Hồ sơ cá nhân" hợp lý.
3. **relay. subdomain thay vì apex** — đúng, đặc biệt vì `looxpassword.com` đã chạy api/s/invite subdomains thật.
4. **Catch-all → Email Worker, không per-alias rule** — đúng về limit 200 rules.
5. **Receive-only V1, không promise two-way anonymous mailbox** — đúng (reply leak từ địa chỉ thật).
6. **Two-tier alias (persona alias + per-site alias)** — đúng về chống correlation.
7. **anonymousStrict isolation** — khả thi đẹp vì toàn bộ matching/suggestion chạy client-side trong extension, không server nào thấy.
8. **Không marketing "fake identity" / anonymous social** — đúng ranh giới Apple 1.2.

### Phản biện / phải sửa theo thực tế Vaultify

1. **Proposal giả định có "Account" — Vaultify KHÔNG có account.** `ownerAccountId`, `SpaceMembership(participantId)`, account-deletion flow (mục 17) đều vô nghĩa với kiến trúc hiện tại. Thay thế: relay backend key theo **App Attest keyId** (hạ tầng đã có sẵn từ Loox Link!) → "account" pseudonymous device-bound, không cần email/Apple ID. Alias records sync giữa devices qua CloudKit như vault record bình thường (sealed); server chỉ giữ `alias_hash → encrypted destination`. Guideline 5.1.1(v) account-deletion hiện **chưa áp dụng** (không có account creation) — nhưng relay tạo server state per-user ⇒ vẫn cần "Delete relay data" in-app từ V1.
2. **"Spaces" chưa tồn tại — Phase 1 của proposal thiếu 1 phase trước nó.** Hiện chỉ có Folder (1-per-item, tên sealed) + virtual Shared-with-Me. Phải quyết trước: promote Folder → Space, hay thêm persona-scoping lên Folder? Đề xuất: **Phase 0 = Folder→Space promotion** (thêm `personaId?` sealed vào FolderSecret), vì `folderId` nằm trong sealed blob nên đổi model = re-seal + bump updatedAt (trap LWW).
3. **Company/shared-space use case xa hơn proposal nghĩ nhiều.** Sharing hiện tại là per-item CKShare delegation (đang hardening V2 dở), không có space-membership record. `SpaceMembership(representedPersonaId)` = feature mới hoàn toàn trên control plane, đừng đưa vào Phase 1-2. Ý "xuất hiện dưới persona khác trong shared space" hay nhưng là Phase cuối.
4. **Cloudflare Email Routing: proposal ĐÁNH GIÁ THIẾU 1 điểm chết.** Catch-all → Email Worker giải quyết limit 200 rules, nhưng `message.forward()` từ Worker **vẫn chỉ forward tới verified destination addresses** — limit 200 verified destinations/account vẫn nguyên. Tức là kể cả kiến trúc Worker đề xuất, quá ~200 user thật là nghẽn. Production scale bắt buộc outbound sending thật (Email Sending / SES / Postmark...) tới arbitrary recipients ⇒ gánh deliverability: SPF/DKIM/DMARC trên relay domain, SRS/ARC cho forwarded mail, IP reputation, bounce handling. Đây là lý do mạnh hơn nữa để Phase 3 chỉ là prototype-scale và ngân sách hạ tầng phải tính từ đầu. (Verify lại CF docs hiện hành trước khi chốt — limits có thể đã đổi.)
5. **Ranking engine = greenfield, và điểm cắm là extension.** Hiện suggestion chỉ có 1 nguồn (default identity email). Scoring của proposal build mới trong `VaultReader`/extension được; lưu ý extension memory limit và QuickType index chứa username+host plaintext trong system store — per-site alias sẽ xuất hiện ở đó (chấp nhận được, ghi vào threat model).
6. **Sync trap**: Persona nên là **CK record type mới** (như VaultFolder) trong zone `Vault`, không nhét cột vào ItemRecord — tránh whole-record LWW conflict với item content, và tránh trap "quên bump updatedAt". Persona phải hoạt động **full offline/local** vì iCloud sync OFF by default.
7. **Onboarding auto-create**: lo ngại "Apple auth email → Real Identity" của proposal không áp dụng — Vaultify không có Sign in with Apple; seed hiện tại từ tên/email user tự nhập, đã đúng tinh thần "Personal, không phải Real Identity". Chỉ cần nâng seed hiện tại → Persona `.personal`.
8. **Zero-backend positioning**: relay biến Vaultify từ "zero-backend" thành "backend-lite". Cần quyết định product-level (marketing, privacy policy, App Privacy label sẽ đổi: Contact Info — Email — linked? Cần chốt trước khi build Phase 3). Loox Link đã mở tiền lệ (D1 giữ share metadata) nhưng relay giữ **destination email dài hạn** — khác về chất.

### Roadmap điều chỉnh (thay cho mục 20 của proposal)

- **Phase 0 — Space promotion**: Folder→Space (personaId sealed trong FolderSecret), UI space switcher. Không đụng backend.
- **Phase 1 — Persona Core**: `PersonaRecord` (@Model + CK record type mới, sealed payload: displayName/kind/privacyMode/primaryProfileItemId/defaultSpaceId), seed từ default identity hiện tại, migration `isDefaultIdentity` → persona link. Invariant mới: ≥1 persona, đúng 1 default.
- **Phase 2 — Persona-scoped AutoFill**: ranking engine trong VaultReader/extension, anonymousStrict, persona context truyền vào CreateLoginView. Không backend.
- **Phase 3 — Local EmailAlias model**: entity + UI, chưa mail thật (như proposal).
- **Phase 4 — Relay MVP**: worker mới trong `looxpassword/workers/` (tách khỏi loox-link), auth = App Attest (tái dùng `LooxLinkAttestation` pattern + canonical transcript), D1 `alias_hash(HMAC) → AEAD(destination)`, catch-all ingress, receive-only, **prototype scale** (chấp nhận verified-destination limit hoặc đi thẳng outbound provider). Privacy policy + App Privacy + delete-relay-data bắt buộc trước ship.
- **Phase 5 — Shared-space persona representation**: sau khi shared-vault hardening V2 xong và space-membership model tồn tại.

### Phối hợp với công việc đang chạy

Branch hiện tại đang giữa shared-vault hardening V2 (grant v2 canonical bump). Persona đụng grant model nếu làm Phase 5 sớm — giữ Phase 5 sau V2 merge. Phase 0-2 không conflict.

## Phần C — Xác minh trực tiếp repo BE/FE (`~/Developer/Projects/frontend/looxpassword`)

Bổ sung sau khi đọc source backend thật (thay cho suy đoán ở câu 7 Phần A):

### C1. Stack đã xác nhận

- 3 deployable units: marketing site (Next.js 16 + next-intl EN/VI, OpenNext→Workers, apex+www), `workers/loox-link` (plain TS Worker, **zero runtime deps**, không Hono), `invite/` (static assets + AASA, SPA fallback).
- `loox-link` bindings: **D1 ONLY** (staging + production DB riêng, custom domains `api./api-staging.`, `s./s-staging.`). Không KV/R2/DO/Queues/Email/AE. `observability: true`. Vars: 64KB payload cap, 30d max expiry, `EXPECTED_APP_ID=WDNL2F75V7.com.bervion.vaultify`.
- Viewer `s.looxpassword.com` do chính Worker render (self-contained HTML, `viewer.ts`), decrypt 100% client-side Web Crypto, key trong URL fragment không bao giờ gửi server.
- **Không có CI** — deploy manual qua wrangler + `scripts/deploy-marketing.sh` (kèm `claims-gate.sh` chặn marketing claims cấm). Secrets qua `wrangler secret put`.

### C2. App Attest server-side: ĐÃ IMPLEMENT ĐẦY ĐỦ (không phải stub)

- Cert chain verify tới Apple App Attest Root (`@peculiar/x509` + `cbor-x`), nonce/appId/keyId structural verify, `attest_keys` lưu public key + `sign_count` CAS chống replay, challenge single-use TTL 180s.
- `ASSERTION_MODE=off` hiện tại ở **mọi env** (wrangler vars) — tức server chưa vào shadow; client iOS đã shadow-ready. Đính chính Phần A câu 7: "đang shadow mode" là phía client.
- ⚠️ Gap đã được chính repo flag: transcript V1 **không cover `one_time`** — phải fix trước khi bật `required` (`create-assertion.ts:9-11`).
- Auth interim: `APP_CREATE_TOKEN` constant-time compare, indistinguishable 401/404. ADR khẳng định token không phải durable auth.

### C3. Hạ tầng cho relay: HOÀN TOÀN CHƯA CÓ

- **Zero email infrastructure**: không MX/SPF/DKIM/DMARC, không Email Routing, không `email()` handler, không send binding. Contact form marketing chỉ là `mailto:`.
- Cron `scheduled()` có trong code nhưng **chưa đăng ký trigger** (deploy guide ghi "enable once Cron Triggers are available on the account").
- Rate limiting: **không có trong code** — chỉ là target ghi trong ADR (~10 creates/hr/IP), cấu hình dashboard-manual, chưa verify đã bật.
- Không có user-account/session/cookie auth, không CORS (API same-origin) — web surface quản lý alias/persona sẽ là greenfield hoàn toàn.
- Paid features: không dùng gì bắt buộc Paid; plan tier vẫn chưa xác định từ repo.

### C4. Điều chỉnh feasibility Phase 4 (Relay MVP)

Tin tốt: nền tảng loox-link sạch (D1-only, abuse posture tốt: FORBIDDEN_KEYS chống pastebin, payload caps, indistinguishable 404) — thêm worker `email()` handler + bảng D1 `aliases` không conflict gì. App Attest tái dùng được làm auth provisioning alias.

Việc net-new bắt buộc (không có sẵn cái nào):
1. Bật Email Routing trên zone + subdomain relay, MX/SPF/DKIM/DMARC DNS (hiện DNS không được quản lý as-code — routes chỉ là `custom_domain: true`).
2. Worker mới với `email()` handler + catch-all binding.
3. Destination verification flow (limit 200 verified destinations vẫn áp dụng cho `message.forward()` — điểm chết đã nêu ở B4 giữ nguyên).
4. Cron cleanup (phải bật trigger), rate limiting phải code-level thay vì dashboard-manual (email abuse nghiêm trọng hơn share links).
5. Transcript canonical mới `LOOX-APP-ATTEST-ALIAS-V1` (học pattern loox-link, nhớ cover đủ fields — tránh lặp gap `one_time`).

## Unresolved questions

1. Workers plan Free/Paid + Cron Triggers có sẵn trên account chưa — repo không nói; cần check dashboard (account `f318e1b1b12cfff2570858cd0ba3f8e5`).
2. Email Routing đã enable trên zone `looxpassword.com` chưa (dashboard-only, không thấy từ repo)?
3. Rate Limiting Rules trong ADR đã thực sự cấu hình trên dashboard chưa?
4. `ASSERTION_MODE=off` server-side vs client `attestationEnabled=true` — thứ tự bật shadow→required cần chốt (và fix transcript `one_time` gap trước `required`).
5. Cloudflare Email Routing limits (200 rules / 200 verified destinations / Email Sending pricing) cần verify docs hiện hành trước khi chốt Phase 4.
6. Product decision: Vaultify có chấp nhận rời positioning "zero-backend" cho relay không, hay relay là opt-in add-on tách biệt (thậm chí paid tier)?
7. Space = Folder promotion hay entity mới song song Folder? (khuyến nghị promotion, nhưng ảnh hưởng UX hiện tại cần user quyết.)
8. `docs/deployment-guide.md:10` (repo BE) ghi account owner `chinhphamnhu@gmail.com` — confirm account nào own zone để bật Email Routing.
