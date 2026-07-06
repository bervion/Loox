# Persona / Spaces / Email Relay — Proposal V3 (LOCKED 2026-07-06)

Status: **Decisions locked** bởi proposal author sau 3 round review. Không cần research round tổng quát thêm. Mỗi phase vẫn cần implementation plan riêng trước khi code.

Nguồn đối chiếu:
- `plans/reports/proposal-review-260706-1151-persona-email-alias-architecture-report.md` (8 câu xác minh + BE/FE audit)
- `plans/reports/from-dev-team-to-proposal-author-260706-1223-persona-relay-tasks-a-e-verification-report.md` (tasks A–E)

## Product framing

Một người → nhiều danh tính số (Persona), mỗi Persona có profile, spaces, email aliases, isolation policy riêng. Vault core giữ nguyên local-first + E2E encrypted; relay là **opt-in capability** với trust boundary riêng, disclose rõ (không phá claim vault encryption, nhưng ngừng marketing câu tuyệt đối "no backend" khi relay ship).

UI terms: EN "Personas/Identities", VI "Danh tính". Item type `identity` cũ rename UI → "Personal Profile / Hồ sơ cá nhân". Cấm từ "Fake identity/Danh tính giả".

## Decisions đã khóa (D1–D14)

| # | Quyết định |
|---|---|
| D1 | Cloudflare dashboard check (plan/Email Sending beta/billing) bắt buộc **trước P4C**, không block P0–P4A. Checklist trong §Dashboard. |
| D2 | Relay Principal = **P256.Signing ONLY** V1. Không HPKE role (YAGNI — chỉ thêm khi có protocol server→principal confidential payload). `principalID = SHA256("LOOX-RELAY-PRINCIPAL-V1" ‖ canonical pubkey)`. |
| D3 | Escrow = **dedicated CloudKit record `RelayPrincipalEscrow`** theo blueprint `ParticipantEscrowService` (singleton, first-writer-wins, sealed dưới Vault Key, tự tạo zone, độc lập `iCloudSyncEnabled`). KHÔNG nhét vào `VaultKeyBundle` hay `PersonaRecord`. 1 logical principal/user V1; principal lifecycle ≠ persona lifecycle. |
| D4 | Erase Vault → principal chết theo, **nhưng phải orchestrate**: authenticate → `POST /v1/principal/disable-all` (signed command: principalID, epoch, nonce, issuedAt) → durable ack → erase. **Offline: block destructive erase** với message "Cần mạng để xóa dữ liệu Email Relay" (chỉ khi có active aliases). Không pre-generated revocation secret V1. |
| D5 | Principal rotation = **epoch machinery tối giản**: `RelayPrincipalState{principalID, epoch: UInt64, signingPublicKey}`; backend pin (principal_id, current_epoch, current_public_key, status); rotation = key epoch N signs "rotate to N+1, NewPubKey", server CAS `WHERE current_epoch = N`; old epoch/key rejected. KHÔNG clone full AccessGrant machinery. |
| D6 | Search **mặc định scope theo Space hiện tại**, chip đổi được (Spaces / All Spaces / Shared with Me). "Search All Identities" phải là explicit user action. Sửa inconsistency global-search hiện tại (`VaultRepository+Folders.swift:230`). |
| D7 | Persist selected Space **per-Persona**: `lastSelectedSpaceByPersona` — local preference (@AppStorage/typed store), KHÔNG sync V1, KHÔNG trộn vào identity truth. |
| D8 | Transcript V2 (`one_time`) **trước** extraction. Ordering D0–D8 (§Transcript). `ASSERTION_MODE=required` cấm bật trước D0–D5. |
| D9 | App Attest **per-service**: loox-relay có `attest_keys`/`attest_challenges` D1 riêng. Shared verifier CODE, separate trust STATE. Không cross-trust từ loox-link. |
| D10 | Folder → Space **promotion** (90/10). Model: Persona → Space → Items (flat, không thêm tầng Folder dưới Space). Tags = multi-dimensional taxonomy. |
| D11 | P0 gọi là **"Space Hardening"** (không phải migration — UI đã coi Folder là Space). Type `FolderRecord` giữ tên phase đầu; symbol rename là tech-debt phase riêng nếu đáng. |
| D12 | Primary Space = **`Persona.primarySpaceID`** (single pointer, tránh distributed uniqueness `Space.isPrimary` bị sync conflict). Structural → có thể sync. Tách biệt `lastSelectedSpaceID` (UI pref, local). Bỏ `folders.first` heuristic. |
| D13 | **MAIL-0 tách khỏi roadmap, làm NGAY**: support@/security@ đang bounce (zone không MX) là production bug độc lập. Scope §MAIL-0. Không publish SPF/DKIM sai kiểu check-box; DMARC theo actual sending setup. |
| D14 | Relay V1 = **receive-only vì product reason** (không phải capability absence — Cloudflare `reply()` tồn tại với restrictions). Alias setup UI bắt buộc warning: "Replies from your destination inbox may reveal your real email address." P5+ mới nghiên cứu Cloudflare-native reply. |

## Invariants (ghi vào mọi phase plan liên quan)

```
INV-R01  App Attest identity MUST NOT be the long-lived logical owner of relay resources.
INV-R02  A relay command MUST be authorized by the current Relay Principal epoch AND
         independently admitted by the relay service's App Attest boundary.
INV-R03  strictAnonymous context MUST NOT silently surface, rank, search, or prefill
         identity-bearing data from another Persona. (Candidate EXCLUDED, not down-ranked.)
INV-R04  Cron MUST NOT be required to enforce alias expiry or revocation; hot paths
         enforce current state. Cron only reclaims garbage.
INV-R05  A delivered shared/relay secret and an authorization grant have distinct
         revocation semantics and MUST NOT be described as equivalent.
```

## Roadmap V3

```
MAIL-0  Corporate inbound bootstrap (NGAY, độc lập)
P0      Space Hardening            (no backend)
P1      Persona Core               (no backend)
P2      Persona Context + AutoFill (no backend)
P3      Local Alias Model          (no backend)
P4A     Relay Security Foundation
P4B     Email Ingress Beta (receive-only, verified-destination internal beta)
P4C     Production Delivery benchmark (CF Email Sending Beta vs SES/Postmark contingency)
P5      Shared Space Persona Representation (sau Sharing V2 stable + space membership model)
```

### MAIL-0 — Corporate inbound bootstrap — DONE (pending propagation) 2026-07-06
- [x] Owner verified (chinhphamnhu@gmail.com, sole Super admin).
- [x] Email Routing enabled; destination hi.bervion@gmail.com verified.
- [x] Rule support@ → hi.bervion@gmail.com (Active).
- [x] Rule security@ → hi.bervion@gmail.com (Active).
- [x] Catch-all giữ nguyên (Drop, Disabled) — không đụng.
- [~] DNS Syncing: authoritative NS chưa hiện MX/SPF lúc 12:50 (dig @alexis.ns.cloudflare.com trống). Cloudflare tự thêm route*.mx.cloudflare.net + SPF khi sync xong.
- Acceptance test (sau khi sync): gửi từ Gmail **và** Outlook → support@ + security@; xác nhận nhận ở hi.bervion@gmail.com + xem headers (Received-SPF pass). Rollback = xóa 2 rule + destination.
- Không publish SPF/DKIM outbound giả (receive-only). DMARC để P4C.

### P0 — Space Hardening
S0 per-persona selection persistence **readiness** (persona chưa tồn tại → key nullable/persona-agnostic trước, đổi key khi P1 ship) · S1 primary Space invariant (chuẩn bị `primarySpaceID` pointer — tạm thời app-level cho tới khi PersonaRecord có ở P1) · S2 scoped search + chip + All Spaces · S3 personaId attachment readiness (sealed FolderSecret) · S4 Unfiled semantics · S5 Shared-with-Me pseudo-space compatibility.

### P1 — Persona Core
`PersonaRecord` first-class (@Model + CK record type mới, sealed payload: displayName/kind/isolationPolicy/primaryProfileItemID/**primarySpaceID**), seed Personal từ default identity hiện tại, migration `isDefaultIdentity` → persona link, persona switcher, invariants ≥1 persona + đúng 1 default. `PersonaKind`: personal/professional/pseudonymous/anonymous/custom. Không sync qua ItemRecord (tránh LWW trap); local-first, hoạt động khi sync OFF.

### P2 — Persona Context + AutoFill
Ranking engine (greenfield trong VaultReader/extension), `PersonaIsolationMode` standard/isolated/strictAnonymous với **hard candidate exclusion** (INV-R03), Create Login context, extension memory tests, QuickType privacy threat-model (per-site alias xuất hiện plaintext trong system index — document chấp nhận).

### P3 — Local Alias Model
EmailAlias entity states **draft / reserved / active** — không tạo địa chỉ trông như hoạt động khi chưa có relay. Persona Alias + Per-site Alias (2 tầng chống correlation). Bind alias↔persona↔login/domain. Feature-flag/dev-only cho active state.

### P4A — Relay Security Foundation
P256 Relay Principal + `RelayPrincipalEscrow` (blueprint ParticipantEscrowService) · principal epoch (D5) · signed commands `LOOX-RELAY-AUTHZ-V1` · per-service App Attest (D9, transcript riêng phủ đủ fields — tránh lặp gap one_time) · code-level rate limits ≥5 dimensions (IP, principal, device key, alias, sender/sender-domain) + hard caps + kill switches (global/principal/alias/sender) · cron trigger enable (cleanup only, INV-R04) · `POST /v1/principal/disable-all` + delete-relay-data in-app (Settings → Private Email → Delete all relay data; alias-level Disable/Delete).

Prerequisite từ BE repo: transcript V2 ordering **D0→D8**: D0 freeze V2 schema (thêm `one_time`) → D1 production encoder → D2 vector generator import encoder thật (fix parity gap 2) → D3 TS vector tests → D4 Swift frozen-vector tests → D5 v1 compat tests → D6 extract framing+verifier primitives (`packages/security-protocol/`, Tier1 pure + Tier2 D1-parameterized, X.509 path optional sub-export, formalize pnpm workspace) → D7 consumers migrate → D8 shadow→required progression.

### P4B — Email Ingress Beta
`relay.looxpassword.com` (subdomain, không apex) · Email Routing onboarding + DNS-as-code decision · catch-all → `email()` handler worker `workers/loox-relay/` · D1 alias routing (`alias_hash = HMAC(serverKey, alias)` → AEAD(destination)) · receive-only · internal beta hard-capped bởi 200 verified destinations · Workers Paid cho ingress (CPU limits trên Free có thể fail email handler).

### P4C — Production Delivery
Benchmark Path B (Cloudflare Email Sending **Beta** — Workers Paid $5/mo, 3.000 included, $0.35/1k) vs contingency SES/Postmark. Đo: deliverability Gmail/Outlook/Yahoo, bounce/complaint handling, latency, cost/1k, attachments, abuse tooling, beta SLA/GA timeline. Không commit trước benchmark. Trước ship: Privacy Policy + App Privacy label update, retention policy (no body/attachment/subject persistence; metadata tối thiểu: message_id, alias_id, received_at, forward_status, size_bucket, error_code).

### P5 — Shared Space Persona Representation
Chỉ sau Shared Vault Hardening V2 merged + space membership model tồn tại + Persona core stable. Nghiên cứu Cloudflare-native reply cũng nằm đây trở đi.

## Dashboard checklist (D1 — VERIFIED 2026-07-06)

```
Zone owner:        [x] chinhphamnhu@gmail.com — sole member, Super admin, Active ✅
Email Routing:     [x] Enabled (status Syncing, DNS records Enabled) — 0 rules, 0 destinations
Workers plan:      [x] FREE ($0)
Email Sending:     [!] Paid-only — KHÔNG bật được trên Free (chỉ hiện "Purchase Workers Paid")
D1:                [x] Available on Free (5GB, 5M row-reads/day) — đủ cho P4B alias DB beta scale
Free-tier limits:  cron ≤5 · rate-limit binding min 10s window (ảnh hưởng P4A — xem note)
```

**Hệ quả đổi giả định:**
- **P4C bắt buộc Workers Paid ($5/mo)** để chạy Cloudflare Email Sending Beta (arbitrary recipients). Path A (`forward()` → verified destinations) vẫn Free. → Quyết định upgrade rời tới ngay trước P4C, không sớm hơn. P0–P4B chạy trọn trên Free.
- **P4A rate limiting**: Free-tier rate-limit binding min window 10s → không đủ granularity cho vài dimension. Mitigation: dùng D1 counter rows (atomic UPDATE, như challenge store) cho per-principal/per-alias caps thay vì chỉ rate-limit binding; hoặc upgrade Paid nếu cần. Không đổi INV-R04 (cron vẫn không enforce; hot path D1 counter enforce).
- **Cron ≤5 trên Free**: P4B/P4A cleanup cron nằm trong hạn mức (1 cron đủ). OK.

## Execution notes từ dev team (không đổi decision, chỉ lưu ý implement)

1. **D4 offline-block Erase Vault** đổi semantics flow Erase hiện tại (đang offline-capable). Block chỉ áp khi `active relay aliases > 0` — user chưa từng bật relay không được phép bị chặn erase. Cần UX copy EN+VI.
2. **D6 scoped search** là behavior change trên UX đã ship nội bộ — cần localize chip + empty-state "No results in <Space>. Search all Spaces?" (escape hatch trong 1 tap, vẫn tôn trọng INV-R03 khi strictAnonymous).
3. **D7/D12 ordering**: P0 chạy trước khi Persona tồn tại → S0/S1 build dạng persona-ready (nullable personaID key), P1 rebind. Đã phản ánh trong P0 scope.
4. **D2 principalID**: dùng SHA256 fingerprint over X9.63 canonical pubkey — encode qua `CanonicalWriter` sẵn có để khỏi tự chế framing.
5. Branch hiện tại: shared-vault-hardening-V2 chưa merge — P0 code không conflict, nhưng mọi phase plan phải re-check sau merge.

## MAIL-0 destinations (LOCKED 2026-07-06)

- support@looxpassword.com → **hi.bervion@gmail.com** (interim, owner-controlled)
- security@looxpassword.com → **hi.bervion@gmail.com**
- Cloudflare gửi 1 email verify tới hi.bervion@gmail.com → user bấm link 1 lần → dùng cho cả 2 rule.
- Rollback = xóa 2 routing rule + destination (không có mail flow production nào tồn tại trước đó — zero risk). Không cần formal zone export; ghi lại state hiện tại (Routing on, 0 rule, 0 dest) là đủ làm mốc revert.
- Workers Paid: **defer tới ngay trước P4C** (P0–P4B chạy trọn trên Free).

## Unresolved

Không còn — tất cả input để khởi động MAIL-0 + P0 đã đủ.
