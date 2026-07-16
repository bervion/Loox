---
title: "Loox Entitlement Service - Proposal BE trên Cloudflare (không VPS)"
status: proposal-v4
updated: 2026-07-16
review: "v2 tích hợp phản biện vòng 1. v3 tích hợp vòng 2 (env namespace, transaction ledger, quota outbox, statuses-before-grant, named RPC, atomic alias quota, rollout đảo thứ tự). v4 đóng review vòng 3: Sandbox authorization bắt buộc entitlement lease bound vào authenticated principal; prod không global-poll Sandbox; quota commit kiểm TTL độc lập cron; bind insertion-first không burn grant khi conditional no-op; Quick View outbox nằm cùng SessionDO transaction; reducer lưu isUpgraded/webOrderLineItemId + renewal ledger riêng; rollout tách client-capable coverage, paid-binding coverage và legacy cohort."
scope: [backend-entitlements, cloudflare-workers, apple-server-notifications, quota-enforcement]
source_of_truth: "Thực thi phần backend của proposal-260714-2231-loox-subscription-strategy.md (§7, §8, §10, §12). Bảng tier/quota và bảng trạng thái §8.1 đã đóng băng ở client (VaultifyCore/Subscription/LooxTier.swift, LooxSubscriptionState.swift) — BE phải khớp từng dòng."
repo: "~/Developer/Projects/frontend/looxpassword (workers/loox-relay, loox-link, loox-quick-view, loox-config)"
---

# Loox Entitlement Service - Proposal BE trên Cloudflare (v4)

## 0. Quyết định chốt

Toàn bộ trên hạ tầng Cloudflare hiện có (account `f318e1b1…`), không VPS:

- **Một worker mới `loox-entitlement`** (TypeScript, `nodejs_compat`, pattern
  `env.staging`/prod) + **D1 `loox-entitlement`** là nguồn quyết định DUY NHẤT
  cho mọi mutation. V1 không có cache nào trong authorization path; chỉ xem xét
  cache khi có số liệu latency, không bao giờ cho quota.
- **Internal API là các named `WorkerEntrypoint` RIÊNG THEO DỊCH VỤ**
  (`RelayEntitlement`, `LinkEntitlement`, `QuickViewEntitlement`) — caller
  không bao giờ tự khai `service`; quyền đến từ binding, không từ tham số.
- **`environment` là namespace xuyên suốt**: account, chain, transaction,
  binding, grant, lease, quota đều mang env. Namespace DB là điều kiện cần;
  authorization còn bắt buộc **`entitlement_lease` bound vào principal đã xác
  thực** để request không thể tự chọn env (mục 1). Sandbox binding không bao giờ
  được resolve chỉ từ `binding_value`.
- **Binding qua `binding_grant` một lần, TTL 10 phút**, lưu HASH của grant;
  cap-check + ghi binding + consume trong MỘT transaction D1 theo thứ tự
  insertion-first, mọi câu sau conditional theo binding vừa tạo — cap/no-op
  không burn grant.
  `subscription_account_id` không bao giờ là proof of ownership.
- **Sổ cái versioned `subscription_transactions` + `subscription_renewals`** là
  nền reducer; chain/account chỉ là projection tính lại. Mỗi JWS mới INSERT một
  version, không sửa lịch sử; refund kỳ cũ và `isUpgraded` không thể quyết định
  sai kỳ hiện hành.
- **Quota là saga `reserve → commit/release`** với `operation_id` +
  `request_fingerprint`; `released` là TRẠNG THÁI CUỐI (commit muộn bị từ chối
  và commit luôn kiểm `ttl_expires_at_ms > now`, không phụ thuộc cron). Link có
  transactional outbox trong D1; Quick View lưu outbox trong CHÍNH SessionDO
  transaction với payload/state rồi drain bằng alarm.
- **`/attach` không tin JWS một mình**: sau verify chữ ký phải gọi
  `Get All Subscription Statuses` (đúng host theo env) rồi mới cấp paid
  grant/lease — chặn replay JWS đã refund/revoke.
- **ASSN v2 chỉ là trigger.** Staging poll Sandbox history; prod chỉ poll
  Production history. Dòng Sandbox trên prod (TestFlight/App Review) hội tụ
  bằng statuses poll cho chain đã đăng ký qua prod `/attach` — prod không nhập
  global Sandbox history của dev/staging.
- **Fail posture:** entitlement/quota không trả lời được → create mutation trả
  **`503 service_unavailable`** (outage §2.7) — không silent-Free, không
  paywall; đọc và tài nguyên hiện hữu không đụng.
- **Quota alias do relay enforce bằng conditional-INSERT nguyên tử** (thay
  COUNT-rồi-INSERT hiện tại, `aliases.ts:126-141`) và **relay_principal cap =
  1 active/subscription** — principal vốn đã escrow cross-device
  (`RelayPrincipalEscrowService` phía iOS), nên 1 là đúng bản chất, đồng thời
  chặn nhân quota theo principal. Link + Quick View quota do entitlement giữ.
- **Recipient seat của Approval Mode KHÔNG enforce ở BE** (CloudKit-only).
- **Enforcement bật SAU CÙNG**: client integration dormant + purchases live
  trước. B5 cần 100% paid-binding coverage và rollout cohort per-service; định
  danh live có trước cutover được grandfather cho tới legacy sunset — không dựa
  vào một ngưỡng `85% sessions` mơ hồ.
- Ba cổng độc lập (§10.2): App Attest · entitlement · abuse hiện hữu. Kill
  switch per-service `ENTITLEMENT_MODE: off`.

## 1. Environment isolation (P0 — đọc trước khi code)

| Client | StoreKit transaction | App Attest | Worker mà app gọi |
|---|---|---|---|
| Dev build (Xcode) | Sandbox / StoreKit-config | Development | staging |
| TestFlight | **Sandbox** | Production | **prod** (Release config) |
| App Store | Production | Production | prod |
| App Review | **Sandbox** | Production | **prod** |

Ràng buộc thực tế:

1. **Không lấy routing làm security boundary.** TestFlight thường dùng cùng
   Release candidate/endpoint với App Store; runtime-detect bằng receipt
   heuristic là fragile. Quan trọng hơn, **App Review kiểm IAP trong Sandbox
   trên bản gọi prod** — §12 yêu cầu reviewer chạm được paid feature. Vì vậy
   prod phải hỗ trợ Sandbox có kiểm soát, dù QA dev chủ lực vẫn đi staging.
2. **Namespace DB chưa đủ — request phải mang authorization context:**
   - Mọi bảng mang `environment`; không query nào join khác env.
   - `/attach` sau statuses check phát một `entitlement_lease` opaque per
     `(environment, service, binding_value_hash, account_version)`. DB chỉ lưu
     hash; lease biết env từ server, client không tự khai env/account/service.
   - Mỗi paid mutation gửi lease NGOÀI business transcript. Service chỉ chuyển
     lease + identity lấy từ verifier result (relay principal/App Attest key)
     vào named RPC; entitlement verify lease, active binding và account version
     cùng env. Biết lease mà không có private key của principal vẫn vô dụng.
   - TTL ceiling: Sandbox **15 phút**, Production **24 giờ**. `lease_expires_at`
     luôn là `min(now + ceiling, authorization_not_after)`; active dùng kỳ hết
     hạn hiện tại, grace dùng grace-period deadline. Vì vậy ASSN/cron đến trễ
     cũng không kéo quyền qua hạn. Client giữ Sandbox lease trong memory, chỉ
     refresh lazy/single-flight khi gần hết hạn hoặc nhận
     `entitlement_refresh_required`; `/attach` luôn statuses-check. Account
     projection đổi version làm mọi lease cũ mất hiệu lực ngay.
   - Không lease: chỉ xét binding ở env mặc định của deployment (prod =
     Production, staging = Sandbox). Binding paid ở env mặc định →
     `entitlement_refresh_required` (client attach rồi retry), không
     silent-Free/paywall; binding khác env bị bỏ qua và request vào Free bucket.
     Nhờ vậy App Store sau TestFlight không bị Sandbox binding cũ giữ ở refresh
     loop.
3. **Residual cần owner ký đúng phạm vi:** tester/TestFlight/App Review được
   paid tier trên dịch vụ prod khi còn trình được Sandbox lease hợp lệ. TestFlight
   renew theo nhịp riêng của Apple (có thể kéo dài tới một tuần), nên không dựa
   vào giả định "tự hết trong khoảng một giờ". Backend không thể phân biệt bằng
   mật mã một TestFlight client với App Store client đang replay cùng Sandbox JWS
   hợp lệ + principal; lease 15 phút chỉ buộc re-check trạng thái, không biến nó
   thành Production. Rủi ro được giới hạn vào người có Sandbox transaction hợp
   lệ của app, namespace quota riêng và không cấp Production entitlement. Dữ
   liệu họ đã tạo vẫn đọc được sau khi lease hết theo nguyên tắc không xóa dữ
   liệu; mutation mới chỉ nhận paid Sandbox quota khi còn lease hợp lệ.
4. QA paid-flow E2E chủ lực chạy staging/dev build (Sandbox → staging worker).
   ASSN Sandbox URL của ASC trỏ **staging**. Prod **không global-poll Sandbox
   history**; chỉ statuses-reconcile các `(Sandbox, original_transaction_id)`
   đã được prod `/attach` đăng ký (TestFlight/App Review), xem mục 5.
5. App Attest: verifier hiện tại trả `environment: 'unknown'`, chain-verify
   còn `REAL_APPLE_FIXTURE_PENDING`, chưa wire vào create path
   (`loox-link/src/app-attest/attestation.ts:118-135`, epic C7). An ninh lõi
   của `/attach` đứng trên chữ ký Apple của transaction JWS + statuses check;
   App Attest là lớp abuse theo ladder `off → shadow → active`. C7 không giải
   quyết TestFlight-vs-App-Store (cả hai đều Production attest) — cái đó do
   env-scoped lease ở trên lo. C7 chặn ladder `active`, không chặn B1-B2.

## 2. Nguyên tắc không thương lượng (kế thừa §2, §7, §10 + v4)

1. Lỗi entitlement không bao giờ xóa/sửa dữ liệu — chỉ được chặn mutation TẠO
   MỚI; không chặn đọc, không xóa alias/share/session đang sống vì billing.
2. `subscription_account_id` lấy từ `appAccountToken` BÊN TRONG JWS đã verify;
   client claim chỉ để đối chiếu. Không định danh nào là bearer credential.
3. Grant/lease chỉ được cấp từ TRẠNG THÁI HIỆN TẠI đã xác nhận với Apple
   (statuses), không từ một chữ ký từng-hợp-lệ; paid mutation luôn cần lease
   bound vào authenticated identity.
4. Trạng thái mơ hồ = giữ quyền đã verify gần nhất và reconcile; không "xóa
   cho chắc" (§8.1). Quota sai số luôn nghiêng VỀ PHÍA user (mục 4.4), không
   bao giờ deny sau khi đã giao hàng.
5. Không lưu/log nội dung vault, alias address, persona, email thật. Billing
   projection tối thiểu, giả danh (§7.3-7.4).
6. Không hạ quota đã công bố mà không grandfather (§3.2); enforcement là
   create-only nên tài nguyên vượt cap có sẵn không bị đụng.
7. `verifyReceipt` deprecated — không dùng. Verify outer JWS VÀ nested
   `signedTransactionInfo`/`signedRenewalInfo` riêng từng cái.

## 3. Kiến trúc

~~~mermaid
flowchart LR
    subgraph Apple
      AS["App Store"] --> SK["StoreKit 2 trong app"]
      AS -->|"ASSN v2 (prod URL -> prod, sandbox URL -> staging)"| WH["POST /v1/apple/notifications"]
      API["App Store Server API<br/>(host theo env từng dòng)"]
    end
    SK -->|"transaction JWS (+App Attest ladder)"| AT["POST /v1/entitlement/attach"]
    AT -->|"statuses check TRƯỚC khi cấp grant/lease"| API
    subgraph loox-entitlement worker
      WH --> RED["Verify outer+nested JWS -> Ledger -> Reducer"]
      AT --> RED
      RED --> D1[("D1: transaction+renewal ledgers / projections /<br/>notifications / bindings / grants / leases /<br/>quota_operations / reconcile_state")]
      CRON["Cron: scoped history/statuses,<br/>quota expiry, wind-down, prune"] --> API
      CRON --> RED
    end
    subgraph Dịch vụ hiện hữu
      RELAY["loox-relay"] -->|"RelayEntitlement RPC"| D1
      LINK["loox-link + outbox"] -->|"LinkEntitlement RPC"| D1
      QV["loox-quick-view + outbox"] -->|"QuickViewEntitlement RPC"| D1
    end
~~~

### 3.1 Worker `loox-entitlement`

- `workers/loox-entitlement/` theo khuôn `loox-link`. Domain: prod
  `entitlement.looxpassword.com`, staging
  `entitlement-staging.looxpassword.com` — chốt trước khi điền URL ASSN vào ASC.
- Secrets (cả hai env): `IAP_KEY_P8`, `IAP_KEY_ID`, `IAP_ISSUER_ID`,
  `APP_APPLE_ID` (bắt buộc cho verifier production). Apple root CA bundle
  trong source.
- Export: `default fetch` (attach + webhook) và BA named entrypoint RPC
  (`RelayEntitlement`, `LinkEntitlement`, `QuickViewEntitlement` — mỗi worker
  chỉ được bind đúng entrypoint của nó trong `wrangler.jsonc`).

### 3.2 Verify chữ ký Apple — HARD GATE

- **B1-0 (gate):** `@apple/app-store-server-library` (Node chính thức) phải
  chạy dưới `nodejs_compat`: outer notification JWS, nested transaction/renewal
  JWS, App Store Server API client, online-check/OCSP behavior dưới workerd
  test tường minh. Pin major version.
- Không tương thích → **DỪNG, quyết định lại** (runtime/thư viện chính thức
  tương thích khác). Tự viết crypto là phương án cuối cùng, có security review
  riêng — không phải mặc định.
- Claims sau verify: `bundleId == "com.bervion.vaultify"`, `environment` hợp lệ
  theo ma trận mục 1, `productId` thuộc allowlist 4 ID (§4.2 proposal thương mại).

### 3.3 Data model (D1, migration 0001 — CHƯA freeze tới khi v4 sign-off + B1-0 xanh)

~~~sql
-- SỔ CÁI VERSIONED, append-only: refund/reversal INSERT version mới của chính
-- transaction; không UPDATE/xóa version cũ.
CREATE TABLE subscription_transactions (
  environment TEXT NOT NULL,                  -- 'Production' | 'Sandbox'
  transaction_id TEXT NOT NULL,
  signed_date_ms INTEGER NOT NULL,
  original_transaction_id TEXT NOT NULL,
  subscription_account_id TEXT,               -- appAccountToken trong JWS (nullable: purchase cũ)
  product_id TEXT NOT NULL,
  web_order_line_item_id TEXT,
  subscription_group_identifier TEXT,
  purchase_date_ms INTEGER,
  expires_date_ms INTEGER,
  revocation_date_ms INTEGER,
  revocation_reason TEXT,
  is_upgraded INTEGER NOT NULL DEFAULT 0,
  payload_hash TEXT NOT NULL,                 -- audit/dedupe, không lưu plaintext JWS ở ledger
  inserted_at_ms INTEGER NOT NULL,
  PRIMARY KEY (environment, transaction_id, signed_date_ms)
);
CREATE INDEX idx_txn_chain_latest
  ON subscription_transactions(environment, original_transaction_id,
                               transaction_id, signed_date_ms DESC);

-- RenewalInfo là trạng thái theo CHAIN, không có transaction_id ổn định để
-- nhét chung transaction ledger. Mỗi JWS mới cũng append một version.
CREATE TABLE subscription_renewals (
  environment TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  signed_date_ms INTEGER NOT NULL,
  auto_renew_product_id TEXT,
  auto_renew_status INTEGER,
  grace_period_expires_date_ms INTEGER,
  expiration_intent INTEGER,
  payload_hash TEXT NOT NULL,
  inserted_at_ms INTEGER NOT NULL,
  PRIMARY KEY (environment, original_transaction_id, signed_date_ms)
);

-- PROJECTION theo chuỗi (tính lại từ sổ cái, không ghi tay).
CREATE TABLE subscription_chains (
  environment TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  subscription_account_id TEXT,
  current_transaction_id TEXT,
  product_id TEXT NOT NULL,
  status TEXT NOT NULL,                       -- mục 4.3
  expires_at_ms INTEGER,
  grace_until_ms INTEGER,
  auto_renew_status INTEGER,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (environment, original_transaction_id)
);
CREATE INDEX idx_chain_account ON subscription_chains(environment, subscription_account_id);

-- PROJECTION hiệu lực theo định danh billing giả danh.
CREATE TABLE subscription_accounts (
  environment TEXT NOT NULL,
  subscription_account_id TEXT NOT NULL,
  effective_tier TEXT NOT NULL,
  effective_status TEXT NOT NULL,
  expires_at_ms INTEGER,
  grace_until_ms INTEGER,
  version INTEGER NOT NULL DEFAULT 0,         -- CAS khi reducer ghi
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (environment, subscription_account_id)
);

-- Inbox: idempotency + audit + reprocess. raw nullable để prune giữ dòng tối thiểu.
CREATE TABLE apple_notifications (
  environment TEXT NOT NULL,
  notification_uuid TEXT NOT NULL,
  notification_type TEXT NOT NULL,
  subtype TEXT,
  original_transaction_id TEXT,
  signed_date_ms INTEGER NOT NULL,
  raw_payload TEXT,                           -- NULL sau prune (dòng tối thiểu giữ lại)
  received_at_ms INTEGER NOT NULL,
  source TEXT NOT NULL,                       -- 'webhook' | 'history_poll' | 'test'
  processed_at_ms INTEGER,
  PRIMARY KEY (environment, notification_uuid)
);

-- Grant một lần: LƯU HASH, không lưu plaintext. replace_binding_id chỉ dùng
-- cho Link/QV key rotation; Relay principal khác giá trị không auto-replace.
CREATE TABLE binding_grants (
  grant_hash TEXT PRIMARY KEY,                -- SHA256(grant secret gửi cho client)
  environment TEXT NOT NULL,
  subscription_account_id TEXT NOT NULL,
  service TEXT NOT NULL,                      -- 'relay' | 'link' | 'quickview'
  binding_type TEXT NOT NULL,
  binding_value_hash TEXT NOT NULL,
  replace_binding_id INTEGER,
  created_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,             -- now + 10 phút
  consumed_at_ms INTEGER
);

-- Authorization context dùng lại cho paid mutation; request không tự chọn env.
CREATE TABLE entitlement_leases (
  lease_hash TEXT PRIMARY KEY,                -- SHA256(opaque secret trả một lần)
  environment TEXT NOT NULL,
  subscription_account_id TEXT NOT NULL,
  account_version INTEGER NOT NULL,
  service TEXT NOT NULL,
  binding_type TEXT NOT NULL,
  binding_value_hash TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER NOT NULL,             -- Sandbox 15m; Production 24h
  revoked_at_ms INTEGER
);
CREATE INDEX idx_lease_subject ON entitlement_leases(
  environment, subscription_account_id, service, binding_value_hash
);

-- Binding có lịch sử: chỉ lưu hash identity kỹ thuật. source_grant_hash làm
-- bind retry idempotent và buộc mọi side effect theo đúng grant đã thắng.
CREATE TABLE principal_bindings (
  binding_id INTEGER PRIMARY KEY AUTOINCREMENT,
  environment TEXT NOT NULL,
  binding_type TEXT NOT NULL,
  binding_value_hash TEXT NOT NULL,
  subscription_account_id TEXT NOT NULL,
  source_grant_hash TEXT NOT NULL,
  replaced_binding_id INTEGER,
  status TEXT NOT NULL DEFAULT 'active',      -- 'active' | 'revoked'
  created_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER
);
CREATE UNIQUE INDEX uq_bind_active
  ON principal_bindings(environment, binding_type, binding_value_hash)
  WHERE status = 'active';
CREATE UNIQUE INDEX uq_bind_source_grant ON principal_bindings(source_grant_hash);
CREATE INDEX idx_bind_sub ON principal_bindings(environment, subscription_account_id, status);

-- Saga quota: reservation + ledger; released là TERMINAL.
CREATE TABLE quota_operations (
  environment TEXT NOT NULL,
  service TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,          -- SHA256(payload chuẩn hóa); khác -> 409
  event TEXT NOT NULL,
  subscription_account_id TEXT,               -- NULL = Free theo identity
  identity_key_hash TEXT NOT NULL,
  status TEXT NOT NULL,                       -- 'reserved' | 'committed' | 'released'
  reserved_at_ms INTEGER NOT NULL,
  ttl_expires_at_ms INTEGER NOT NULL,
  committed_at_ms INTEGER,
  PRIMARY KEY (environment, service, operation_id)
);
CREATE INDEX idx_quota_account_window ON quota_operations(
  environment, service, subscription_account_id, committed_at_ms, ttl_expires_at_ms
);
CREATE INDEX idx_quota_identity_window ON quota_operations(
  environment, service, identity_key_hash, committed_at_ms, ttl_expires_at_ms
);

-- Reconcile theo CỬA SỔ CỐ ĐỊNH (paginationToken không phải durable cursor).
CREATE TABLE reconcile_state (
  scope_key TEXT PRIMARY KEY,                 -- 'history:Production' | 'chain:<env>:<otid>'
  window_start_ms INTEGER,
  window_end_ms INTEGER,
  page_token TEXT,                            -- CHỈ hợp lệ trong cửa sổ hiện tại; clear khi hasMore=false
  high_watermark_ms INTEGER,                  -- mốc đã hội tụ chắc chắn
  last_ok_at_ms INTEGER,
  next_at_ms INTEGER NOT NULL,
  failure_count INTEGER NOT NULL DEFAULT 0,
  leased_until_ms INTEGER
);
~~~

Migration thật dùng `STRICT` + `CHECK` cho enum/status/environment. `payload_hash`
là SHA-256 compact JWS đã verify; raw JWS chỉ nằm trong inbox có retention. B6 có
migration riêng cho wind-down state/alias selection, không nhét trước vào 0001.

Tier/quota là hằng số code (`quotas.ts`) chép từ `LooxTier.swift`, unit test
pin: `retainedAliases 1/10/200`, `linkCreates30d 3/30/300`,
`quickViewApprovals30d 3/30/300`. Personas/Watchtower/themes: client-only.

### 3.4 Vì sao D1 (chưa Queue/DO) — và giới hạn đã tính

Tải trần ~vài nghìn write/ngày. Mọi thao tác điều-kiện-rồi-ghi là MỘT câu SQL
hoặc một `batch()` mà mọi câu sau phụ thuộc bằng SQL vào row thắng trước đó
(không kiểm `meta.changes` sau commit để giả lập rollback). Upgrade path:
`SubscriptionDO` per account nếu một ngày cần serialize chặt. Link outbox nằm
trong D1 của Link; Quick View outbox nằm trong `SessionDO` storage cùng payload
vì D1 không thể transaction với Durable Object.

## 4. Contract API

### 4.1 Public — `POST /v1/entitlement/attach`

Body: `{ transaction_jws, requested_bindings: [{service, binding_type,
binding_value_hash, replace_binding_id?}] }`

1. Verify JWS (3.2) → ghi sổ cái + reducer (dữ liệu lịch sử, chưa cấp gì).
   `subscription_account_id := payload.appAccountToken`; thiếu → `token_missing`
   (client PHẢI set token từ purchase đầu tiên — IAP chưa live nên đây là
   đường chính; `Set App Account Token` chỉ là defensive follow-up, xem Câu hỏi 4).
2. **Gọi `Get All Subscription Statuses`** (host theo env) cho
   `originalTransactionId` → reducer áp trạng thái HIỆN TẠI. Apple API không
   trả lời được → `503 retryable`, KHÔNG cấp grant từ JWS một mình (chặn
   replay JWS đã refund/revoke).
3. Trạng thái hiện tại là paid → với từng requested binding:
   - nếu active binding cùng `(env, service, hash, account)` đã tồn tại, chỉ
     refresh lease; không phát grant/rebind dư thừa;
   - nếu chưa binding, phát `binding_grant` một lần, TTL 10 phút, để dịch vụ
     bind identity đã auth; cùng hash đang thuộc account khác →
     `binding_conflict`, không tự chuyển ownership;
   - `entitlement_lease` dùng lại, bound vào cùng binding hash + service + env +
     `subscription_accounts.version`; expiry lấy min của TTL ceiling và
     entitlement/grace deadline (Sandbox 15 phút, Production 24 giờ).
   DB chỉ giữ hash của cả hai secret. Free/expired → không phát grant/lease.
4. Response: `{ tier, status, expires_at_ms, authorizations:
   [{grant?, lease, lease_expires_at_ms, service, binding_type,
   binding_required}] }`.

Auth: App Attest ladder riêng của worker (pattern `attest_challenges`/
`attest_keys`). Restore đa thiết bị nằm trong V1: máy B đọc `appAccountToken`
từ verified transaction của nó → attach → grants/leases mới. Link/QV key
rotation có thể chỉ rõ `replace_binding_id`; Relay phải khôi phục cùng escrowed
principal, không dùng billing ownership để âm thầm chiếm aliases của principal
khác.

### 4.2 Bind + authorize — named RPC theo từng service

Named entrypoint cố định `service` + `binding_type`; dịch vụ gọi SAU khi auth
định danh gốc (relay: verify chữ ký + `consumeNonce`; link/qv: lấy `keyId` từ
verifier result). Không API nào nhận identity/env/service do app tự khai.

`bind({grant, authenticated_binding_value})` chạy MỘT batch insertion-first:

1. Nếu `source_grant_hash` đã có binding → trả binding đó (retry sau response
   timeout), không chạy side effect mới.
2. `INSERT principal_bindings … SELECT FROM binding_grants` chỉ khi grant hash,
   TTL, service, binding type/hash hợp lệ, chưa consumed và cap còn chỗ. Nếu có
   `replace_binding_id`, cap query chỉ loại row đó khi nó thuộc đúng
   `(env, account, binding_type)`; chỉ áp dụng cho Link/QV.
3. UPDATE revoke replacement **chỉ WHERE EXISTS binding vừa INSERT với
   `source_grant_hash` đó**.
4. UPDATE consume grant **chỉ WHERE EXISTS cùng binding vừa INSERT**.

Conditional no-op không phải SQL error và D1 không rollback vì `changes==0`,
nên thứ tự/`EXISTS` trên là invariant bắt buộc: cap/grant fail → cả ba câu đều
no-op, grant còn dùng được và binding cũ còn active. Batch statement thật fail →
D1 rollback toàn bộ. Nếu hai request cùng grant chạy đồng thời và request thua
gặp unique conflict ở `source_grant_hash`, RPC bắt conflict, đọc binding đã thắng
và trả idempotent success; không phát lại grant. Test race + test no-op pin chính
xác hành vi này.

Cap theo loại (config): **relay_principal = 1 active** (principal đã escrow
cross-device — một principal per user là bản chất; đồng thời chặn nhân quota
alias theo principal), **attest_key_link = 5**, **attest_key_qv = 5**, kèm
self-service revoke/replace có `replace_binding_id` cho Link/QV. Relay principal
khác giá trị → `principal_recovery_required`; V1 chỉ support/old-principal signed
transfer mới được thay, không transfer alias ownership chỉ bằng Apple billing.

Paid authorization dùng các typed method như
`tierForRelayPrincipal({principal_id, lease})`,
`reserveLinkCreate({attest_key_id, lease, ...})` và
`reserveQuickViewUpload({attest_key_id, lease, ...})`. Identity luôn là output
của verifier. Lease hash phải match service/binding/env, chưa hết hạn, chưa
revoked, active binding tồn tại, account còn `active|grace` và
`account_version` bằng projection hiện tại. Authorization luôn so `now` trực
tiếp với `effective_expires_at_ms`/grace deadline; không chờ reducer đổi status
sau một mốc thời gian đã biết.

### 4.3 Reducer trạng thái (ledger-first)

Mọi trigger (webhook, history poll, attach, statuses) đi một đường:

1. Verify OUTER rồi NESTED JWS riêng từng cái. Trigger không có transaction
   data (`RENEWAL_EXTENSION` SUMMARY, loại lạ…) → KHÔNG đổi state, đánh dấu
   `reconcile_state['chain:…']` để poll statuses.
2. INSERT version mới vào transaction/renewal ledger theo `signedDate`; cùng
   `(env, id, signedDate)` + cùng hash là idempotent, hash khác là security
   anomaly. Refund transaction cũ chỉ thêm version của đúng transaction đó.
3. **Recompute chain từ latest version per row + verified statuses:**
   - `Get All Subscription Statuses.lastTransactions` là pointer authoritative
     tới kỳ hiện hành; persist `transactionId`, `status`, renewal info đã verify.
   - Loại `is_upgraded=1`; upgrade-away transaction còn future expiry không
     quyết định tier. Dùng `web_order_line_item_id` + subscription group để
     kiểm chuỗi/upgrade nhất quán.
   - Nếu current transaction bị revoke → chain `revoked`, không fallback về kỳ
     cũ non-revoked rồi gọi `expired`. Refund kỳ cũ không ảnh hưởng khi current
     transaction khác.
   - Webhook/history chỉ có dữ liệu chưa đủ hoặc nhiều candidate mơ hồ → giữ
     projection đã verify gần nhất và enqueue statuses ngay, không tự đoán bằng
     `MAX(expires_date_ms)`.
4. Renewal ledger latest cho `auto_renew_status`, grace, expiration intent và
   pending downgrade. `REFUND_REVERSED` insert full version mới không còn
   revocation → recompute tự hồi phục. `REVOKE` vẫn đi cùng reducer.
5. **Recompute account** = tốt nhất giữa các chain CÙNG ENV (CAS). Mỗi thay đổi
   effective tier/status/expiry tăng `version`, vô hiệu lease cũ ngay; thua CAS
   thì đọc lại và làm lại.
6. Mapping `effective_status` → hành vi khớp §8.1 client
   (`LooxSubscriptionState.swift`): `active|grace` → tier đầy đủ;
   `billing_retry|expired|revoked` → Free cho MUTATION MỚI (revoked chặn
   premium-create ngay; "giữ service state ≤72h" do wind-down job tự động).

Webhook: verify → INSERT inbox (PK dedupe → 200) → reducer → `processed_at_ms`
→ 200. Chữ ký/claim sai vĩnh viễn → 401; OCSP/online-check hoặc D1 lỗi trước
inbox → 503 để Apple retry. Lỗi reducer sau khi raw đã durable → 200, sweep xử
lại; taxonomy lỗi được pin bằng integration test B1-0.

### 4.4 Quota — saga có outbox, `released` là terminal

Typed entrypoint nhận `operation_id`, `request_fingerprint`, `event`, lease và
identity LẤY TỪ verifier result. `authorizeMutation` resolve `(env, account,
tier, cap)` từ lease+binding. Không lease chỉ xét env mặc định của deployment:
binding paid ở env đó trả `entitlement_refresh_required`, binding khác env bị
bỏ qua, còn lại vào Free bucket. Sau đó `reserveQuota` chạy MỘT câu SQL nguyên
tử:

~~~sql
INSERT INTO quota_operations
  (environment, service, operation_id, request_fingerprint, event,
   subscription_account_id, identity_key_hash, status, reserved_at_ms, ttl_expires_at_ms)
SELECT ?env, ?svc, ?op, ?fp, ?evt, ?sub, ?idk, 'reserved', ?now, ?now + ?ttl
WHERE (
  SELECT COUNT(*) FROM quota_operations
  WHERE environment = ?env AND service = ?svc
    AND ((?sub IS NOT NULL AND subscription_account_id = ?sub)
         OR (?sub IS NULL AND identity_key_hash = ?idk))
    AND ((status = 'committed'
          AND committed_at_ms > ?now - 2592000000)
         OR (status = 'reserved' AND ttl_expires_at_ms > ?now))
) < ?cap
ON CONFLICT(environment, service, operation_id) DO NOTHING;
~~~

- `changes==1` → reserved. `==0` → SELECT theo `(env, service, operation_id)`:
  tồn tại và
  `request_fingerprint` khớp → idempotent retry (trả trạng thái hiện có);
  fingerprint KHÁC → `409 idempotency_conflict`; reserved đã hết TTL →
  conditional release + `quota_lost`; không tồn tại → chạm quota. Fingerprint
  hash canonical business input + event + authenticated identity, KHÔNG hash
  lease secret để refresh lease không biến retry thành operation khác.
- **`commitQuota` correctness không phụ thuộc cron:** UPDATE chỉ khi
  `status='reserved' AND ttl_expires_at_ms > now`; committed cùng fingerprint →
  idempotent success; reserved đã quá TTL được conditional-transition sang
  `released` rồi trả `409 quota_lost`; released là terminal. Vì B có thể reserve
  ngay khi A hết TTL nhưng A không còn đường commit, không thể vượt cap.
- Expiry cron 1 phút chỉ cleanup reserved quá TTL. TTL: Link **2 phút**; Quick
  View **5 phút** (live SessionDO create→approval trần 180 giây + network
  margin), không còn câu hỏi động theo session.
- **Link outbox:** `INSERT shares + pending_commit(operation_id)` trong một D1
  `batch()` local; cron Link drain tới terminal.
- **Quick View outbox:** `SessionDO.claim()` ghi `{state: APPROVED, payload,
  quota_pending_commit}` trong CÙNG DO storage transaction rồi mới trả success.
  `SessionDO.alarm()` multiplex session expiry + quota retry, luôn schedule mốc
  sớm nhất; không có D1 outbox Quick View vì D1 không atomic với DO.
- Nhận `quota_lost` khi drain: **Link bù trừ** (revoke share vừa mint — service
  sở hữu revoke); **QV không thu hồi được thứ đã giao** → chấp nhận một lượt
  KHÔNG ĐẾM, nghiêng về phía user (nguyên tắc §2.4), bounded bởi tần suất crash
  trong cửa sổ TTL — không bao giờ deny sau khi đã giao.
- Luồng: `reserve → nghiệp vụ (+outbox) → commit` (fail trước side effect →
  `release` chủ động). §3.2 bảo toàn: thất bại không trừ (release/TTL), thành
  công không hoàn (committed bất biến, không có refund API). Outcome mơ hồ sau
  khi đã gọi storage KHÔNG được release; service đọc operation/outbox local và
  tiếp tục commit hoặc compensation idempotent.

### 4.5 Thay đổi ở ba worker hiện hữu

- Cả ba: `services` binding trỏ named entrypoint tương ứng (prod↔prod,
  staging↔staging), var `ENTITLEMENT_MODE: off | shadow | active`, typed RPC;
  identity truyền vào RPC chỉ lấy từ auth verifier result. Link thêm D1 outbox;
  Quick View mở rộng SessionDO state/alarm.
- **loox-relay** — `createAlias`: thay COUNT-rồi-INSERT
  (`aliases.ts:126-141`) bằng **conditional INSERT nguyên tử** (INSERT … SELECT
  … WHERE COUNT mọi alias retained theo principal < cap). Retained =
  `ACTIVE|DISABLED` kể cả `disabled_reason='billing'`; chỉ `TOMBSTONE` không
  tính — user không thể disable alias để né quota. Sửa cả race hiện có;
  cap lấy từ `tierForRelayPrincipal(principal, lease)` khi `active`, giữ
  `MAX_ALIASES_PER_PRINCIPAL` hiện tại làm trần abuse độc lập. Vượt →
  `quota_exceeded` (client map `.aliasLimit`); RPC fail ở mode `active` →
  `503 service_unavailable`. Grant relay đi trong field NGOÀI transcript ký
  `LOOX-RELAY-AUTHZ-V2` (transcript đóng băng bằng 10-vector parity test);
  `bind` và paid authorize chạy SAU `consumeNonce` + verify chữ ký principal;
  grant/lease ở ngoài transcript nhưng bound vào hash principal đó.
  **Wind-down cần trạng thái riêng `disabled_reason='billing'`** (migration
  nhỏ): alias bị billing-pause không được `createAlias`/enable thường bật lại
  — re-enable phải đi qua quota check.
- **loox-link** — create: verifier trả `attestKeyId`; typed RPC authorize lease
  rồi `reserve → (INSERT shares + D1 outbox cùng batch) → commit/drain`;
  `quota_lost` → revoke bù trừ.
- **loox-quick-view** — approve: verifier trả `attestKeyId`; typed RPC authorize
  lease rồi `reserve → DO transaction(payload + pending_commit) → commit/alarm
  drain`; `quota_lost` → chấp nhận không đếm (đã giao thì không thu hồi).

## 5. Cron Triggers (`loox-entitlement`)

| Lịch | Việc |
|---|---|
| 1 phút | Cleanup: `reserved` quá TTL → `released` terminal. Commit đã tự check TTL nên cron trễ không ảnh hưởng cap. |
| 15 phút | **History fixed-window:** staging chỉ poll Sandbox; prod chỉ poll Production. Window `[high_watermark-overlap 24h, now]`, giữ `window_start/end` cố định qua mọi page; clear `page_token` khi `hasMore=false` rồi mới nâng watermark. |
| 15 phút | **Prod-Sandbox known-chain statuses:** chỉ `(Sandbox, original_transaction_id)` đã được prod `/attach` đăng ký. Không global-poll Sandbox history vào prod, không tạo row prod từ dev/staging notification lạ. |
| Giờ/deadline | **Statuses có chủ đích:** chain tới entitlement/grace deadline, `grace/billing_retry`, trigger thiếu data/ambiguous candidates, attach mismatch, inbox `processed_at_ms IS NULL`. Authorization tự check deadline; reconcile chỉ làm projection hội tụ. |
| Theo deadline, fallback mỗi giờ | **Wind-down (§8.3), phase B6:** account rơi khỏi paid → hold 30 ngày; revoked → `hold_until = revoked_at + 72h`; đến hạn mới RPC relay billing-pause alias ngoài keep-selection. Job idempotent, không xóa dữ liệu. |
| Ngày | **Prune:** quota >40 ngày; grant/lease hết hạn; `raw_payload=NULL` notification >180 ngày; binding revoked >90 ngày sau khi không còn recovery reference. Ledger projection tối thiểu giữ cho audit/accounting. |

B6-0 có migration riêng: entitlement lưu wind-down state/`hold_until`; Relay
thêm `disabled_reason`, `billing_disabled_at`, `billing_recover_until` và
keep-selection do signed client command tạo. Alarm/job chạy theo deadline
(fallback hourly, không dựa cron ngày để hứa chính xác 72h). Normal enable không
được xóa reason `billing` nếu chưa qua entitlement quota check.

## 6. Rollout (enforcement sau client + purchases, legacy có cohort)

| Phase | Nội dung | Gate qua phase |
|---|---|---|
| **B1-0** | Spike official Apple library dưới workerd: verifier outer+nested, Server API, OCSP/error taxonomy. Không migration production. | Fixture thật + online failure tests xanh; fail thì dừng và quyết định runtime, không tự viết crypto mặc định. |
| **B1** | Worker + migration 0001 + attach statuses-check + webhook + versioned ledgers/projections + scoped history/statuses. Chưa public grant/lease. | Test reducer: dup/hash anomaly, refund cũ, current refund, REFUND_REVERSED, `isUpgraded`, upgrade/downgrade, ambiguous trigger giữ state; prod không nhập unknown Sandbox history. |
| **B2** | Named typed RPC + hashed grants/leases + insertion-first bind + saga; Link D1 outbox, Quick View DO outbox/alarm, relay conditional-insert. Workers `shadow`. | Sandbox lease không resolve Production/no-lease; lease không bao giờ vượt entitlement/grace deadline; identity chỉ từ verifier; cap-fail không burn grant; commit expired-before-cron → `quota_lost`; crash matrix Link/QV; race N request đúng cap. |
| **B3** | **Ship iOS integration DORMANT:** tạo appAccountToken, attach/refresh queue, grant bind, memory-only Sandbox lease, retry `entitlement_refresh_required`, gửi `entitlement_contract_version` cho telemetry; purchases OFF. | Đo **client-capable coverage** per service trên toàn bộ authenticated create traffic, gồm client cũ. Free user không có JWS/binding là bình thường; không gọi đó là binding coverage. Snapshot identity hiện hữu làm legacy cohort trước B5. |
| **B4** | **Purchases ON**, BE vẫn shadow. Người mua attach→bind→lease; không ai bị server chặn. | 100% paid accounts quan sát trong 7 ngày có active binding + lease refresh path; Sandbox/TestFlight/App Review flow; không paid request nào bị map silent-Free. |
| **B5** | Enforcement canary per service cho identity mới sau cutover; identity có trước cutover giữ legacy behavior tới sunset. Ramp riêng Relay/Link/QV, kill switch độc lập. | §12 BE xanh; paid-binding coverage 100%; client-capable mutation traffic ≥95% để bắt đầu canary; error/refresh SLO xanh. Full legacy sunset chỉ khi ≥99% trong 30 ngày hoặc có minimum-version policy owner duyệt. |
| **B6** | B6-0 protocol/migration review → UI keep-selection live → wind-down + billing reason + deadline jobs. | Signed selection không phá auth invariant; deadline/idempotency/rollback rehearsal; không đường xóa dữ liệu. |

Không phase nào bó user live về Free khi chưa có đường mua/bind; không thể né
quota vĩnh viễn bằng cách bỏ field version vì cohort dựa trên identity
`created_at` phía server, không tin client claim.

Effort thô v4: **14-18 ngày công BE + QA end-to-end** (B1-0/B1 ≈ 5-6,
B2 ≈ 5-6, B5 ≈ 2 + QA, B6 ≈ 2-3; B3-B4 chủ yếu iOS). Hạ tầng vẫn ≈ 0 ở tải hiện tại.

## 7. Privacy, bảo mật, vận hành

- Entitlement DB: UUID giả danh, transaction/product ID, trạng thái, mốc thời
  gian, hash identity/grant/lease — không email/alias/persona/item và không lưu
  raw principal/App Attest key. `principal_bindings` vẫn là billing linkage giả
  danh, ghi vào Privacy Policy update (§10.1).
- Inbox raw JWS có thể chứa thêm field Apple như storefront/price; retention
  180 ngày phải được disclosure đúng, access hạn chế, không đưa vào analytics;
  hết hạn đặt `raw_payload=NULL` nhưng giữ hash/metadata tối thiểu.
- Coverage rollout chỉ là aggregate per-service/build/contract version, không
  tạo dashboard hành vi per-user; số thương mại chuẩn vẫn đọc từ ASC (§11).
- Public surface: attach + App Attest challenge/register + webhook. Tier/quota/
  bind chỉ qua named Service Binding; webhook bảo vệ bằng verified JWS.
- Kill switch per-service `ENTITLEMENT_MODE=off` = hành vi hôm nay.
- Sandbox D1 staging: retention/reset có runbook (reset = xóa theo env + chạy
  lại history poll từ high_watermark mới) — không wipe tùy hứng.
- Sự cố entitlement: mutation mới `503 service_unavailable`; đọc + tài nguyên
  hiện hữu không đụng; không đường nào xóa dữ liệu.

### 7.1 SLO, telemetry và release gate production

Target ban đầu (đo 14 ngày shadow rồi tune, không nới correctness invariant):

| Signal | Target / alert |
|---|---|
| Named authorization RPC | Availability ≥99.9%/30 ngày, p95 ≤250ms; page khi 5xx >1% trong 5 phút. |
| `/attach` | p95 ≤3s không tính retry client; tách Apple 429/5xx, verify-invalid và D1 failure, không gộp mọi lỗi thành 500. |
| Hội tụ | Oldest unprocessed inbox <15 phút; Production history lag <45 phút; prod-Sandbox known-chain statuses lag <30 phút. |
| Saga/outbox | Link pending oldest <5 phút, Quick View pending oldest <10 phút; alert ngay nếu backlog tăng liên tục hoặc compensation fail. |
| Security invariant | Cross-env match, cùng ledger key khác payload hash, lease/account-version mismatch bất thường hoặc admin transfer không audit = alert severity cao. |

- Structured log chỉ có `request_id`, env, service, result code, latency,
  hashed/correlation ID cần thiết; tuyệt đối không log compact JWS, grant, lease,
  raw identity hay App Attest assertion. Metric label không chứa account/transaction
  ID để tránh cardinality và theo dõi per-user.
- Trước mỗi phase: migration rehearsal trên staging snapshot, export/restore
  rehearsal, forward-only migration + rollback bằng feature flag, dashboard/alert
  đã live và owner on-call được ghi trong runbook. Không chạy migration phá hủy
  cùng release bật enforcement.
- Mọi support action (reconcile cưỡng bức, revoke/rebind, Relay transfer) dùng
  credential nội bộ riêng, audit actor/reason/timestamp, idempotency key; Relay
  transfer cần dual confirmation vì có thể đổi quyền với alias hiện hữu.
- Incident drill trước B5: Apple API timeout/429, D1 unavailable, webhook replay,
  outbox stuck, reducer anomaly và kill switch từng service. `off` phải quay về
  hành vi live trước enforcement, ưu tiên user và không sửa/xóa dữ liệu.

## 8. Ngoài phạm vi V1

Win-back/offer code, Family SKU, web checkout, recipient-seat Approval Mode
(client-only), đồng bộ `subscriptionAccountID` qua iCloud Keychain (iOS repo),
dashboard riêng.

## Các quyết định cần owner phê duyệt

1. **Owner ký residual Sandbox-on-prod đúng phạm vi:** TestFlight/App Review có
   thể liên tục refresh lease 15 phút và dùng paid tier trên prod suốt Sandbox
   entitlement (TestFlight có thể tới một tuần). Người giữ Sandbox JWS hợp lệ có
   thể replay từ App Store binary vì backend không phân biệt được hai binary;
   lease bound principal/env, quota tách env, không sinh Production entitlement.
   Dữ liệu đã tạo không bị xóa, còn mutation paid mới luôn cần lease hiện hành.
2. **Legacy sunset:** đề xuất B5 chỉ enforce identity mới sau cutover; identity
   cũ grandfather 90 ngày. Full sunset khi client-capable traffic từng service
   ≥99% trong 30 ngày hoặc minimum-version policy đã duyệt — owner chốt mốc.
3. **Lease TTL/API budget:** ceiling mặc định Sandbox 15 phút, Production 24 giờ
   và luôn cắt tại entitlement/grace deadline.
   B1/B4 đo số lần statuses call thực tế, 429/backoff và ceiling trước khi chốt
   config production. Không kéo dài Sandbox lease chỉ để giảm API call.
4. **`Set App Account Token`**: defensive follow-up cho JWS thiếu token — xác
   minh endpoint/điều kiện trên tài khoản ASC trước khi hứa; V1 trả
   `token_missing` + client luôn set token từ purchase đầu (IAP chưa live nên
   không có backlog thiếu token thật).
5. **Epic C7 (App Attest hardening)**: cần owner + timeline TRƯỚC B5 (chặn
   ladder attach `active`); lưu ý C7 không giải TestFlight-vs-App-Store — cái
   đó do env-scoped lease mục 1 lo.
