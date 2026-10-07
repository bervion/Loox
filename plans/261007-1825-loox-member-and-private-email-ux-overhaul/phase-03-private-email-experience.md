---
phase: 3
title: "Private Email Experience"
status: in-progress
priority: P1
effort: "2.5d–4d, gồm Linked services refinement"
dependencies: [1, 2]
---

# Phase 3: Private Email Experience

## Overview

Đại tu tạo/quản lý email theo DNA Loox: no-Login không dead-end, recipient preview đúng, title/copy ngắn và state đáng tin. Compose coordinator phase 2 và trusted domain resolver phase 1; tận dụng nullable fields có sẵn.

## Implementation status (2026-10-07)

No-Login issuance/checkpoint retry, 1:N canonical associations, atomic unlink/rollback, protected/conflicting recovery, sealed original baseline and namespace preservation passed unit/source review. Final UI proves unlink cancel/confirm preserves the other Login and ordinary credentials. Representative AX3 title/action truncations are repaired; full all-theme/VO/DNA acceptance remains pending.

Source/synthetic checks and remaining external gates: [implementation progress](./reports/implementation-progress.md). A checked item records native source/executable acceptance only; physical and complete matrix gates stay separate and unchecked.

## Requirements

- Title `Tạo email riêng`, CTA `Tạo địa chỉ`; nhóm `Địa chỉ theo dịch vụ` / `Địa chỉ dùng nhiều nơi`.
- Tên gợi nhớ, website và Login đều optional; không ép mỗi alias chỉ dùng cho một website.
- Không Login vẫn tạo được alias; detail có `Dịch vụ liên kết` và `Liên kết mục đăng nhập`, chọn Login có sẵn hoặc tạo mới có alias-ID handoff.
- Global/per-alias service list và unlink theo [linked-services addendum](./linked-services-addendum.md); canonical fields hỗ trợ một alias cho nhiều Login, không tự detect tài khoản provider.
- Website lưu normalized `boundDomain`, label dùng `EmailAlias.label`; không invented storage field.
- Root/status banner có surface/icon/title/body rõ; receive-only notice `Chỉ nhận thư` nhẹ và ở dưới nội dung chính.
- Một filled primary/state; disable có reason, loading giữ geometry, error giữ input/checkpoint và retry.
- Preview dùng exact new recipient resolver; alias active biết actual forwarding, desired change và tiến độ rotation.
- Existing suffix/domain bất biến từ mint checkpoint; domain mất eligibility chỉ được chọn lại trước mint. `backendMinted=true` resume routing trên cùng namespace theo rotate policy, không chạy new-create/reselect hay silently đổi suffix.

## Architecture

### Root/create flow

1. Active persona → actionable readiness nếu cần → scoped addresses → one create CTA → inbox/domain settings → receive-only notice.
2. Editor type `Cho một dịch vụ` / `Dùng nhiều nơi` → optional label/website/Login → trusted domain → resolved recipient + verification state → create.
3. Model optional fields đã có tại [EmailAlias.swift:30](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/EmailAlias.swift:30); `createPerSiteAlias` nhận binding nil tại [AliasManagement:31](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasManagement.swift:31).
4. Reserve local → mint checkpoint → route destination → active result. Failure giữ reserved/minted alias để retry đúng step, không mint địa chỉ khác sau error.
5. Inbox pending chuyển CTA vào verification, draft giữ nguyên; coordinator update → create reenabled. Không auto activate chỉ vì server status vừa đổi.
6. Row subtitle precedence: label → website → `Chưa liên kết`; status riêng một dòng, không dùng màu thay text.

### Link Login handoff

- Existing Login picker scoped true persona ownership, verify lại trước save canonical field. Một alias có thể lưu cho nhiều Login; boundItemId là primary/legacy hint, không silently repoint nó khi liên kết thêm. Một Login V1 chỉ có một canonical private email hợp lệ.
- New Login từ alias detail: EditorTarget/draft carry explicit aliasID, prefill trusted address, set pendingAliasID. Không dựa suggestion matching website để tìm lại alias.
- Context optional aliasID/personaID phải nằm trong sealed `UIStateStore.DraftState`, backward decode; shell restore/remount dựng đúng editor context. Revalidate alias live/owner/trusted address trước save; deleted/conflicting/unknown-domain context có recovery rõ, không tự mint khác. Same alias đã lưu trong Login là idempotent, primary binding ở Login khác không chặn liên kết thêm.
- Bind chỉ sau repository.add/update thành công; current create save order tại [ItemEditor:932](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:932), binding helper tại [ItemEditor:795](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:795).
- Link alias đã active vào Login phải upsert canonical `Private email` qua trusted resolver/writeback, giữ username/email thật; AutoFill đọc field này tại [AutoFillView.swift:223](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyAutoFill/AutoFillView.swift:223). Nếu Login đang có private email khác, V1 block binding và hướng chọn mục khác, không silently replace/unbind địa chỉ đang dùng. Failure giữa bind và field save có recovery/retry, không báo thành công đầy đủ; callback/retry idempotent.
- Cancel/save failure không bind hoặc allocate alias khác; partial binding persistence failure có recovery state/retry, không báo thành công đầy đủ.
- Unbound không website không được suggestion tự động hiện nay; dedicated detail binding giải quyết discoverability.
- Relay lifecycle serialize per alias; sau await re-read live row, validate alias identity/operation revision rồi patch riêng minted checkpoint/forwardingTarget/status. Không ghi whole snapshot cũ làm mất label/binding vừa lưu hoặc resurrect alias bị xóa. Current activation tại [RelayService:88](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:88), rotation tại [RelayService:122](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:122) cần đổi cùng persistence contract, không chỉ guard ở view.
- Unlink exact canonical field + matching primary pointer trong một repository transaction/save; writeback/late relay/editor save revalidate relation generation để không reattach. Protected/duplicate fields block mutation và hướng mở Login/repair; không blind upsert helper đầu tiên. Legacy ordinary Email/username chỉ xuất hiện trong explicit review/migration, không authoritative list/count và không auto convert/delete.

### Recipient/scope/motion

- Editor đang preview profile email tại [AliasEditor:46](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:46), repository default ưu tiên vault-wide explicit inbox tại [ForwardingInboxes:49](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+ForwardingInboxes.swift:49); thống nhất resolver.
- Login picker hiện fallback all logins khi primarySpace nil tại [AliasEditor:17](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:17); dùng canonical [items(for:):20](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+PersonaPartition.swift:20), không helper personaID hiện có khi folder chưa resolve. Non-nil missing folder là unknown, loại khỏi chooser và revalidate live ownership trước bind.
- Alias detail mask actual checkpoint, có labeled local reveal/route đúng inbox detail; desired≠actual hiển thị update progress, không đổi label như đã route xong.
- Native inline sheet header; visible status transition Motion tokens, Reduce Motion instant. ClipboardService owns success haptic, navigation/scroll silent.

## Related Code Files

**Owner Email UI:** phase 3 sau Domain/State merge. Phase 4 không sửa file này. Integration sở hữu shared catalog/component.

- Modify: [PersonaAliasesScreen.swift:25](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/PersonaAliasesScreen.swift:25) — hierarchy/notice/subtitle/one CTA/scope/live status.
- Modify: [AliasEditorSheet.swift:24](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:24) — inline title, optional fields/binding, real recipient/draft/error.
- Modify: [AliasDetailScreen.swift:46](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasDetailScreen.swift:46) — copy/reveal/actual-vs-desired/link-login/management.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasLinkedServicesScreen.swift` — proposed global/per-alias list, scoped projection, open/unlink/review legacy flows.
- Modify: [AliasDomainPicker.swift:27](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasDomainPicker.swift:27) — hostname-first choices, appliedRevision/reactivity/default selection.
- Modify: [PrivateEmailIntroSheet.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/PrivateEmailIntroSheet.swift) — receive-only copy consistent.
- Modify: [EditorTarget.swift:5](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Vault/EditorTarget.swift:5) — explicit aliasID handoff contract.
- Modify: [UIStateStore.swift:14](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/UIStateStore.swift:14), [VaultShellBehaviors.swift:74](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Main/VaultShellBehaviors.swift:74) — sealed optional draft context/restore/revalidate; default backward decoding.
- Modify: [ItemEditorScreen.swift:68](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:68) — draft init/handoff; [create caller:722](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:722), [bind/save:795](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:795) — retain exact alias, bind after save.
- Modify: [VaultRepository+AliasManagement.swift:31](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasManagement.swift:31) — optional binding/ownership validation, reuse trusted snapshot phase 1.
- Modify: [RelayService.swift:88](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:88), [122](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:122) — serialize lifecycle, live-row checkpoint/status patch. State owner bàn giao file sau P2; Email không overlap P2 edits.
- Modify/reuse: [VaultRepository+AliasWriteback.swift:22](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasWriteback.swift:22) — link-later canonical field writeback/recovery; Domain bàn giao sau P1, giữ username/email thật.
- Modify: [AliasWriteback.swift:14](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/AliasWriteback.swift:14), [AliasSuggestion.swift:27](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/AliasSuggestion.swift:27) — guarded field conflict/protected/duplicate policy, canonical relation lookup thay sole boundItemId; reuse extra-protection gates trong editor.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/RelayLifecycleSafetyTests.swift` — proposed create/retry/link-handoff tests.
- Modify: [AliasSuggestionTests.swift:85](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/AliasSuggestionTests.swift:85), [PersonaIsolationTests.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/PersonaIsolationTests.swift) — optional binding/owner scope.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyUITests/PrivateEmailMemberUXUITests.swift` — proposed fixture workflow tests.

## Implementation Steps

1. Adopt phase 2 coordinator interface and phase 1 trusted suffix contract; preview empty/loading/error/partial result before view work.
2. Root hierarchy + neutral notice bằng shared component; off/offline/outage/maintenance/retired có next step đúng.
3. Integration merge glossary EN/VI/JA cùng UI PR; audit title/footer/error/accessibility/plurals.
4. Unified inline editor optional label/website/Login; no-login path hợp lệ, Save dead button bỏ.
5. Candidate Login filter theo true persona ownership, revalidate selected item ở submit.
6. Recipient preview và request cùng resolver/snapshot; nếu pin/default/profile đổi lúc sheet mở thì update rõ/reconfirm.
7. Website hint optional normalize hostname qua existing helper; không DNS lookup hoặc promise sender restriction.
8. Reserve/mint/route giữ checkpoints/error/draft; bỏ try? rồi dismiss dù thất bại. Serialize lifecycle per alias và patch live row sau await, giữ concurrent binding/label, reject deleted/stale identity.
9. Detail thêm service list/choose existing Login + canonical Private email writeback; existing conflicting/protected private email hướng mở Login hoặc chọn mục khác. New Login route carry aliasID trong sealed draft/restore, canonical field sau save; migrate create/reuse không blind fillEmail ordinary fields.
10. Test cancel/error/duplicate CTA/profile switch/cold draft restore; binding alias đã có cần explicit management, không auto repoint. Partial bind/field-write recovery không allocate alias khác.
11. Detail actual recipient reveal/target inbox/rotation progress; management destructive đúng một lần/menu confirmation.
12. Domain reactive options; lifecycle change trước mint yêu cầu chọn lại. Sau mint confirmed giữ namespace/address, resume route theo rotate policy dù domain createDisabled; no silent suffix swap/orphan mint.
13. Verify create callers: reusable [PersonaAliases:239](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/PersonaAliasesScreen.swift:239), service [AliasEditor:66](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:66), quick-create [ItemEditor:722](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:722).
14. Global/per-alias list, open Login, atomic guarded unlink, explicit legacy review/migration; tests delayed activation/unlink/stale editor và protected/duplicate fields theo addendum.

## Test Matrix

| Lớp | Ca | Kỳ vọng |
| --- | --- | --- |
| Unit/repository | nil Login/website, label-only, wrong persona, primarySpace nil | Create độc lập, no cross-profile binding |
| Unit flow | default/pin/profile, registry change mid-submit, unknown descriptor | Preview=request; no wrong/silent suffix |
| Handoff | existing/new Login save/cancel/failure/cold restore/remount, alias bound/deleted mid-editor | Exact aliasID survives sealed draft; bind only after save, no extra mint |
| Link-later/AutoFill | active unbound→Login, field conflict, partial write failure/retry | Canonical Private email đúng; real username/email giữ, conflict không auto replace, AutoFill đọc đúng |
| Linked services | one alias→many Login, persona switch, explicit legacy review; unlink one/all, protected/duplicates/stale editor | Count/projection đúng; transaction hoặc rollback; no remote pause/delete, no ordinary credential mutation hoặc reattach |
| Lifecycle race | bind/edit label/sync/delete khi activation hoặc rotation đang chờ | Patch riêng state trên live row, không overwrite binding/label hoặc resurrect deleted alias |
| Integration | reserve/mint/route fail/retry/relaunch; mint success→rotate fail→createDisabled | One checkpoint/address, routing-only retry cùng namespace, no orphan or draft loss |
| UI | no-login/pending/verified/offline, detail link/reveal, pause/delete | Actions/next steps đúng, back/cancel tốt |
| Snapshot | root/create/detail notice/error, long VI/email/domain | 375/430 XL/AX XXL no clipping/forced title ellipsis |
| Mail E2E | new/legacy domain/default change/pinned inbox | Receipt correct destination, old aliases immutable |

## Success Criteria

- [x] No Login vẫn create alias độc lập khi verified/available; optional fields storage đúng model.
- [x] Unbound detail link existing/new Login discoverable; exact sealed draft restore/cancel semantics và canonical field/AutoFill writeback pass.
- [x] Global/per-alias service list/open/unlink đúng scope, canonical N associations, protected/legacy/duplicate cases có recovery, no stale reattach.
- [x] Actual recipient biết được qua detail/reveal; desired rotation không giả success.
- [ ] Title/action VI không `…` do layout; notice surface/title/body rõ mọi theme.
- [x] One filled primary/state, create error không mất draft/checkpoint, retry không mint duplicate.
- [x] Domain default/persisted selection/immutability và trusted suffix giữ contract phase 1.
- [ ] EN/VI/JA, Motion/haptics/VO/DNA matrix pass.

## Risk Assessment

| Rủi ro | Khả năng × tác động | Mitigation |
| --- | --- | --- |
| Preview khác real destination | Cao × cao | Shared resolver/snapshot, actual checkpoint distinct |
| Login picker leak persona | Cao × cao | Ownership resolver, revalidate bind, nil-primarySpace tests |
| Handoff mint/bind sai alias | Trung bình × cao | Explicit aliasID, bind after save, cancellation/race tests |
| Retry duplicate/partial lost | Trung bình × cao | backendMinted checkpoint, bounded busy, retained reservation |
| Shared catalog conflicts | Cao × trung bình | Integration serialize, translations ngay mỗi UI PR |

## Compatibility and Rollback

- label/boundDomain/boundItemId nullable sealed đã có; không schema website/service-name giả mới. Optional trusted hostname growth từ phase 1 giữ backward decode.
- Revert views/entry độc lập, không xóa/tombstone alias đã dùng; giữ state CAS/ownership fixes.
- Domain disabled mới chỉ chặn create, không đổi suffix/revoke/stop ingress địa chỉ cũ.

## Decisions and Dependencies

- Depends phase 1 Gate D + phase 2 merged; mail new-domain acceptance đợi Gate M.
- Phase 3/4 parallel theo ownership; catalogue/components chỉ Integration sửa.
- Default `loox.pw` là đề xuất sau activation, explicit user selection không bị override.
