---
phase: 5
title: "Acceptance and Rollout"
status: in-progress
priority: P1
effort: "1.5d, chưa gồm Apple processing/QA account wait"
dependencies: [1, 2, 3, 4]
---

# Phase 5: Acceptance and Rollout

## Overview

Tích hợp, adversarial UX/security review và physical Debug/TestFlight receipts trước phát hành. Không đợi phase này mới thêm localization hoặc sửa state cơ bản; verification là source/code + flow thật, không mock-only.

## Implementation status (2026-10-07)

Final local receipts: 1457 unit cases (1456 pass, 1 expected Simulator skip, 0 fail); 12/12 snapshots with 40 renders; final new UI 3/3 with 6 mounted captures; privacy/catalog/whitespace and signed generic-device Debug passed. No exact release commit/CI/candidate/physical smoke exists for this patch, and the full DNA matrix is not claimed.

Source/synthetic checks and remaining external gates: [implementation progress](./reports/implementation-progress.md). A checked item records native source/executable acceptance only; physical and complete matrix gates stay separate and unchecked.

## Requirements

- Full unit/privacy/workspace checks qua exact integrated release commit; Tuist regenerate trước compile.
- Touched screens: Member, Email root/create/detail, Linked services global/per-alias/detail, inbox list/detail, domain picker, Links, Browser, Family/person/share chooser.
- Matrix 375/430, default/XL/Accessibility XXL, EN/VI/JA, light/dark/custom + seven accents, contrast, Reduce Motion/Transparency, VoiceOver.
- iOS 17.3 fallbacks và availability guards; native toolbar/navigation, existing tokens/Polaris/no raw feature palettes.
- Physical Debug/TF dùng production relay/registry/App Attest; staging chỉ explicit isolated tests, không chuyển sealed shared records.
- Web-confirm → foreground ở root/create/detail → state verified; new-domain và legacy mail nhận thật đúng inbox.
- Family hai iCloud accounts/devices: invite/accept/ceremony/use/update/revoke với vault sync off/approval on.
- Gate M chưa đủ thì UI polish có thể ship độc lập, email-pw giữ createDisabled; no domain-default activation claim.

## Architecture

### Dependency/evidence flow

1. Gate D → State/Member branches; State merge → Email. Integration serialize shared component/catalog, translations cùng mỗi UI PR.
2. State+Email+Member integrated → exact commit → generated workspace + privacy/full unit → fixture UI/snapshots → physical flows.
3. Gate M staging logic/isolated evidence + production apex actual-mail receipt → server/registry active phối hợp → verified app registry/cache/default/immutable-host checks → new-domain TF flow; không repoint production catch-all sang staging.
4. Tag exact green commit → sign/archive/upload → Apple processing VALID/internal ready → TF runtime smoke → actual rollout completion.
5. Evidence report chỉ run IDs/revisions/environments/timing/results. Screenshots synthetic inboxes; không logs/email thật/token/key/body.

### Observable acceptance journey

- Member tile mở đúng feature; root có purpose, empty next step và one primary phù hợp state.
- Chưa Login vẫn create address; detail link later existing/new Login, exact aliasID survives sealed draft restore và bind after save, cancel giữ unbound; canonical field/AutoFill writeback và conflict recovery đúng.
- Inbox detail deliberate open đọc/copy local full email; return foreground vẫn concealed, overview/alias detail masked với reveal.
- Confirm web quay app state refresh không force quit/manual đổi màn; status chỉ verified đúng identity.
- Registry missing/removed descriptor không Copy wrong suffix; old aliases/default choices giữ nguyên.
- Motion không delay security result; Reduce Motion instant, haptic service không duplicate, theme switch không invisible text.

## Related Code Files

**Owner QA/Integration:** no feature parallel edits; failure giao lại đúng owner, relevant retest sau fix. Phase 3/4 không đồng thời sửa shared fixture/catalog.

- Review/run: [Makefile:18](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Makefile:18) — Vaultify-Quality và test simulator isolation.
- Review/run: [ci.yml:21](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/.github/workflows/ci.yml:21) — exact commit full unit/privacy receipts.
- Review/run: [check-privacy-manifests.sh](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/scripts/ci/check-privacy-manifests.sh) — packaged targets manifests.
- Review: [Project.swift:435](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Project.swift:435) — unit/snapshot/UI targets đã tồn tại, source globs; [quality scheme:490](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Project.swift:490) carries cả ba suites, Tuist generate đưa proposed test files vào đúng target.
- Modify if needed: [UITestFixtures.swift](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/UITestFixtures.swift) — synthetic pending/verified/unbound/link/share states.
- Review: [TestAppEnvironment.swift:29](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyTests/TestAppEnvironment.swift:29) — isolated service lifetime/caches, no stale shared process state.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifySnapshotTests/PrivateEmailMemberSnapshotTests.swift` — proposed component/state/layout snapshots.
- Create: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/plans/261007-1825-loox-member-and-private-email-ux-overhaul/reports/acceptance-receipt.md` — planned actual/pass/blocked matrix và evidence links.
- Modify: [README.md](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/README.md), [codebase-summary.md](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/docs/codebase-summary.md), [deployment-guide.md](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/docs/deployment-guide.md) — real navigation/state/domain operation runbook.
- Review: [Localizable.xcstrings:2](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Localizable.xcstrings:2) — semantics/interpolation/plurals; catalogue already updated each UI PR.

## Implementation Steps

1. Integrate owners theo dependency, review diff, không overwrite unrelated user changes; capture exact revision.
2. Audit semantic catalog EN/VI/JA, title in-app localization, runtime appString, VO labels/plurals và language-toggle live.
3. Reverify target/source globs và Vaultify-Quality wiring tại Project.swift; hiện đủ unit/snapshot/UI targets. Regenerate `tuist generate --no-open`; workspace generic Simulator compile app/extensions theo repo recipe, logs/derived paths không dùng từ bị hook chặn. Nếu target wiring đổi trước implementation, sửa manifest trước test, không coi folder mới là runnable target.
4. Full VaultifyTests + privacy manifests ở isolated simulator; receipt count/failures/exact commit, no mocks claim physical readiness.
5. Run meaningful added CAS/owner/lifecycle/domain/codec/alias-ID handoff tests; không repeat rộng suite nếu xanh và source unchanged.
6. UI navigation/no-login/create/retry/reveal tests synthetic; snapshot long VI/email/domain trên size/appearance matrix.
7. Adversarial UX: theme switch khi loading/reveal, keyboard/AX, repeated taps, back/cancel, persona đổi lúc picker/in-flight, record deleted detail đang mở.
8. 10 DNA rules: protagonist/text/control/shape/space/state, contrast 4.5:1 body /3:1 large glyph/control, target ≥44pt, status VO announcements.
9. Physical Debug production environment, full recipient/root/detail verification flows; optional Apple sandbox config chỉ theo deployment guide.
10. TF candidate cùng production env: web-confirm foreground ở root/create/detail; cooldown/dedupe, actual-vs-desired recipient và conceal/privacy shield.
11. Real mail `loox.pw` và legacy domain → pinned/default inbox chính xác; Gate M receipt/config consistency, no falsely active aliases.
12. Family hai iCloud accounts/devices, Approval Mode on/vault sync off; item entry approval-only/Space → invite/accept/ceremony/use/update/revoke/offline retry, không đi Quick Link từ Family CTA.
13. Exact release CI → signing/upload → Apple ready → TF runtime smoke; upload VALID không thay actual functional QA.
14. Docs/release notes/rollback receipts đúng kết quả; CLI phase completion chỉ khi acceptance pass, blocked row có owner/evidence needed.

## Test Matrix

| Nhóm | Variants bắt buộc | Observable pass |
| --- | --- | --- |
| Unit | CAS/no status downgrade/no-op, cancelled breaker, operator-mode GET, missing-folder scope, signed domain proof | 0 failure, stale identity không ghi state; local-read/network policy độc lập |
| Integration | begin/status, reserve/mint/route retry, link revoke, browser gate | No duplicate mutations/auth consent bypass |
| Navigation UI | mỗi Member tile, back/cancel, empty/no Login/error | Named destination, primary/next step rõ |
| Linked services | one alias→many Login; unlink one; delayed activate/editor; legacy review/protected/duplicate | Atomic/CAS no resurrection, ordinary credentials/other links/forwarding giữ nguyên |
| Screens | 375/430 × default/XL/AX XXL × EN/VI/JA | No essential title/action clipping/ellipsis, email wrap |
| Appearance | light/dark/custom/seven accents, live switch/contrast | Text/icons đủ contrast, no canvas-blended notices |
| Accessibility | Reduce Motion/Transparency, VoiceOver, target size | Instant security conceal, focus/order/status đúng |
| Physical email | Debug/TF × root/create/detail × new/legacy production domain | Lab target p95 foreground ≤3s, visible pending ≤8s; benchmark chưa đo, không SLA Internet; actual mail đúng inbox |
| Physical Family | hai accounts/devices, item/Space, approval on/sync off | Share/ceremony/use/update/revoke thực sự đúng |
| Upgrade | old sealed alias blobs/cache/env choice, registry unavailable, fresh device synced proof | Immutable suffix từ mint; valid historical mapping address-only; unknown/forged proof unresolved, no vault reset |

## Success Criteria

- [ ] Exact commit full unit/privacy/workspace green, generated Xcode artifacts không commit.
- [ ] Native screenshots/fixtures touched screens pass DNA matrix; HTML preview không thay native acceptance.
- [ ] Physical Debug và TF verification/reveal/no-login/create/link-handoff/retry pass có receipt.
- [ ] Domain mới/legacy real mail receipts đủ; nếu thiếu Gate M giữ disabled và scope release UI-only.
- [ ] Family hai account/device QA pass, no vault-sync gate hay cross-persona metadata leak.
- [x] No secret/key/new plaintext endpoint/log persistence; EN/VI/JA đầy đủ từ UI PR.
- [ ] Apple candidate ready + TF runtime smoke, docs và rollback receipts đúng implementation.

## Risk Assessment

| Rủi ro | Khả năng × tác động | Mitigation |
| --- | --- | --- |
| Simulator xanh/TF App Attest lỗi | Trung bình × cao | Physical Debug+TF production auth/env receipts |
| Mock che CloudKit/routing failure | Cao × cao | Hai account/device thật + actual mail receipt |
| Only EN/default UI review | Cao × trung bình | VI-first 375/430/AX XXL, themes/accessibility toggle |
| Ship domain chưa nhận thư | Cao × cao | Gate M hard blocker, UI release tách activation |
| Rollback làm aliases cũ chết | Trung bình × rất cao | createDisabled only, giữ ingress/suffix, no reset/retire |

## Compatibility and Rollback

- D component opt-in, State loop switch/CAS giữ, Email views và Member routes rollback độc lập; no cascading erase/revoke.
- Registry rollback version ký mới cao hơn, email-pw createDisabled, không retired khi còn aliases dùng.
- TF runtime lỗi: dừng growth/activation mới, keep legacy delivery, native hotfix bình thường; không force principal/vault reset.
- Preserve canary/acceptance receipts redacted và worker/config revisions để audit/retry không suy đoán.

## Decisions and Dependencies

- Phase 5 đợi State/Email/Member integrated và Gate D; mail/domain acceptance đợi Gate M.
- Nhận Infra M work package từ runbook P1; P1 completion chỉ chứng minh Gate D, không thay mail receipt. UI-only candidate được nghiệm thu độc lập khi M chưa đủ, domain tiếp tục createDisabled.
- Device, hai iCloud accounts và canary inbox là resource phải chuẩn bị trước; nếu unavailable nêu blocked thật, không thay mock rồi claim done.
- Yêu cầu hiện tại đã chuyển sang triển khai. Source/local checks được ghi trong implementation report; deploy/rollout/physical acceptance còn pending cho patch này.
