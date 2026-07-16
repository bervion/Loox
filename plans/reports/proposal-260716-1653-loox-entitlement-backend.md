---
title: "Loox Entitlement Service - Proposal BE trên Cloudflare (không VPS)"
status: proposal-v3
updated: 2026-07-16
review: "v2 tích hợp phản biện vòng 1 (grant thay bearer-UUID, saga quota, reducer, reconcile chủ động, bỏ KV, ma trận env, hard-gate verifier). v3 tích hợp vòng 2: env-scoped entitlement end-to-end (P0 TestFlight leak — giải bằng namespace + sandbox tự hết hạn, KHÔNG route TestFlight sang staging vì chung binary với App Store và App Review cần sandbox trên prod), transaction ledger bất biến, saga có outbox + released là terminal (không còn late-commit vượt cap), attach phải hỏi Get All Subscription Statuses trước khi cấp grant, named WorkerEntrypoint per service, binding_id surrogate + partial-unique, relay conditional-insert + cap 1 principal active, rollout đảo thứ tự (client dormant + purchases trước enforcement), fixed-window polling."
scope: [backend-entitlements, cloudflare-workers, apple-server-notifications, quota-enforcement]
source_of_truth: "Thực thi phần backend của proposal-260714-2231-loox-subscription-strategy.md (§7, §8, §10, §12). Bảng tier/quota và bảng trạng thái §8.1 đã đóng băng ở client (VaultifyCore/Subscription/LooxTier.swift, LooxSubscriptionState.swift) — BE phải khớp từng dòng."
repo: "~/Developer/Projects/frontend/looxpassword (workers/loox-relay, loox-link, loox-quick-view, loox-config)"
---

# Loox Entitlement Service - Proposal BE trên Cloudflare (v3)

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
  binding, grant, quota đều mang env; tier của một binding chỉ resolve từ dữ
  liệu CÙNG env (mục 1). Sandbox không bao giờ mở khóa gì cho hàng thật.
- **Binding qua `binding_grant` một lần, TTL 10 phút**, lưu HASH của grant;
  consume + cap-check + ghi binding trong MỘT transaction D1.
  `subscription_account_id` không bao giờ là proof of ownership.
- **Sổ cái `subscription_transactions` bất biến theo `transaction_id`** là nền
  reducer; chain và account chỉ là projection tính lại từ sổ cái — refund một
  kỳ CŨ không thể giết kỳ hiện tại dù chữ ký refund mới hơn.
- **Quota là saga `reserve → commit/release`** với `operation_id` +
  `request_fingerprint`; `released` là TRẠNG THÁI CUỐI (commit muộn bị từ chối
  — không tồn tại đường vượt cap); mỗi dịch vụ có **transactional outbox**
  trong D1 của chính nó để commit đến nơi dù crash.
- **`/attach` không tin JWS một mình**: sau verify chữ ký phải gọi
  `Get All Subscription Statuses` (đúng host theo env) rồi mới cấp paid grant
  — chặn replay JWS đã refund/revoke.
- **ASSN v2 chỉ là trigger.** Reconcile chủ động bằng `Get Notification
  History` theo CỬA SỔ THỜI GIAN CỐ ĐỊNH (paginationToken chỉ để phân trang
  trong cửa sổ, không phải durable cursor) + statuses có chủ đích là đường hội
  tụ đảm bảo (sandbox không retry notification).
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
  trước, enforcement `active` sau khi đo binding coverage (mục 6) — không bao
  giờ để user live bị bó về Free khi chưa có đường mua/bind.
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

1. **Không route TestFlight sang staging được**: TestFlight và App Store dùng
   CHUNG một binary Release (một bộ endpoint); runtime-detect TestFlight bằng
   receipt heuristic là fragile và không được Apple hỗ trợ. Quan trọng hơn,
   **App Review mua bằng sandbox account trên chính bản App Store** — §12 yêu
   cầu reviewer chạm được mọi paid feature, nên prod BẮT BUỘC tôn trọng
   sandbox transaction ở một mức nào đó.
2. **Chống rò vĩnh viễn bằng hai lớp:**
   - **Namespace theo env end-to-end**: mọi bảng mang cột `environment`;
     binding sinh từ grant Sandbox chỉ resolve tier từ account/chain Sandbox.
     Không có phép lai env ở bất kỳ query nào (test bắt buộc).
   - **Sandbox tự hết hạn nhanh**: đồng hồ sandbox của Apple nén thời gian
     (năm ≈ 1 giờ, tối đa vài lần renew rồi dừng) — reducer + reconcile đóng
     entitlement Sandbox trong vòng ~giờ. Kẻ "giữ Max từ TestFlight" chỉ giữ
     được tới chu kỳ reconcile kế tiếp.
   - User thường KHÔNG thể tạo sandbox purchase trên bản App Store (sandbox
     account do chính mình cấp trong ASC) — bề mặt còn lại là tester nội bộ và
     App Review, đúng đối tượng cần hoạt động.
3. **Residual được chấp nhận có chủ đích** (cần owner ký): tester/App Review
   cầm tier Sandbox ngắn hạn trên dịch vụ prod, quota đếm trong namespace
   Sandbox riêng — không lẫn counter với hàng thật.
4. QA paid-flow E2E chủ lực chạy trên staging/dev build (sandbox → staging
   worker). ASSN sandbox URL của ASC trỏ **staging**; dòng Sandbox nằm trên
   prod (TestFlight/App Review) hội tụ bằng history poll + statuses theo host
   sandbox (mục 5).
5. App Attest: verifier hiện tại trả `environment: 'unknown'`, chain-verify
   còn `REAL_APPLE_FIXTURE_PENDING`, chưa wire vào create path
   (`loox-link/src/app-attest/attestation.ts:118-135`, epic C7). An ninh lõi
   của `/attach` đứng trên chữ ký Apple của transaction JWS + statuses check;
   App Attest là lớp abuse theo ladder `off → shadow → active`. C7 không giải
   quyết TestFlight-vs-App-Store (cả hai đều Production attest) — cái đó do
   namespace env ở trên lo. C7 chặn ladder `active`, không chặn B1-B2.

## 2. Nguyên tắc không thương lượng (kế thừa §2, §7, §10 + v3)

1. Lỗi entitlement không bao giờ xóa/sửa dữ liệu — chỉ được chặn mutation TẠO
   MỚI; không chặn đọc, không xóa alias/share/session đang sống vì billing.
2. `subscription_account_id` lấy từ `appAccountToken` BÊN TRONG JWS đã verify;
   client claim chỉ để đối chiếu. Không định danh nào là bearer credential.
3. Grant/entitlement chỉ được cấp từ TRẠNG THÁI HIỆN TẠI đã xác nhận với Apple
   (statuses), không từ một chữ ký từng-hợp-lệ.
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
    AT -->|"statuses check TRƯỚC khi cấp grant"| API
    subgraph loox-entitlement worker
      WH --> RED["Verify outer+nested JWS -> Ledger -> Reducer"]
      AT --> RED
      RED --> D1[("D1: transactions(ledger) / chains / accounts /<br/>notifications / bindings / grants /<br/>quota_operations / reconcile_state")]
      CRON["Cron: history poll (fixed windows),<br/>statuses reconcile, wind-down, prune"] --> API
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

### 3.3 Data model (D1, migration 0001 — CHƯA freeze cho tới hết review vòng 3)

~~~sql
-- SỔ CÁI bất biến theo transaction: mỗi renewal/refund/reversal là dữ liệu
-- mới nhất đã verify của CHÍNH transaction đó (guard signedDate per-row).
CREATE TABLE subscription_transactions (
  transaction_id TEXT NOT NULL,
  environment TEXT NOT NULL,                  -- 'Production' | 'Sandbox'
  original_transaction_id TEXT NOT NULL,
  subscription_account_id TEXT,               -- appAccountToken trong JWS (nullable: purchase cũ)
  product_id TEXT NOT NULL,
  purchase_date_ms INTEGER,
  expires_date_ms INTEGER,
  revocation_date_ms INTEGER,
  revocation_reason TEXT,
  signed_date_ms INTEGER NOT NULL,            -- guard: chỉ ghi đè khi mới hơn CHO ROW NÀY
  raw_kind TEXT NOT NULL,                     -- 'transaction' | 'renewal_info' (renewal lưu row riêng theo original)
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (environment, transaction_id, raw_kind)
);
CREATE INDEX idx_txn_chain ON subscription_transactions(environment, original_transaction_id);

-- PROJECTION theo chuỗi (tính lại từ sổ cái, không ghi tay).
CREATE TABLE subscription_chains (
  environment TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  subscription_account_id TEXT,
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
  notification_uuid TEXT PRIMARY KEY,
  environment TEXT NOT NULL,
  notification_type TEXT NOT NULL,
  subtype TEXT,
  original_transaction_id TEXT,
  signed_date_ms INTEGER NOT NULL,
  raw_payload TEXT,                           -- NULL sau prune (dòng tối thiểu giữ lại)
  received_at_ms INTEGER NOT NULL,
  source TEXT NOT NULL,                       -- 'webhook' | 'history_poll' | 'test'
  processed_at_ms INTEGER
);

-- Grant một lần: LƯU HASH, không lưu plaintext.
CREATE TABLE binding_grants (
  grant_hash TEXT PRIMARY KEY,                -- SHA256(grant secret gửi cho client)
  environment TEXT NOT NULL,
  subscription_account_id TEXT NOT NULL,
  service TEXT NOT NULL,                      -- 'relay' | 'link' | 'quickview'
  binding_type TEXT NOT NULL,
  binding_value_hash TEXT NOT NULL,
  expires_at_ms INTEGER NOT NULL,             -- now + 10 phút
  consumed_at_ms INTEGER
);

-- Binding có lịch sử: surrogate PK + partial-unique cho active.
CREATE TABLE principal_bindings (
  binding_id INTEGER PRIMARY KEY AUTOINCREMENT,
  environment TEXT NOT NULL,
  binding_type TEXT NOT NULL,
  binding_value TEXT NOT NULL,
  subscription_account_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',      -- 'active' | 'revoked'
  created_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL,
  revoked_at_ms INTEGER
);
CREATE UNIQUE INDEX uq_bind_active
  ON principal_bindings(environment, binding_type, binding_value)
  WHERE status = 'active';
CREATE INDEX idx_bind_sub ON principal_bindings(environment, subscription_account_id, status);

-- Saga quota: reservation + ledger; released là TERMINAL.
CREATE TABLE quota_operations (
  operation_id TEXT PRIMARY KEY,
  request_fingerprint TEXT NOT NULL,          -- SHA256(payload chuẩn hóa); khác -> 409
  environment TEXT NOT NULL,
  service TEXT NOT NULL,
  event TEXT NOT NULL,
  subscription_account_id TEXT,               -- NULL = Free theo identity
  identity_key TEXT NOT NULL,
  status TEXT NOT NULL,                       -- 'reserved' | 'committed' | 'released'
  reserved_at_ms INTEGER NOT NULL,
  ttl_expires_at_ms INTEGER NOT NULL,
  committed_at_ms INTEGER
);
CREATE INDEX idx_quota_window ON quota_operations(environment, service, subscription_account_id, reserved_at_ms);
CREATE INDEX idx_quota_identity ON quota_operations(environment, service, identity_key, reserved_at_ms);

-- Reconcile theo CỬA SỔ CỐ ĐỊNH (paginationToken không phải durable cursor).
CREATE TABLE reconcile_state (
  scope_key TEXT PRIMARY KEY,                 -- 'history:<env>' | 'chain:<env>:<otid>'
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

Tier/quota là hằng số code (`quotas.ts`) chép từ `LooxTier.swift`, unit test
pin: `retainedAliases 1/10/200`, `linkCreates30d 3/30/300`,
`quickViewApprovals30d 3/30/300`. Personas/Watchtower/themes: client-only.

### 3.4 Vì sao D1 (chưa Queue/DO) — và giới hạn đã tính

Tải trần ~vài nghìn write/ngày. Mọi thao tác điều-kiện-rồi-ghi là MỘT câu SQL
hoặc một `batch()` toàn-conditional (không read-modify-write ở JS). Upgrade
path: `SubscriptionDO` per account nếu một ngày cần serialize chặt (pattern
`SessionDO` đã có). Outbox của từng service nằm trong D1 CỦA SERVICE ĐÓ để
side-effect + outbox là một transaction local thật sự.

## 4. Contract API

### 4.1 Public — `POST /v1/entitlement/attach`

Body: `{ transaction_jws, requested_bindings: [{service, binding_type, binding_value_hash}] }`

1. Verify JWS (3.2) → ghi sổ cái + reducer (dữ liệu lịch sử, chưa cấp gì).
   `subscription_account_id := payload.appAccountToken`; thiếu → `token_missing`
   (client PHẢI set token từ purchase đầu tiên — IAP chưa live nên đây là
   đường chính; `Set App Account Token` chỉ là defensive follow-up, xem Câu hỏi 4).
2. **Gọi `Get All Subscription Statuses`** (host theo env) cho
   `originalTransactionId` → reducer áp trạng thái HIỆN TẠI. Apple API không
   trả lời được → `503 retryable`, KHÔNG cấp grant từ JWS một mình (chặn
   replay JWS đã refund/revoke).
3. Trạng thái hiện tại là paid → phát `binding_grants` (trả PLAINTEXT secret
   một lần cho client, DB chỉ giữ `grant_hash`; TTL 10 phút; cap theo loại —
   mục 4.2). Free/expired → response không grant.
4. Response: `{ tier, status, expires_at_ms, grants: [{grant, service, binding_type}] }`.

Auth: App Attest ladder riêng của worker (pattern `attest_challenges`/
`attest_keys`). Restore đa thiết bị nằm trong V1: máy B đọc `appAccountToken`
từ verified transaction của nó → attach → grants mới (rebind tự revoke binding
cũ nếu chạm cap).

### 4.2 Bind — RPC `bind({grant, binding_value})` trên entrypoint của từng service

Named entrypoint đã cố định `service`; dịch vụ gọi SAU khi đã authenticate
định danh gốc theo đường chuẩn của nó (relay: verify chữ ký principal +
`consumeNonce` xong; link/qv: assertion ladder hiện hành).

MỘT `batch()` D1, hai câu đều conditional, verify `meta.changes` từng câu:

1. Consume grant: `UPDATE binding_grants SET consumed_at_ms=?now WHERE
   grant_hash=SHA256(?grant) AND consumed_at_ms IS NULL AND expires_at_ms>?now
   AND service=?svc AND binding_type=?bt AND binding_value_hash=SHA256(?bv)
   AND environment=?env` — changes==1 bắt buộc.
2. Ghi binding active (INSERT … SELECT … WHERE đếm active của
   (env, subscription, binding_type) < cap) + nếu rebind: câu UPDATE revoke
   dòng active cũ của chính binding_value đó đứng trước trong batch.

Cap theo loại (config): **relay_principal = 1 active** (principal đã escrow
cross-device — một principal per user là bản chất; đồng thời chặn nhân quota
alias theo principal), **attest_key_link = 5**, **attest_key_qv = 5**, kèm
self-service revoke/replace qua chính flow attach→bind (grant mới revoke dòng
cũ). Vượt cap → lỗi rõ + runbook.

### 4.3 Reducer trạng thái (ledger-first)

Mọi trigger (webhook, history poll, attach, statuses) đi một đường:

1. Verify OUTER rồi NESTED JWS riêng từng cái. Trigger không có transaction
   data (`RENEWAL_EXTENSION` SUMMARY, loại lạ…) → KHÔNG đổi state, đánh dấu
   `reconcile_state['chain:…']` để poll statuses.
2. **Upsert sổ cái theo (env, transaction_id, kind)** với guard
   `signed_date_ms` CỦA CHÍNH ROW ĐÓ — refund một transaction cũ ký muộn chỉ
   cập nhật row transaction cũ, không đè gì của kỳ hiện tại.
3. **Recompute chain từ sổ cái**: transaction có `expires_date_ms` lớn nhất
   chưa bị revoke quyết định kỳ hiện tại; `revocation_date/reason` chỉ giết
   chain khi rơi vào transaction cấp quyền hiện hành; renewal_info cho
   `auto_renew_status`/grace → `active | grace | billing_retry | expired |
   revoked` (+ cờ pending-downgrade, không đổi tier trước effective date).
4. `REFUND_REVERSED` → cũng chỉ là trigger recompute (row transaction mất
   revocation trong dữ liệu mới → tự hồi phục). `REVOKE` (Family Sharing —
   Loox tắt FS) đi qua cùng đường, không nhánh riêng.
5. **Recompute account** = tốt nhất giữa các chain CÙNG ENV của account (CAS
   bằng `version`; thua thì đọc lại làm lại).
6. Mapping `effective_status` → hành vi khớp §8.1 client
   (`LooxSubscriptionState.swift`): `active|grace` → tier đầy đủ;
   `billing_retry|expired|revoked` → Free cho MUTATION MỚI (revoked chặn
   premium-create ngay; "giữ service state ≤72h" do wind-down job tự động).

Webhook: verify → INSERT inbox (PK dedupe → 200) → reducer → `processed_at_ms`
→ 200. Verify fail → 401. Lỗi sau khi lưu raw → vẫn 200, sweep xử lại.

### 4.4 Quota — saga có outbox, `released` là terminal

`reserveQuota({operation_id, request_fingerprint, event, binding_value})`
(entrypoint đã biết service) — MỘT câu SQL nguyên tử:

~~~sql
INSERT INTO quota_operations
  (operation_id, request_fingerprint, environment, service, event,
   subscription_account_id, identity_key, status, reserved_at_ms, ttl_expires_at_ms)
SELECT ?op, ?fp, ?env, ?svc, ?evt, ?sub, ?idk, 'reserved', ?now, ?now + ?ttl
WHERE (
  SELECT COUNT(*) FROM quota_operations
  WHERE environment = ?env AND service = ?svc
    AND ((?sub IS NOT NULL AND subscription_account_id = ?sub)
         OR (?sub IS NULL AND identity_key = ?idk))
    AND reserved_at_ms > ?now - 2592000000
    AND (status = 'committed'
         OR (status = 'reserved' AND ttl_expires_at_ms > ?now))
) < ?cap
ON CONFLICT(operation_id) DO NOTHING;
~~~

- `changes==1` → reserved. `==0` → SELECT theo `operation_id`: tồn tại và
  `request_fingerprint` khớp → idempotent retry (trả trạng thái hiện có);
  fingerprint KHÁC → `409 idempotency_conflict`; không tồn tại → chạm quota.
- **`commitQuota` chỉ từ `reserved`** (kể cả reserved đã quá TTL nhưng CHƯA bị
  expiry job nhả). **`released` là terminal**: commit gặp released →
  `409 quota_lost` — không tồn tại đường "A hết hạn, B chiếm slot, A commit"
  → **không bao giờ vượt cap**.
- Expiry job (cron 1 phút, trên entitlement) nhả `reserved` quá TTL → `released`.
  TTL đặt dư dả so với nghiệp vụ (Link 2 phút; QV = trần vòng đời session).
- **Transactional outbox tại từng service** (bảng mới trong D1 của service):
  side effect + outbox row `pending_commit(operation_id)` trong MỘT `batch()`
  local (Link: cùng batch với INSERT `shares` — `shares.ts:96`; QV: outbox
  ngay cạnh điểm ghi giao hàng của `session-do-mailbox.ts`, thứ tự
  giao-hàng-trước, xem dưới). Sau đó gọi `commitQuota`; thành công → xóa/đánh
  dấu outbox. Cron nhỏ của service drain outbox retry commit đến terminal.
- Nhận `quota_lost` khi drain: **Link bù trừ** (revoke share vừa mint — service
  sở hữu revoke); **QV không thu hồi được thứ đã giao** → chấp nhận một lượt
  KHÔNG ĐẾM, nghiêng về phía user (nguyên tắc 2.4), bounded bởi tần suất crash
  trong cửa sổ TTL — không bao giờ deny sau khi đã giao.
- Luồng: `reserve → nghiệp vụ (+outbox) → commit` (fail trước side effect →
  `release` chủ động). §3.2 bảo toàn: thất bại không trừ (release/TTL), thành
  công không hoàn (committed bất biến, không có refund API).

`tier({binding_value})` — relay dùng cho alias quota.

### 4.5 Thay đổi ở ba worker hiện hữu

- Cả ba: `services` binding trỏ named entrypoint tương ứng (prod↔prod,
  staging↔staging), var `ENTITLEMENT_MODE: off | shadow | active`, bảng outbox
  (Link/QV) trong D1 của chính worker.
- **loox-relay** — `createAlias`: thay COUNT-rồi-INSERT
  (`aliases.ts:126-141`) bằng **conditional INSERT nguyên tử** (INSERT … SELECT
  … WHERE COUNT(active+paused theo principal) < cap) — sửa cả race hiện có;
  cap lấy từ RPC `tier` khi `active` (Free khi không binding), giữ
  `MAX_ALIASES_PER_PRINCIPAL` hiện tại làm trần abuse độc lập. Vượt →
  `quota_exceeded` (client map `.aliasLimit`); RPC fail ở mode `active` →
  `503 service_unavailable`. Grant relay đi trong field NGOÀI transcript ký
  `LOOX-RELAY-AUTHZ-V2` (transcript đóng băng bằng 10-vector parity test);
  `bind` chạy SAU `consumeNonce` + verify chữ ký principal.
  **Wind-down cần trạng thái riêng `disabled_reason='billing'`** (migration
  nhỏ): alias bị billing-pause không được `createAlias`/enable thường bật lại
  — re-enable phải đi qua quota check.
- **loox-link** — create: `reserve → (INSERT shares + outbox cùng batch) →
  commit/drain`; `quota_lost` → revoke bù trừ.
- **loox-quick-view** — approve: `reserve → giao hàng DO → outbox → commit/
  drain`; `quota_lost` → chấp nhận không đếm (đã giao thì không thu hồi).

## 5. Cron Triggers (`loox-entitlement`)

| Lịch | Việc |
|---|---|
| 1 phút | Expiry job: `reserved` quá TTL → `released` (terminal). |
| 15 phút | **History poll theo CỬA SỔ CỐ ĐỊNH** per env: `[high_watermark - overlap 24h, now]`; `page_token` chỉ dùng trong cửa sổ, clear khi `hasMore=false` rồi nâng `high_watermark`. Lease + backoff theo `failure_count`. Notification mới → inbox (`source='history_poll'`, PK dedupe) → reducer. Host theo env (dòng Sandbox trên prod đi host sandbox). |
| Giờ | **Statuses reconcile có chủ đích**: chain `grace/billing_retry`, trigger thiếu data, attach mismatch, inbox tồn `processed_at_ms IS NULL`. Không quét toàn bộ theo tuổi. |
| Ngày | **Wind-down (§8.3) — phase B6, tách khỏi quota:** account rơi khỏi paid → cửa sổ 30 ngày alias vượt quota; hết cửa sổ → RPC relay đặt `disabled_reason='billing'` các alias user chưa chọn giữ. `revoked` → cùng job, delay 72h TỰ ĐỘNG. Idempotent, có rollback rehearsal, CHỈ bật khi client có UI chọn alias giữ lại. Mốc khôi phục 90 ngày (§8.4). |
| Ngày | **Prune:** `quota_operations` > 40 ngày; grants hết hạn; `raw_payload = NULL` cho notification > 180 ngày (giữ dòng tối thiểu); binding `revoked` > 90 ngày. |

## 6. Rollout (đảo thứ tự v2 — enforcement SAU client + purchases)

| Phase | Nội dung | Gate qua phase |
|---|---|---|
| **B1** | Worker + schema + verify gate 3.2 (hard) + attach (statuses-check, chưa grants cũng được) + webhook 2 env + ledger/reducer + history poll fixed-window. | Official library pass dưới workerd; Request-a-Test-Notification 2 env về đúng nơi; test reducer: dup, per-row signedDate, refund kỳ cũ không giết kỳ hiện tại, REFUND_REVERSED hồi phục, trigger thiếu data không đổi state; test env-scoping: Sandbox không bao giờ resolve cho binding Production. |
| **B2** | Named entrypoints RPC + grants (hash) + bind atomic + saga + outbox ở Link/QV + relay conditional-insert. Ba worker `ENTITLEMENT_MODE=shadow` (log, không chặn). | Race test reserve N đồng thời đúng cap; retry cùng op idempotent, khác fingerprint → 409; commit-sau-released → 409 `quota_lost` + Link bù trừ chạy; grant sai service/hash/TTL/env bị từ chối trong MỘT batch. |
| **B3** | **iOS ship client integration DORMANT**: sinh token trước purchase, attach queue, nhận/dùng grants, gửi claim — tất cả sau `purchasesEnabled=false`. Đo **binding coverage** qua shadow log. | Shadow数 khớp: user thật (Free) không bị ảnh hưởng; binding coverage tăng theo update adoption. |
| **B4** | **Purchases ON**: ASC products live + client flip `LooxMembership.purchasesEnabled` (paywall/gate client-side hoạt động). BE vẫn `shadow` — người mua được ghi nhận tier, KHÔNG ai bị server chặn. | Sandbox + TestFlight round-trip: mua → attach → bind → tier đúng trên shadow log; §12 client gates xanh. |
| **B5** | **Enforcement `active`** staging → prod (quota + tier), coordinated flag per-service. Runbook support (tra theo original_transaction_id, revoke/rebind, refund, 503 posture). | Ma trận §12 BE: refund, refund-reversed, expiration, grace, upgrade, downgrade, restore end-to-end sandbox; client claim không bypass; binding coverage đạt ngưỡng đã chốt với owner; 503 posture kiểm chứng. |
| **B6** | Wind-down + relay `disabled_reason='billing'` + hold 72h tự động. **Prerequisite: client UI chọn alias giữ lại đã live.** | Job idempotent chạy lặp vô hại; rollback rehearsal; không đường xóa dữ liệu. |

Không phase nào bó user live về Free khi chưa có đường mua/bind (P1-7).
Effort thô v3: **12-16 ngày công BE + QA end-to-end sandbox** (B1 ≈ 5, B2 ≈ 4,
B5 ≈ 2 + QA, B6 ≈ 2-3; B3-B4 chủ yếu iOS). Chi phí hạ tầng ≈ 0.

## 7. Privacy, bảo mật, vận hành

- Entitlement DB: UUID giả danh, transaction id, product id, trạng thái, mốc
  thời gian, hash — không email/alias/persona/item. Không analytics per-user;
  số thương mại đọc từ ASC (§11). `principal_bindings` là billing linkage giả
  danh duy nhất — ghi vào Privacy Policy update (§10.1).
- Public surface chỉ attach + webhook; webhook bảo vệ bằng verify JWS.
- Kill switch per-service `ENTITLEMENT_MODE=off` = hành vi hôm nay.
- Sandbox D1 staging: retention/reset có runbook (reset = xóa theo env + chạy
  lại history poll từ high_watermark mới) — không wipe tùy hứng.
- Sự cố entitlement: mutation mới `503 service_unavailable`; đọc + tài nguyên
  hiện hữu không đụng; không đường nào xóa dữ liệu.

## 8. Ngoài phạm vi V1

Win-back/offer code, Family SKU, web checkout, recipient-seat Approval Mode
(client-only), đồng bộ `subscriptionAccountID` qua iCloud Keychain (iOS repo),
dashboard riêng.

## Câu hỏi chưa chốt

1. **Owner ký residual mục 1.3**: tester/App Review cầm tier Sandbox ngắn hạn
   trên prod (namespace riêng, tự hết hạn theo đồng hồ sandbox) — đây là điều
   kiện để App Review chạm được paid features (§12); từ chối thì phải có cơ
   chế review-account allowlist thay thế.
2. **Ngưỡng binding coverage cho B5** (bao nhiêu % active user trên bản app đã
   có attach plumbing thì mới bật enforcement) — đề xuất ≥85% sessions 30 ngày.
3. **TTL saga cho Quick View** = trần vòng đời session (lấy số chính xác từ
   `SessionDO` khi implement) — xác nhận không có đường approve nào dài hơn.
4. **`Set App Account Token`**: defensive follow-up cho JWS thiếu token — xác
   minh endpoint/điều kiện trên tài khoản ASC trước khi hứa; V1 trả
   `token_missing` + client luôn set token từ purchase đầu (IAP chưa live nên
   không có backlog thiếu token thật).
5. **Epic C7 (App Attest hardening)**: cần owner + timeline TRƯỚC B5 (chặn
   ladder attach `active`); lưu ý C7 không giải TestFlight-vs-App-Store — cái
   đó do env-namespace mục 1 lo.
