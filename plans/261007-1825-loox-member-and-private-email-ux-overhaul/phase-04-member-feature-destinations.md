---
phase: 4
title: "Member Feature Destinations"
status: in-progress
priority: P1
effort: "2d"
dependencies: [1]
---

# Phase 4: Member Feature Destinations

## Overview

Mỗi tile Member mở màn có nội dung/action đúng tính năng. Share Links/Send to Browser đang mở Notifications; Family đã có root/person detail, cần sửa discovery/share scope/state, không xây family billing/roster mới.

## Implementation status (2026-10-07)

Named destinations, purpose/primary/empty states, persona ownership projections, truthful metadata-only histories and unchanged rollout/commerce gates passed source/unit/UI review. Family person-detail/pending ceremonies still require two-account and populated-state receipts. Full visual/accessibility matrix remains pending.

Source/synthetic checks and remaining external gates: [implementation progress](./reports/implementation-progress.md). A checked item records native source/executable acceptance only; physical and complete matrix gates stay separate and unchecked.

## Requirements

- Share Links có dedicated create/list/revoke root, reuse QuickLinkView field/expiry/encryption flow.
- Browser có dedicated root item→QR/code chooser→approval và bounded local attempts history.
- Family làm rõ người theo outgoing shares, pending/active; chọn một item hoặc Space, giữ existing person detail.
- Active persona scope rõ; count/list/chooser/history cùng ownership policy, quota commerce vẫn vault-wide có nhãn.
- Không persist fragment content key, historical working-link recopy, fake server consumed/unread state.
- Không promise expired archive nếu store drop expired; V1 chỉ quản lý local records còn thời hạn.
- Browser signed exposure/cohort/capability và commerce launch flags giữ nguyên; không mở GA vì thêm entry.
- Approval Mode độc lập iCloudSyncEnabled; iCloud account/readiness có cause+next step đúng, operator outage không upsell.

## Architecture

### Share Links flow

1. Active persona + ownership projection → eligible item chooser → QuickLinkView → encrypted snapshot API → completion transient URL key fragment.
2. Local itemId/revokeToken/expiresAt metadata → scoped list → manage/item/revoke → server 204/404 → local cleanup; network fail giữ token/row cho retry.
3. Key không persisted tại [LooxLinkRecordStore:7](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/LooxLink/LooxLinkRecordStore.swift:7); expired drop on load tại [store:68](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/LooxLink/LooxLinkRecordStore.swift:68).
4. List “còn thời hạn” mô tả clock, không proof chưa mở. Historical row không Copy working URL; user tạo link mới nếu cần chia sẻ lại.
5. Record item bị xóa/orphan giữ revoke credential cleanup, không gán active persona theo suy đoán hoặc lộ title profile khác.

### Browser flow

1. Signed exposure/cohort + create capability → eligible scoped item → existing chooser scan/code → signed session → field approval/SAS/Face ID → encrypted transfer.
2. History chỉ itemID/timestamp/result tại [QuickViewHistoryStore:10](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/QuickView/QuickViewHistoryStore.swift:10); no code/token/SAS/field-value replay.
3. Entry gate parity với [ItemDetail:137](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemDetail/ItemDetailScreen.swift:137), không infer AppStore availability từ TF.
4. Completed/cancelled/failed chỉ local attempt outcome, không remote recipient activity hoặc live session monitor.

### Family flow

1. Owned item shares → group recipientLabel local → person summary → existing observed person detail → active management hoặc unfinished resume.
2. Family hiện group shares tại [FamilyScreen:24](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Profile/FamilyScreen.swift:24), detail live projection tại [FamilyScreen:145](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Profile/FamilyScreen.swift:145).
3. CTA `Chia sẻ với người thân` → chọn một mục/Space → existing ceremony/transport. Không invented family roster trước khi có share, role/billing quyền hạn hay contact upload.
4. Pending/accepted/ceremony/active khác nhau; refresher đúng source, không gộp waiting với đã cấp quyền.
5. Single-item route có explicit approval-only entry vào ShareAccessSheet, chạy prerequisites rồi existing Loox-user/ceremony flow; default generic chooser giữ nguyên cho nơi khác. Không mở Quick Link từ CTA Family, không truyền resumeEmail giả để skip chooser. Quick Link không tạo share-derived Family relationship.

### Scope/lifetime contract

- Owned items lấy từ canonical [items(for:):20](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+PersonaPartition.swift:20); chỉ folderId nil thuộc default. Non-nil missing folder unknown, loại khỏi count/list/chooser/action; không fallback default bằng personaID helper hiện có hoặc all items khi primarySpace nil.
- Pure proposed `MemberFeatureProjection` dùng repository/store input hiện tại, không giữ stale persona snapshot qua navigation.
- Device-local stores chưa personaID: filter qua item ownership; orphan chưa chứng minh owner không show trong persona list/count. Credential erase cleanup giữ nguyên.
- Item đã move persona thay visibility theo current ownership; legacy orphan archive không silently gán persona hiện tại. Full archive/owner metadata migration ngoài scope, phải có quyết định riêng.
- Revalidate active persona/item eligibility trước create/share/revoke sau picker; không reuse zone/share từ persona khác.

## Related Code Files

**Owner Member UI:** phase 4 riêng; không Personas/Relay/email repositories. Shared components/catalog do Integration serialize.

- Modify: [LooxHubScreen.swift:231](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Profile/LooxHubScreen.swift:231) — feature roots/metrics/scope, adaptive grid/status text.
- Modify if needed: [LooxFeatureTile.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Profile/LooxFeatureTile.swift) — multiline metric/status, adaptive size bằng existing tokens.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/ShareLinksScreen.swift` — proposed local create/manage root.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/QuickView/SendToBrowserScreen.swift` — proposed item/entry/history root.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/MemberFeatureProjection.swift` — proposed scoped eligibility/count/list helper, no secret persistence.
- Modify: [FamilyScreen.swift:30](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Profile/FamilyScreen.swift:30) — scope/entry/empty/state và existing person detail.
- Review/reuse: [QuickLinkView.swift:7](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/QuickLinkView.swift:7), [LooxLinkService.swift:186](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/LooxLink/LooxLinkService.swift:186) — snapshot/revoke, no duplicate cryptography.
- Review/reuse: [SettingsScreen.swift:55](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Settings/SettingsScreen.swift:55) — existing vault-wide orphan-link safety cleanup; không invent persona ownership/archive cho orphan.
- Review/reuse: [QuickViewEntryChooserSheet.swift:6](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/QuickView/QuickViewEntryChooserSheet.swift:6), [ExposureProvider:43](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/QuickView/QuickViewExposureProvider.swift:43) — gated existing scanner/code/approval.
- Review/reuse: [ShareRecipientDetailSheet.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/ShareRecipientDetailSheet.swift), [ShareSpaceSheet.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/ShareSpaceSheet.swift), [ShareResumeStepperSheet.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/ShareResumeStepperSheet.swift) — established scopes/management.
- Modify: [ShareAccessSheet.swift:35](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/ShareAccessSheet.swift:35), [chooser:463](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/ShareAccessSheet.swift:463) — explicit approval-only Family entry, default generic flow backward compatible; inventory actual callers before changing initializer.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/MemberFeatureProjectionTests.swift` — proposed scope/gate/metadata tests.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyUITests/PrivateEmailMemberUXUITests.swift` — proposed route/workflow tests.

## Implementation Steps

1. Lock purpose/state/action/ownership từng root theo Gate D/design spec, nêu device-local limitation bằng copy ngắn.
2. Add pure projection; count/list/picker/history cùng scope, quota giữ vault-wide semantics và launch flags.
3. Hub tiles route đúng root; back về Member, no notification detour/nested tab stack; 2 columns→1 ở AX.
4. Links root one create primary, active local list, expiry/device-only explanation; menu revoke confirmation.
5. Item chooser reuse QuickLinkView; không duplicate field selection/encryption/API/expiry.
6. Historical records không Copy working link; không persist key để làm Copy, không giả consumed/unread status.
7. Browser root one primary, supported viewer/scan/code instructions, scoped bounded attempts; compose chooser/approval.
8. Exposure/capability trước entry/create; no eligible fields/extra-protected có reason, no silent disabled button.
9. Family refine people/empty; share chooser một item/Space, item approval-only explicit entry/prerequisites, no Quick Link detour; person active/resume routes reused.
10. iCloud account/Approval Mode readiness reasons riêng; không gate vault sync hoặc upsell operator outage.
11. Integration EN/VI/JA cùng mỗi UI PR; theme/long-copy/accessibility review, correct action rank/haptic ownership.
12. Validate back/dismiss/cancel/result, persona change lúc picker/in-flight, record deleted khi detail mở.

## Test Matrix

| Lớp | Ca | Kỳ vọng |
| --- | --- | --- |
| Projection unit | personal/work/anonymous, nil primarySpace, missing-folder, moved/deleted/orphan item | Unknown folder fail closed; no cross-profile title/count/list/chooser |
| Links integration | create/shorten, expiry cleanup, revoke 204/404/offline | Auth reused, failed revoke giữ token, no historical key |
| Browser gate | disabled/beta/GA × Debug/TF/AppStore × shadow/required | Existing signed/cohort policy parity, không widening |
| Browser UI | choose→QR/code→fields approve→result, cancel/extra protection/error | Explicit action, không replay history/plaintext |
| Family integration | item approval-only→pending→accepted→ceremony→active→revoke, Space | No Quick Link chooser/resumeEmail fake; live observed Family relationship, true permissions |
| Live E2E | hai iCloud accounts/devices, approval on/sync off | Transport share/update/revoke hoạt động đúng |
| DNA snapshot | roots empty/content/offline, long VI/name/item/metrics | 375/430, XL/AX XXL light/dark, VO order tốt |

## Success Criteria

- [x] Links/Browser tile mở named feature root, không Notifications.
- [x] Feature root có purpose/primary/empty next step rõ; Family share item/Space discoverable.
- [x] Counts/list/chooser active persona nhất quán, no cross-profile leak/orphan reassignment.
- [x] No historical working recopy, fake consumed state hoặc full expired archive promise.
- [x] Browser rollout/commerce gates nguyên, operator outage không upsell.
- [ ] Existing person detail và pending resume đúng, no invented roster/billing roles.
- [ ] EN/VI/JA/token/motion/haptic/VO screen matrix pass.

## Risk Assessment

| Rủi ro | Khả năng × tác động | Mitigation |
| --- | --- | --- |
| New list/history leak persona | Cao × cao | Same ownership projection/revalidation, orphan fail closed |
| Persist URL key for recopy | Trung bình × rất cao | Transient result only, codec/privacy tests |
| New entry widening Browser | Trung bình × cao | Same signed resolver, cohort matrix |
| Family tưởng roster/billing | Cao × trung bình | Share-derived people copy, item/Space scope explicit |

## Compatibility and Rollback

- Added roots/projection không đổi link/history/store codecs; metadata retention/privacy đúng existing contract.
- Revert tile routes/hide root độc lập, không auto revoke links/shares đã dùng.
- Revoke token/erase cleanup giữ nguyên; không delete metadata chỉ để UI empty.

## Decisions and Dependencies

- Depends Gate D phase 1; song song phase 2/3 theo file ownership.
- Live Family acceptance cần hai iCloud accounts/devices, Approval Mode readiness; không phụ thuộc bật vault sync.
- Full orphan archive/cross-device history/family roster cần migration/backend contract riêng, ngoài scope.
