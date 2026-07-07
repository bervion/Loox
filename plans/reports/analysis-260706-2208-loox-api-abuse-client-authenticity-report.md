# Phân tích proposal: Loox API Abuse Resistance & Client Authenticity (App Team)

**Ngày:** 2026-07-06
**Nguồn:** `~/Downloads/loox-api-abuse-resistance-client-authenticity-app-team.md`
**Loại:** Đối chiếu proposal (do backend team viết) với hiện trạng code iOS client.
**Phương pháp:** 3 scout song song — (1) Loox Link networking, (2) Relay/App Attest, (3) TLS/ATS/secrets. Mọi kết luận dưới đây có citation `file:line`.

---

## 1. Bản chất tài liệu

Đây **không phải plan để implement** — là **spec kiểm chứng** do backend team đưa xuống, yêu cầu app team trả lời 16 câu (§32) trước khi backend "đóng băng" enforcement. Câu hỏi trung tâm (§35):

> Một người hiểu public protocol có thể viết custom client hợp lệ và tiêu tài nguyên backend mà KHÔNG phải là instance Loox app được cấp phép hay không?

Tài liệu tách bạch đúng: transport ≠ client authenticity ≠ principal authorization ≠ replay ≠ abuse. Mental model (§3) và invariants (§4) đều hợp lý, không mâu thuẫn với kiến trúc hiện có.

**Điểm mấu chốt:** Phần lớn thứ proposal yêu cầu app team "làm/kiểm chứng" thì **đã build sẵn** (P4A relay crypto, transcript parity, escrow, capability degradation, error taxonomy). Việc còn lại chủ yếu nằm ở **backend (P4B)** + vài gap client nhỏ.

---

## 2. Đối chiếu hiện trạng (điều đã có vs. còn thiếu)

### ✅ Đã có sẵn (không cần làm mới)

| Hạng mục proposal | Hiện trạng | Vị trí |
|---|---|---|
| Relay Principal (P256, principal_id, epoch, nonce, kinds 1–6) | Đủ, client-side P4A done | `VaultifyCore/Relay/RelayCommand.swift:6-13`, `RelayPrincipalIdentity.swift:39-68` |
| Canonical command transcript | `LOOX-RELAY-AUTHZ-V1` (không phải "COMMAND-V1" như proposal đoán) | `RelayCommandCanonical.swift:11` |
| Vector byte-parity test | 6 vector frozen + tamper/domain-sep test | `VaultifyTests/RelayCommandCanonicalTests.swift:33-44`, `Fixtures/relay-authz-command-vectors-v1.json` |
| App Attest cho Loox Link create-share | Real `DCAppAttestService`, fail-closed, 1 retry | `LooxLinkAttestation.swift:19,49,61,81` |
| Retry không tái dùng nonce/challenge/signature | Đúng — mỗi lần fetch challenge single-use mới | `LooxLinkAPIClient.swift:144-170`, `RelayRetryPolicy.swift:9-22` |
| Error taxonomy + capability degradation độc lập | Per-capability circuit breaker, vault không ảnh hưởng | `LooxLinkService.swift:12-14,69-71,116-127` |
| Key escrow qua Vault Key + CloudKit | Relay principal sealed AES-256-GCM, escrow singleton | `RelayPrincipalEscrowService.swift:26-55` |
| Không hardcode secret | Không có API key/bearer/HMAC nhúng | (audit toàn repo) |
| ATS mặc định, không exception | Zero `NSAppTransportSecurity` | `Project.swift:47,168` |
| Extension local-first | Không có network mutation trong AutoFill | `VaultifyAutoFill/AutoFillView.swift:204` |

### ⚠️ Gap thật sự cần xử lý

1. **[P0] Relay App Attest CHƯA wire** — đây chính là mối lo "arbitrary genesis" (§6, ATTACK-R01). Hiện relay chỉ auth bằng principal signature; chữ ký chỉ chứng minh "requester sở hữu key nó vừa tạo", KHÔNG chứng minh "là Loox app instance". App Attest cho relay bị hoãn sang **P4B (backend)**. Xem `RelayAPIClient.swift:4-6`, `RelayCommandCanonical.swift:8-9` (INV-R02).

2. **[P0] `one_time` không nằm trong transcript V1 của Loox Link** — đúng ATTACK-S02 / §22. Cờ burn-after-read gửi ngoài phần được ký/assert (`LooxLinkAPIClient.swift:103-105`); layout V1 không có field này (`LooxLinkCanonical.swift:22-41`); code tự ghi chú "V2 must bind it". → Attacker lật `one_time true→false` mà không phá vỡ assertion.

3. **[P1] `X-Loox-App-Token` extractable từ IPA** — token chống-abuse dùng chung, ship trong Release Info.plist (`Project.swift:66`, `LooxLinkConfig.swift:41-57`). Đã biết & rotatable, là interim cho tới khi App Attest bật `required`. Đúng INV-API-02 (phải coi là public).

4. **[P2] Không có certificate/SPKI pinning** — mọi request qua `URLSession.shared`, không custom trust delegate. Proposal xếp P2 (defense-in-depth), nên chấp nhận được — nhưng cần **quyết định có chủ đích** (§18).

5. **[Cần làm rõ] Vector parity mới một chiều** — Swift đã test byte-for-byte với JSON frozen, nhưng backend encoder P4B chưa tồn tại nên chưa chứng minh được parity thật giữa 2 phía (§23 yêu cầu backend import production encoder, sinh vector). Hiện note ghi "P4B worker MUST reproduce byte-for-byte".

6. **[Nhỏ] App Attest state chỉ là boolean** — proposal §13 đề xuất enum 7 trạng thái; hiện dùng `isSupported` bool + cờ registered trong Keychain, không có nhánh simulator/TestFlight tường minh (`LooxLinkAttestation.swift:19`).

---

## 3. Trả lời 16 câu hỏi báo-cáo-ngược (§32)

| # | Câu hỏi | Trả lời theo code |
|---|---|---|
| 1 | Arbitrary P256 genesis có trả 201 khi không có Loox app? | Client dựng được request y hệt (self-gen P256, ký `LOOX-RELAY-AUTHZ-V1`); relay **không có** app-instance admission. **Lưu ý naming (tránh nhầm):** Relay/Private Email **data plane backend = đã deploy & chạy thật** (createAlias/mint/provisioning, G1–G6 merged, INV-PE02); thứ CHƯA có là **Relay App Attest admission** (nhánh "P4B" chỉ riêng lớp admission này, không phải toàn bộ relay backend). Vì admission chưa tồn tại, custom script có thể tạo request giống hệt và được nhận nếu chỉ dựa self-signature. `RelayService.swift:178-234`, `RelayCommandCanonical.swift:8-9` (INV-R02) |
| 2 | Relay command nào đang dùng App Attest? | **Không cái nào.** Hoãn P4B. `RelayAPIClient.swift:4-6` |
| 3 | Share Link mutation nào dùng App Attest? | `create` (assertion) + `register`; **revoke không** (chỉ revoke-token). `LooxLinkAPIClient.swift:81-125` |
| 4 | Rollout mode hiện tại? | Loox Link = **shadow** (`attestationEnabled=true, attestationRequired=false`, `LooxLinkConfig.swift:23,31`); Relay = **off** (chưa có attest) |
| 5 | Còn static token trong production? | Có — `X-Loox-App-Token`, extractable, rotatable, không per-user. `LooxLinkConfig.swift:41-57` |
| 6 | Principal + App Attest cùng bind một command hash? | Relay: N/A (chưa có attest). Loox Link: **không có principal signature**, chỉ có assertion bind transcript (ciphertext-hash + params). Hai feature tách biệt. `LooxLinkCanonical.swift:22-53` |
| 7 | Mọi retry sinh nonce/timestamp/signature mới? | **Có.** Loox fetch challenge mới mỗi lần; Relay rebuild trên nonce_replay, refresh trên epoch_stale. `RelayRetryPolicy.swift:9-22` |
| 8 | Extension chạy được App Attest? | **Không** — extension không gọi network relay/loox, local-first. `AutoFillView.swift:204` |
| 9 | Có ATS exception? | **Không.** ATS mặc định full. `Project.swift:47,168` |
| 10 | Có cert pinning? | **Không.** `URLSession.shared`, OS-default trust |
| 11 | Field nào thiếu trong transcript? | **`one_time`** thiếu trong Loox V1 asserted transcript. `LooxLinkCanonical.swift:22-41` |
| 12 | Vector generator import production encoder? | Swift có frozen vectors + byte-parity test. Relay data plane đã verify principal signature ở prod nên **ngầm** phải tái tạo canonical bytes đúng; nhưng contract App Attest admission (P4B) chưa có → parity 2-phía cho lớp admission chưa chốt bằng vector chung. Cần backend import production encoder & sinh vector khi thêm assertion. `Fixtures/relay-authz-command-vectors-v1.json` |
| 13 | Sau khi mất App Attest key? | `resetKey()` + re-register, 1 retry trên `DCError.invalidKey`. `LooxLinkAttestation.swift:30-36,86-89` |
| 14 | Relay Principal recovery máy mới? | Escrow qua Vault Key + CloudKit, `refreshFromCloud` cho epoch_stale. `RelayPrincipalEscrowService.swift:64` |
| 15 | Feature nào hỏng khi API outage toàn phần? | Loox Link + Private Email degrade **độc lập** qua circuit breaker riêng; vault bình thường. `LooxLinkService.swift:12-14` |
| 16 | Core Vault dùng được khi Cloudflare down toàn bộ? | **Có** — offline/zero-backend theo thiết kế |

---

## 4. Đánh giá red-team (§30) theo hiện trạng

- **ATTACK-R01 (arbitrary genesis):** Hiện **KHÔNG chặn** ở client (không có relay App Attest). Kết quả tùy backend P4B. Đây là rủi ro P0 số 1.
- **ATTACK-R02 (nhiều principal):** Rào chắn client-auth hiện = 0 cho relay. Cần backend abuse budget + App Attest.
- **ATTACK-R03 (replay):** Client contract **thiết kế đúng** (mỗi lần sinh nonce/challenge single-use mới, không tái dùng) — nhưng client sinh nonce mới KHÔNG tự chặn replay. Enforcement cuối cùng phải chứng minh **server-side cho từng service**: Loox Link đã có challenge atomic + `sign_count` CAS; Relay cần backend verify nonce uniqueness scope + TTL + atomic-consume + race behavior. Không kết luận "replay solved" chỉ từ client.
- **ATTACK-R04 (field mutation):** Chặn — transcript length-prefixed BE bao trùm field, sai hash → sai signature/assertion.
- **ATTACK-R05 (mix-and-match A/B):** Với Loox Link: assertion bind command hash cụ thể → an toàn. Với Relay: chưa có 2 lớp nên không áp dụng.
- **ATTACK-S01 (Share Link custom client):** Ở shadow mode, custom client **vẫn tạo được** share nếu có `X-Loox-App-Token` (extractable). Chỉ khi bật `attestationRequired` mới chặn.
- **ATTACK-S02 (`one_time` omission):** **Gap còn tồn tại** — cần transcript V2.
- **ATTACK-TLS01 (debug proxy):** ATS default; không pinning nên proxy CA tin cậy vẫn xem được — chấp nhận theo threat model (§19).

---

## 5. Khuyến nghị hành động (ưu tiên)

1. **Bật đường đi App Attest cho Relay (P4B ghép với backend)** — nút thắt quyết định câu hỏi trung tâm §35. Trước đó, mọi genesis relay đều không có app-instance admission.
2. **Transcript V2 cho Loox Link bind `one_time`** (+ vector mới, mutation test). Gap rõ ràng, chi phí thấp.
3. **Lịch cutover `X-Loox-App-Token` shadow → required**, sau đó rút token khỏi bundle. Ghi rõ epic C7.
4. **Chốt parity 2-phía P4B:** backend import production encoder, sinh vector, iOS load & assert (đảo chiều so với hiện tại chỉ Swift-side).
5. **Quyết định pinning có chủ đích** (P2) — nếu pin thì SPKI + backup pin + rotation plan; fail chỉ tắt capability liên quan, vault vẫn chạy (INV-API-10).
6. *(tùy chọn)* Nâng App Attest state từ boolean → enum như §13 nếu cần phân biệt simulator/TestFlight/degraded cho UX.

---

## 6. Câu hỏi chưa giải đáp (cần user/backend xác nhận)

1. **Backend P4B relay App Attest** có đang được lên lịch/đóng contract chưa? Client đã sẵn sàng nhận (headers deferred sẵn) nhưng chưa gửi.
2. **Transcript V2 (`one_time` binding)** đã được track ở plan nào chưa? (Code chỉ ghi chú "V2 must", chưa thấy plan cụ thể.)
3. `X-Loox-App-Token` ship trong Release IPA có được chấp nhận như rủi ro tạm thời tới khi App Attest bật `required` không?
4. Không có cert/SPKI pinning: chấp nhận (chỉ ATS default) hay đưa vào roadmap P2?
5. Proposal đặt tên transcript "LOOX-RELAY-COMMAND-V1" — thực tế là `LOOX-RELAY-AUTHZ-V1`. Cần đồng bộ tên trong contract backend để tránh lệch.

---

## 7. Verdict & quyết định đã chốt (user, 2026-07-06)

App team đã **hoàn thành đúng nhiệm vụ audit**; đủ dữ liệu viết proposal backend, **không cần thêm vòng nghiên cứu app tổng quát**. Audit xác nhận nỗi lo ban đầu có cơ sở: *một protocol chữ ký rất chuẩn vẫn bị abuse nếu attacker được phép tự tạo identity rồi tự ký* → đây là lý do Relay Principal và App Attest **phải tồn tại song song**.

### Thứ tự ưu tiên thực tế (locked)

```
P0-1  Loox Link transcript V2 bind one_time
P0-2  Relay App Attest admission
P0-3  Backend abuse budgets (multi-dimensional)
P1    shadow → required rollout
P1    remove interim static token
P2    optional pinning spike (DEFERRED, intentional)
```

### 5 câu mở — quyết định cuối

| Câu | Quyết định |
|---|---|
| Backend Relay App Attest contract? | **Chưa có → P0, phải làm.** |
| Transcript V2 `one_time`? | **Epic riêng, làm NGAY, trước khi bật required. Tuyệt đối không required-trước-V2-sau.** |
| Static `X-Loox-App-Token`? | **Chấp nhận có thời hạn như transitional throttle, KHÔNG phải secret/auth durable.** Ghi rõ "public-to-determined-attacker". |
| Pinning? | **Defer P2.** ATS default là quyết định có chủ đích hiện tại (Cloudflare TLS làm pin lifecycle phức tạp). Spike SPKI riêng sau P0/P1. |
| Transcript naming? | **Giữ nguyên `LOOX-RELAY-AUTHZ-V1`, KHÔNG rename.** Thêm transcript mới riêng `LOOX-RELAY-ASSERTION-V1` khi làm App Attest. |

### Invariant admission cần backend đóng

```
INV-ADM-01
Một Relay Principal chưa biết KHÔNG được nhận chỉ nhờ
self-consistent public key + signature.

Genesis:  Unknown Principal → valid principal sig? → valid App Attest admission? → REGISTER (else REJECT)
```

**Nuance quan trọng:** App Attest KHÔNG chỉ ở genesis. Nếu chỉ attest lần create đầu, attacker lấy 1 principal đã admit rồi automate 1000 createAlias. → Mọi mutation tốn tài nguyên / security-sensitive (`createAlias`, `rotateDestination`, `rotatePrincipal`, `disableAll`, tối thiểu) phải kèm **principal signature + App Attest assertion cùng bind một command hash**. `disableAlias`/`deleteAlias` có thể debate nhưng nghiêng protect-tất-cả cho contract nhất quán.

### 4 workstream backend proposal (locked structure)

- **B0 — Loox Link Transcript V2** (P0 độc lập, nhỏ, làm trước): thêm `one_time` + mọi field security-relevant vào canonical → version bump → production TS encoder → generator import real encoder → frozen vectors → Swift parity → tamper tests → V1 compatibility strategy. Thứ tự bắt buộc: freeze field list → encoder → vectors → parity → mutation test → shadow → required.
- **B1 — Relay App Attest Admission**: challenge endpoint, registration flow, attestation key store, assertion verification, commandHash binding, genesis required, mutation policy. **App Attest transcript MUST bind exact Relay commandHash.** Transcript mới `LOOX-RELAY-ASSERTION-V1` = `MAGIC ‖ method ‖ normalizedPath ‖ challengeID ‖ SHA256(canonicalRelayCommandBytes)`. Hai lớp (P256 principal sig + App Attest assertion) cùng bind một command.
- **B2 — Multi-dimensional Abuse Budgets** (không chỉ IP): Private Email = per IP / per App Attest key / per Relay Principal / **per destination HMAC** / per operation / global. Share Link = per IP / per App Attest key / per create velocity / per ciphertext bytes / per active links. Destination-level: `destination_rate_key = HMAC(serverRateKey, normalize(destination))` — chặn ATTACK-R02 (nhiều principal cùng forward về 1 victim) mà không cần plaintext analytics.
- **B3 — Required-mode Cutover**: Loox Link `shadow → required → remove interim token`; Relay `off → shadow → required`. Có metrics + rollback. Token cutover 4 stage: (A) token required + attest shadow → (B) token required + attest required [overlap giảm rollback risk] → (C) attest required + token ignored server-side → (D) remove token khỏi build mới.

### Genesis flow chốt (client → backend order)

Client: tạo/recover principal → fetch attest challenge → build genesis createAlias command → canonical bytes → (principal signs) + (commandHash → build `LOOX-RELAY-ASSERTION-V1` → `generateAssertion`) → POST.
Backend verify (order optimize được, semantics tương đương): challenge valid+unused → assertion valid → appIdHash valid → sign_count CAS → commandHash khớp body → principal sig valid → genesis rules cho unknown principal → abuse budgets → register principal atomically → create alias.

### Điểm KHÔNG coi là bug (tránh scope creep)

- **Share Link revoke không App Attest**: nếu revoke token là high-entropy bearer capability thì "possession = authority to revoke" hợp lý. Audit riêng entropy/scope/storage/one-link-only/rotation/leak — chưa bắt App Attest chỉ vì "mọi mutation phải giống nhau".
- **AutoFill extension local-first**: không kéo App Attest Relay vào extension ở epic này. Chỉ mở feasibility riêng nếu sau này cho "Create Private Email inside extension".

### App Attest state enum (P1, không blocker)

Boolean `isSupported` + registered-flag đủ cho basic flow; khi shadow→required + tích hợp capability UX cần enum tối giản (không cần 7 case):
```swift
enum AppAttestState: Equatable {
    case unsupported, needsRegistration, registered, temporarilyUnavailable, needsRepair
}
```

### Việc còn lại của app team

Không cần implement thêm trước khi viết backend proposal, **ngoại trừ** có thể tạo ticket nhỏ cho App Attest state enum (P1). Hai P0 client-side thực thi cùng backend: B0 (transcript V2 — cần Swift parity) và B1 (client genesis/assertion flow khi backend contract sẵn sàng).
