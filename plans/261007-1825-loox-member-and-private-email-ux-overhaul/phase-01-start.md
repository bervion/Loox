---
phase: 1
title: "Start"
status: in-progress
priority: P1
effort: "1d–2d, chưa gồm chờ quyền/canary"
dependencies: []
---

# Phase 1: Start

## Overview

Khóa hợp đồng UX/dữ liệu và chứng minh readiness `@loox.pw`. Hai gate: **D** (design/environment/data contract) cho native implementation, **M** (mail) cho activation; thiếu quyền infra không chặn triển khai UI sau Gate D.

Dependency `[1]` của các phase native chỉ tham chiếu Gate D. Phase 1 completion ghi nhận D đã đạt và runbook/owner M đã khóa; không yêu cầu M có delivery receipt. Các bước Infra M dưới đây là work package song song, kết quả actual-mail/server-registry activation được nghiệm thu ở P5; status P1 không được dùng làm bằng chứng M đã đạt.

## Implementation status (2026-10-07)

Gate D native acceptance: production parity, historical mapping/codec and minted namespace guards passed the final unit suite. Operational Gate M ownership/canary readiness is still pending. Actual-mail, fresh-device upgrade and live activation are not inferred from unit tests.

Source/synthetic checks and remaining external gates: [implementation progress](./reports/implementation-progress.md). A checked item records native source/executable acceptance only; physical and complete matrix gates stay separate and unchecked.

## Requirements

- Audit live: production registry v14, staging v7; `email-pw=createDisabled`, `relay-main` active/primary. Re-read/verify signature tại thời điểm triển khai.
- D1 read-only trả 7403; mapping/routing/delivery production chưa được xác minh. OAuth login không chứng minh quyền D1.
- Domain mới chỉ creatable sau thư thật đến inbox; không hardcode suffix hoặc mở creation chung để thử canary.
- Normal Debug và TF dùng relay production, phải dùng production domain registry đúng môi trường dữ liệu.
- Alias đã phát hành giữ đúng domain; unknown descriptor không được render/copy nhầm legacy suffix.
- Copy, neutral notice, CTA/state/motion, scope và ownership được chốt trước parallel work.
- Giữ App Attest, principal authorization, encrypted email và Approval Mode độc lập vault-item sync.

## Architecture

### Gate D: native contracts

1. Root: `Địa chỉ theo dịch vụ` / `Địa chỉ dùng nhiều nơi`; create sheet title `Tạo email riêng`, CTA `Tạo địa chỉ`.
2. Một filled primary/state, management qua menu; label/value stack khi hẹp/chữ lớn.
3. InboxDetail mở có chủ đích trong vault unlocked là deliberate disclosure: full local email, `Ẩn email`; background/lock/exit conceal ngay, foreground không tự reveal. Overview/alias detail mask, có `Hiện email` rõ.
4. Recipient preview và actual routing tách desired/last checkpoint; verified chỉ cho đúng identity.
5. DomainRegistryClient hiện Debug fetch staging tại [client:14](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Capabilities/DomainRegistryClient.swift:14), relay production tại [RelayConfig.swift:14](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Relay/RelayConfig.swift:14) cả config. Đổi normal Debug registry sang production; staging dùng explicit injected tests/isolated fixture, không chuyển shared records sang staging.
6. CapabilityManifestClient đã fetch production cả config; `envTag` chỉ cache scope tại [manifest:21](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Capabilities/CapabilityManifestClient.swift:21). Không đổi signed capability/cohort flags theo sửa domain registry.
7. Đề xuất optional sealed hostname snapshot cho alias: derive từ verified descriptor cùng domainID trước mint/server-bound create. Freeze domainID + hostname + localPart ngay tại checkpoint `backendMinted=true`, không đợi activation. Backfill blob cũ chỉ từ verified descriptor hoặc legacy-known ID.
8. Provenance: snapshot string đơn lẻ nhận từ sync là candidate. Alias mới mang optional signed registry envelope làm mapping proof trong sealed blob; verifier kiểm signature bằng trusted bundled key, đúng env/domainID/hostname. Historical proof chỉ phục vụ địa chỉ đã mint: lifecycle/expiry cũ không mở create/mutate mới; current registry vẫn phải đạt expiry/high-water/lifecycle riêng. Có thể reuse verified local envelope cho alias cũ; nil-proof unknown nonlegacy phải unresolved đến khi nhận mapping đã ký. Fresh device offline chỉ resolve nếu có proof hợp lệ đi cùng alias, không tin synced boolean `verified`. Current unsafe fallback tại [registry:123](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/AuxiliaryDomainRegistry.swift:123); sync chỉ nhận sealed blob tại [CloudSyncService.swift:579](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Sync/CloudSyncService.swift:579).
9. Ownership dùng semantics canonical `items(for:)`: folderId nil thuộc default; non-nil mà folder chưa resolve là unknown và bị loại khỏi list/count/chooser/action. Không dùng `personaID(forItem:)` hiện tại như bằng chứng ownership vì helper fallback default khi lookup lỗi. Chốt resolver nullable/fail-closed cùng contract và kiểm tất cả caller trước sửa shared helper.
10. User refinement: boundItemId là primary/legacy hint, không là complete list. Dịch vụ liên kết derive canonical Private email fields trên owned Login; N Login dùng một alias được hỗ trợ bằng field writes, unlink local atomic/guarded. Contract ở [addendum](./linked-services-addendum.md), P3 sở hữu.

### Gate M: mail flow và canary

1. Signed registry → verified descriptor/lifecycle → domain picker → alias domainID. SMTP recipient → routing/catch-all → ingress → D1 namespace → verified destination → forwarder → inbox thật.
2. Server create chỉ lifecycle active tại [aliases.ts:97](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/aliases.ts:97); ingress giữ existing aliases khi createDisabled, chỉ chặn retired tại [ingress.ts:93](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/ingress.ts:93).
3. Ưu tiên controlled fixture `email-pw` đã tồn tại nếu chứng minh đủ ownership/credentials. Nếu không có: design canary admission allowlist principal/domain, deadline và max creates; vẫn full signature/App Attest/verified destination/quota.
4. Apex `loox.pw` catch-all phục vụ production; staging apex dormant. Staging validate API/schema/registry/logic bằng isolated fixture/domain riêng nếu có; không repoint production catch-all. Production apex canary phải có receipt thư thật. Script V1 cũ không phải production-v2/App Attest bootstrap; không blind D1 writes.
5. Sau proof: phối hợp server lifecycle active + signed registry version tăng; primary `email-pw` chỉ sau quyết định default. Giữ legacy active/ingress.

## Related Code Files

**Owner Domain:** native trust/parity/model; merge trước phase 2/3. **Owner Infra:** BE/canary. **Integration:** shared component/catalog, không parallel edits chung.

- Modify: [DomainRegistryClient.swift:14](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Capabilities/DomainRegistryClient.swift:14) — production normal Debug/TF, injected isolated test env.
- Modify: [AuxiliaryDomainRegistry.swift:123](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/AuxiliaryDomainRegistry.swift:123) — unresolved domain resolution, no wrong suffix fallback.
- Modify: [EmailAlias.swift:23](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/EmailAlias.swift:23), [VaultRepository+Aliases.swift:18](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+Aliases.swift:18) — optional sealed snapshot + signed mapping proof, backward decode, verified-only migration. Historical mapping verification không thay current registry acceptance.
- Review scope contract: [PersonaPartition.swift:20](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+PersonaPartition.swift:20), [PersonaContext.swift:110](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift:110) — canonical items set cho các flow mới; helper legacy không được mở quyền cho unresolved folder. Nếu sửa helper, inventory caller phải liệt kê trước PR.
- Modify: [VaultRepository+AliasManagement.swift:12](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasManagement.swift:12) — stamp trusted snapshot when reserving; hand over to phase 3 after merge.
- Modify/test: [AuxiliaryDomainRegistryTests.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/AuxiliaryDomainRegistryTests.swift), [EmailAliasTests.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/EmailAliasTests.swift) — env/default/immutability/unknown descriptor.
- Review/modify Infra: [aliases.ts:97](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/aliases.ts:97), [domain-routing.ts](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/domain-routing.ts), [ingress.ts:93](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/ingress.ts:93) — canary/mapping, no legacy overwrite.
- Modify Infra after receipt: [production fixture:22](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-config/scripts/fixtures/domain-registry-production.json:22), [staging fixture](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-config/scripts/fixtures/domain-registry-staging.json) — lifecycle/default.
- Review: [BE phase-03:159](/Users/bervion/Developer/Projects/frontend/looxpassword/plans/260831-1004-cloudflare-account-consolidation/phase-03-mail-and-loox-pw.md:159) — actual delivery required; historical seed SQL không chứng minh live.
- Modify Integration: [VaultInfoBanner.swift:100](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/DesignSystem/Components/VaultInfoBanner.swift:100) — neutral surface có sẵn tokens, không đổi palette/solid warnings toàn app.
- Modify Integration: [Localizable.xcstrings:2](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Localizable.xcstrings:2) — EN/VI/JA cùng mỗi UI PR.

## Address consumers phải migrate

Owner Domain sửa tối thiểu fail-closed các 8 call sites dưới đây, merge trước handover Email UI. Không để resolver mới chỉ an toàn ở một màn:

- Modify [PersonaAliasesScreen.swift:204](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/PersonaAliasesScreen.swift:204) — address row unresolved; phase 2/3 nhận ownership sau D.
- Modify [AffectedAccountsScreen.swift:17](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AffectedAccountsScreen.swift:17) — migration review không show wrong suffix.
- Modify [AliasDetailScreen.swift:47](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasDetailScreen.swift:47) — copy disable unresolved; phase 3 nhận ownership sau D.
- Modify [ItemEditorScreen.swift:480](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:480), [729](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:729), [768](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:768) — suggestion/create/select không fill wrong suffix; phase 3 nhận ownership sau D.
- Modify [PrivateEmailRecognition.swift:23](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemDetail/PrivateEmailRecognition.swift:23) — recognize trusted snapshot only.
- Modify [VaultRepository+AliasWriteback.swift:22](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasWriteback.swift:22) — no wrong address writeback vào Login.

## Implementation Steps

1. Capture exact source/config revisions, reverify registry key/env/version; kiểm tra quyền account/D1 read-only.
2. Khóa Gate D theo [design spec](./design-spec.md): state table, recipient disclosure, scope, copy, motion, ownership và domain snapshot contract.
3. Sửa normal Debug domain parity bằng injection; test signed/env/cache migration, không change API shared-record backend.
4. Implement optional hostname snapshot + signed mapping proof + backward decode; backfill only known verified mappings, freeze ở mint checkpoint, migrate đủ 8 consumers ở trên, unresolved copy/fill/writeback disabled. Test forged proof, wrong env/host, fresh-device offline và historical proof không mở new-create.
5. Integration chốt neutral notice dùng semantic surface phân biệt canvas light/dark/custom; giữ action hierarchy/hit targets.
6. Read live mapping/routing/catch-all/ingress allowlist/sender SPF-DKIM-DMARC/destination verification; xác minh `relay-main` nguyên vẹn.
7. Chọn existing fixture hoặc canary allowlist implementation; khóa negative tests/auth/TTL/cleanup trước mutation.
8. Staging fixture kiểm tra API/schema/registry/logic; production canary apex dùng inbox test verified riêng, send thật và kiểm tra arrival/headers. User khác vẫn create-disabled; không đổi apex catch-all sang staging.
9. Receipt chỉ run ID/revisions/timestamps/outcome, không recipient/email/token/body/key.
10. Publish server lifecycle rồi registry mới cao hơn; app re-fetch/verifier test, giữ legacy delivery.
11. Sau primary/default decision, apply cho alias mới chưa explicit pick; remove canary allowlist, ghi rollback.

## Test Matrix

| Lớp | Ca | Bằng chứng |
| --- | --- | --- |
| Native unit | Debug/TF prod parity; injected staging; wrong env/signature/rollback | Fail closed, existing trust/caches đúng scope |
| Alias codec | old blob/legacy/nonlegacy; descriptor removed/cache offline; forged/synced snapshot; fresh device | Signed historical mapping resolve address only; nil/invalid proof unresolved, không copy legacy sai |
| Server integration | createDisabled public; canary đủ auth/sai principal/TTL/domain/quota | Không bypass App Attest/principal, không global opening |
| Staging integration | API/schema/registry/isolated fixture hoặc domain riêng có sẵn | Receipt ghi simulated/isolated, không coi là production mail proof |
| Mail E2E | production apex loox.pw, legacy regression | Receipt actual delivery đến inbox verified, routing/headers hợp lệ |
| UX contract | notice/CTA/reveal long VI; light/dark/custom | Phân biệt surface, text đủ, tokens đúng DNA |

## Success Criteria

- [x] Gate D có thiết kế/scope/privacy/copy/environment/immutable-domain contract và owners rõ.
- [x] Normal Debug/TF registry đúng production; isolated tests không dùng production mutations.
- [x] Không copy/render sai suffix khi nonlegacy descriptor mất; backward blobs vẫn an toàn.
- [ ] Runbook/owner Gate M đã khóa: staging logic/isolated evidence, production apex actual-mail receipt, public creation chỉ sau proof, không repoint catch-all. Receipt thực tế là acceptance P5, không blocker Gate D.
- [x] Native changes giữ namespace/suffix/checkpoint aliases đã phát hành, không reset. Actual legacy mail regression receipt thuộc P5 cùng Gate M.
- [ ] Canary cleanup/rollback và signed increasing-version procedure được ghi rõ.

## Risk Assessment

| Rủi ro | Khả năng × tác động | Mitigation |
| --- | --- | --- |
| Activate trước proof mail | Cao × cao | Gate M và controlled canary, không hardcode picker |
| Ghi nhầm D1 legacy mapping | Trung bình × rất cao | Read/capture trước, mutation chỉ email-pw, verify legacy sau |
| Registry unavailable copy sai suffix | Cao × cao | Trusted immutable snapshot, unresolved fail closed |
| Shared catalog/component conflicts | Cao × trung bình | Integration owner serialize mỗi UI PR |

## Compatibility and Rollback

- Optional sealed field decodeIfPresent; aliases cũ known legacy backfill deterministically, unknown nonlegacy đợi verified registry.
- Domain rollback bằng createDisabled server + signed registry version mới cao hơn; giữ ingress aliases đã dùng, không retired/global disable.
- Component opt-in/environment fix revert độc lập; không đổi API hay reset encrypted records để sửa debug.

## Decisions and Dependencies

- Open: D1 permission/mapping, controlled fixture hay canary admission, readiness receipt.
- Open: đề xuất `loox.pw` default mới sau activation; explicit stored choice giữ ưu tiên.
- P2/P4 bắt đầu sau D; M là gate activation/mail acceptance, không gate UI polish độc lập.
- CLI dependency `[1]` nghĩa P1 native Gate D; các Infra M steps 6–11 theo owner riêng có thể tiếp tục sau P1 completion và chỉ được đánh dấu đủ receipt trong P5.
