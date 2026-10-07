---
phase: 2
title: "Recipient State and Verification"
status: in-progress
priority: P1
effort: "1.5d"
dependencies: [1]
---

# Phase 2: Recipient State and Verification

## Overview

Xác minh email ngoài app phải cập nhật khi quay lại đúng luồng đang mở. Sửa source of truth/race trước UI overhaul: một coordinator reusable, preview đúng recipient và detail disclosure local rõ ràng.

## Implementation status (2026-10-07)

Identity CAS, no-downgrade/no-op, lifecycle/policy cancellation, status-only GET, local recipient disclosure and actual/desired state are source-reviewed and tested. Final new UI covers deliberate reveal/hide. Real browser-confirm return and p95 timing remain physical Debug/TF checks.

Source/synthetic checks and remaining external gates: [implementation progress](./reports/implementation-progress.md). A checked item records native source/executable acceptance only; physical and complete matrix gates stay separate and unchecked.

## Requirements

- Refresh foreground/unlock và khi mở màn liên quan có destination pending; begin-success cũng kích hoạt subscription.
- Poll chỉ foreground/unlocked/opt-in/pending relevant/remote policy cho phép; không loop toàn profile hoặc chạy nền.
- `.read` là local-read luôn mở, không là phép polling mạng. Send/resend vẫn `.mutate` full auth/cooldown.
- Response cũ không verified email mới, destination đổi, inbox bị xóa hoặc vault khác.
- Overview/alias detail masked; dedicated inbox detail mở có chủ đích trong vault unlocked hiển thị full local email và `Ẩn email`.
- Conceal background/lock/exit tức thời; return foreground không tự reveal lại.
- Không UI success giả từ deep-link/browser-return, không auto reset vault/principal.

## Architecture

### Lifetime và triggers

- Proposed `DestinationVerificationCoordinator` owned bởi AppEnvironment, theo app/vault environment; không static singleton.
- Long-lived root tại [AppEnvironment.swift:6](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/AppEnvironment.swift:6), app instance khởi tạo tại [VaultifyApp.swift:33](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/VaultifyApp.swift:33).
- Visible consumers đăng ký scope token (inboxID/aliasID/personaID); unregister disappear, rebind khi identity/persona đổi.
- Foreground/unlock check once pending scope; continuous polling chỉ visible relevant consumers. New pending identity/begin-success wake loop.
- Dedupe key gồm inboxID + email identity + destinationID + generation; một request đang bay/identity.
- Cancel background/lock/off/deleted/change identity; clock/client injection deterministic. Không plaintext email trong static cache/log.

### Data flow và persistence CAS

1. Inbox snapshot local → exact email/destinationID/generation → read-only GET status → validate response identity/status → CAS live row → sealed write → repository observation → UI.
2. Begin-send cũng snapshot email + previous destinationID; chỉ assign new ID nếu live identity còn khớp. Refresh match destinationID của cả request và response.
3. `persistVerification` hiện chỉ lookup ID tại [RelayService:253](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:253); CAS phải nằm ở persistence, không chỉ guard view.
4. Profile email đổi hiện không reset verification tại [ForwardingInboxes:91](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+ForwardingInboxes.swift:91); invalidate destinationID/status rồi yêu cầu consent mới.
5. Preview alias mới dùng `newAliasDestination` tại [repository:64](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+ForwardingInboxes.swift:64). Active alias display actual `forwardingTarget` checkpoint; desired khác actual có drift/progress, không báo routing mới hoàn tất sớm.
6. Begin/resend và GET có ordering chung per identity, không chỉ dedupe GET. Delayed pending response không downgrade verified cùng email/destinationID; generation invalidation + operation revision/CAS live state tại persistence. Test begin pending response về sau GET verified; đổi email/ID là identity mới, không áp monotonic rule xuyên identity.
7. Semantic equality trước persist: pending/verified không đổi là no-op, không reseal, bump updatedAt/dirty, reload vault hoặc post mutation. Checking/last-check/cooldown giữ ephemeral trong coordinator. Existing updateInbox luôn write tại [ForwardingInboxes:127](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+ForwardingInboxes.swift:127), sync debounce tại [SyncCoordinator.swift:75](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Sync/SyncCoordinator.swift:75).

### Remote-read policy

- Local read vẫn available ở mọi state theo [Capability.swift:84](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/Capability.swift:84).
- Proposed `canRefreshDestinationStatus`: user opt-in + active/unlocked + reachability + remote endpoint policy + backoff. Không gọi `.allows(.read)` để quyết định request.
- GET endpoint BE không chạy mutation gate, có IP 60/phút tại [index.ts:117](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/index.ts:117). Remote mode allowlist: active/degraded/maintenance/disabled cho phép bounded pending GET; retired chặn. User-off, signed explicit remote-read disable, offline, inactive/locked vẫn chặn. Local `.read` không bị các network gates che records. 429/Retry-After/backoff là authoritative.
- GET 200 chỉ `noteServiceResponded`, không `noteSuccess`: [CapabilityStore.swift:88](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Capabilities/CapabilityStore.swift:88) reset operator mode active, trong khi [noteServiceResponded:110](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Capabilities/CapabilityStore.swift:110) chỉ ghi reachability. GET thành công không mở create/mutate khi maintenance/disabled.
- Circuit-breaker admission cho remote status phải có terminal outcome đúng một lần. Cancel lifecycle là outcome riêng, release half-open probe theo operation token, không success/operator update hoặc infrastructure failure. Current [Capability.swift:125](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/Capability.swift:125) tiêu thụ half-open; [RelayAPIClient.swift:222](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayAPIClient.swift:222) gom cancel vào transport cần tách. Retry lần foreground không bị probe cũ khóa vĩnh viễn.
- Poll visible pending 8s; lỗi backoff 15→30→60s + bounded jitter ≤20%, success reset 8s. Budget chung app ≤30 GET trong mỗi rolling 60s, ưu tiên inbox đang xem; foreground/manual/begin-success cùng dedupe/budget.
- Honor 429/Retry-After lớn hơn backoff, stop background/lock/user off/no visible pending. Foreground check once chỉ lúc unlocked/relevant; không dùng auto-check để vượt server throttle.
- 404/malformed không biến thành verified, không reset principal; inline retryable error phù hợp. Transient lỗi giữ last known status.

## Related Code Files

**Owner State:** độc quyền phase 2; merge xong mới hand over email views sang phase 3. Integration sở hữu catalog/components.

- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/DestinationVerificationCoordinator.swift` — proposed lifecycle/policy/dedupe.
- Modify: [AppEnvironment.swift:259](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/AppEnvironment.swift:259) — inject beside relay, isolated tests không network.
- Modify: [RootView.swift:174](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/RootView.swift:174) — foreground/unlock/lock lifecycle không block render.
- Modify: [RelayService.swift:235](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:235) — begin/refresh snapshot/CAS.
- Modify if required: [RelayAPIClient.swift:211](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayAPIClient.swift:211) — status response/error/Retry-After, không plaintext endpoint mới.
- Modify: [CapabilityStore.swift:110](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Capabilities/CapabilityStore.swift:110), [Capability.swift:125](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/Capability.swift:125) — named remote-status admission/outcome, cancellation terminal handling; preserve local-read contract và operator mode.
- Modify: [VaultRepository+ForwardingInboxes.swift:85](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+ForwardingInboxes.swift:85) — invalidate verification khi profile email đổi.
- Modify: [ForwardingInboxVerification.swift:65](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/ForwardingInboxVerification.swift:65) — shared coordinator/cooldown/UI outcomes.
- Modify: [ForwardingInboxScreen.swift:75](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/ForwardingInboxScreen.swift:75) — replace loop riêng với visible subscription.
- Modify: [ForwardingInboxDetailScreen.swift:51](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/ForwardingInboxDetailScreen.swift:51) — deliberate local full email/hide and live verification state.
- Modify: [PersonaAliasesScreen.swift:338](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/PersonaAliasesScreen.swift:338) — policy/subscription; phase 3 ownership sau merge.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/DestinationVerificationCoordinatorTests.swift` — proposed deterministic race/lifecycle tests.
- Modify: [ForwardingInboxTests.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/ForwardingInboxTests.swift) — invalidate identity/recipient precedence.

## Callers cần migrate

- Begin: [ForwardingInboxVerification.swift:71](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/ForwardingInboxVerification.swift:71).
- Refresh: [ForwardingInboxVerification.swift:90](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/ForwardingInboxVerification.swift:90), [ForwardingInboxScreen.swift:103](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/ForwardingInboxScreen.swift:103).
- New consumers root/detail bắt đầu phase này; alias detail/editor tích hợp phase 3 theo interface đã khóa.

## Implementation Steps

1. Khóa remote-status mode allowlist/outcome/interface/visible scope đã nêu tại Gate D; inject clock/client trước state mới. Không suy ra permission từ `.read` local.
2. Tests delayed response/email A→B/delete/resend ID mới và cancellation/dedupe.
3. Invalidate local destination identity khi email profile đổi; không giữ verified cho email mới.
4. Add CAS begin/refresh persistence + ordering/no-downgrade per identity; validate response identity/status, semantic equality no-op, retain last known on network lỗi.
5. Implement coordinator/dedupe/budget/backoff và breaker cancel outcome; GET thành công chỉ reachability, không reset operator mode. Status checking/waiting/verified/error có source of truth.
6. Wire foreground/unlock và pending changes; cancel/clear sensitive reveal state ngay lock/background.
7. Replace inbox list loop; subscribe root/detail, không broad poll mọi persona.
8. InboxDetail full email mặc định sau deliberate push trong vault unlocked; selectable/copy local, Hide/Show control, sensitive clipboard policy hiện hữu.
9. Manual check/send/resend khác chức năng; cooldown share giữa root/detail trong cùng environment.
10. Integration cập nhật EN/VI/JA ngay PR; merge trước Email UI, bàn giao interface/tests/file ownership.

## Test Matrix

| Lớp | Ca | Kỳ vọng |
| --- | --- | --- |
| Unit race | A→B lúc response A đang bay, resend ID mới, delete inbox; GET verified rồi delayed begin pending | Không stale write/verified sai identity hoặc downgrade cùng identity |
| Unit lifecycle | root/detail/manual/foreground cùng trigger; pending mới; lock/off | Một request/identity, loop wake/cancel đúng |
| Unit network | nhiều pending, 429/503/404/Retry-After; maintenance/disabled GET 200; cancelled half-open | Budget bounded, operator mode nguyên, cancellation release đúng một lần, không auto resend/reset |
| Unit persistence | unchanged pending/verified nhiều GET | Sealed bytes/updatedAt nguyên, no reload/dirty/sync notification; checking ephemeral |
| Repository | pin/default/profile, email đổi, desired≠actual | Preview đúng, verification invalidated, actual routing không giả |
| Integration | pending→web confirm→verified→sealed reload | UI đổi observed, không restart app |
| Physical | Debug/TF confirm rồi foreground root/detail trong lab network | Target p95 ≤3s foreground, visible update ≤8s; benchmark chưa đo, không SLA Internet |
| Privacy UX | full detail→background→return/lock/exit, VO | Conceal tức thì, no automatic re-reveal |

## Success Criteria

- [ ] Root/detail cập nhật sau xác nhận không force quit; pending mới không bị loop bỏ sót.
- [x] No stale response ghi verified email/destination khác; CAS tests pass.
- [x] No background/locked requests hoặc status poll resend; opt-out tôn trọng.
- [x] Detail nhận diện email local đầy đủ, Hide/Show rõ; overview masked.
- [x] Actual forwarding và desired recipient phân biệt khi rotation pending.
- [x] EN/VI/JA, sensitive clipboard, no email logs/endpoint mới.

## Risk Assessment

| Rủi ro | Khả năng × tác động | Mitigation |
| --- | --- | --- |
| Stale verified sai email | Cao × rất cao | CAS ở persistence + invalidate khi identity đổi |
| State tồn tại qua environment/vault | Trung bình × cao | AppEnvironment owner, cancel/reset scope lock/erase, isolated tests |
| Poll nhiều pending vượt IP limit | Trung bình × cao | Visible scope, process budget, dedupe/backoff |
| Reveal leak snapshot/restoration | Trung bình × cao | Ephemeral display, conceal before inactive/lock, không persist reveal |

## Compatibility and Rollback

- Current sealed inbox identity/status đủ; không endpoint server email plaintext mới.
- Rollback auto loop qua local flag, giữ foreground/manual/CAS fix; không reset vault/principal để làm lại verification.
- Backward old inbox status giữ cho cùng identity; email đổi buộc consent mới đúng security boundary.

## Decisions and Dependencies

- Depends Gate D phase 1; không cần activate loox.pw để sửa verification legacy.
- Browser/deep-link chỉ trigger GET, không là proof verified. Remote-read mode/outcome contract named riêng theo allowlist trên; signed remote-read disable vẫn fail closed.
