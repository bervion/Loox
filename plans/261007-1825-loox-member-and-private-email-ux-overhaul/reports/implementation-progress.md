---
date: 2026-10-07
status: in-progress
scope: native-private-email-member-ux
---

# Private Email and Member implementation progress

## Summary

Requested native flows are integrated and local automated acceptance is green.
Independent review rechecked all nine state/recovery corrections; final native review
closed the observed Composer/Inbox accessibility truncations. Full external and visual
matrix acceptance remains open. No new release, version bump, backend deployment or
production domain activation has been performed for this UI patch. Version remains
**1.56.6 (95)**; these changes are in the working source, not a new TestFlight candidate.

## Source changes

| Phase | Integrated behavior | Evidence still needed |
|---|---|---|
| P1 | Production registry parity, historical proof/codec and minted-identity guards passed source/unit acceptance | Physical upgrade/offline receipt; Gate M ownership/D1/routing/real mail |
| P2 | Coordinator/CAS/policy/service tests passed; final mounted recipient reveal/hide passed | Actual browser-confirm-return, lifecycle disclosure on device and timings |
| P3 | No-Login initial issuance retry, relation/rollback/restore and lifecycle tests passed; final unlink cancel/confirm UI passed | Full secondary/error state visual matrix and actual relay/mail/device flows |
| P4 | Named roots, ownership projections and metadata history passed source/unit/UI review; representative native roots reviewed | Populated/person/pending-share states, live Browser and two-account Family ceremony |
| P5 | Final unit/snapshot/new UI/privacy/catalog/local signing receipts green; docs synchronized | Full DNA matrix, physical Debug/TF, exact release revision/CI/candidate/runtime smoke |

`loox.pw` remains unavailable for new addresses in the captured signed production
registry. The app explains unavailable entries after accepting that registry; it does
not hardcode readiness, change defaults or repoint mail ingress. UI-only rollout remains
possible while the operational mail gate is pending.

Linked services represent saved vault associations, not provider-discovered accounts.
One alias can serve multiple Logins; unlink changes one canonical field and matching
primary pointer locally. Main Email/username, other associations and forwarding remain
intact. Local SwiftData atomicity does not imply a cross-device CloudKit transaction.

Family remains derived from outgoing item shares. Independent family roster, seats,
billing roles and account membership are outside this implementation.

## Review fixes

The [independent review](./implementation-review.md) records **PASS** for source and
automated native acceptance, with R1–R9 closed and no substantive open source defect.
That decision leaves physical, mail, live Browser, Family and full runtime matrix gates open.

| ID | Integrated correction |
|---|---|
| R1 | Paused aliases use an acknowledged backend resume on the existing namespace; a refusal cannot report active |
| R2 | Relay/status/Quick View admissions finish once; cancellation releases its own half-open generation and stale resolve UI is guarded |
| R3 | Explicit `ActionAuthorization.none` is treated as readable; stronger protection remains blocked |
| R4 | Sealed drafts retain the original Login baseline for valid restores and concurrent-unlink CAS protection |
| R5 | Atomic editor relation saves reuse normal successful item-update/reminder effects |
| R6 | Registry changes preserve the selected namespace and require an explicit valid reselect before new mint |
| R7 | Composer retry shows and gates the reserved forwarding inbox |
| R8 | Post-reservation Login recovery stays actionable; unused Login selection is not validated for reusable type |
| R9 | Default-inbox selection reads current metadata before updating, preserving newly verified state |

Native visual review also added opt-in secondary/success/warning body text roles derived
at a 4.5:1 floor on content surfaces. Existing brand/control/icon pairing remains intact.
The 504 numeric body-role combinations passed. Final representative renders show complete
Composer type and Inbox Hide/Copy labels at accessibility3. Independent review inspected
26 of the 40 final renders and all six mounted-app captures; it leaves secondary states,
runtime accessibility settings and the broader matrix explicitly pending.

## Validation receipts

| Check | Current result | Limit |
|---|---|---|
| Workspace compilation | Final generated-workspace app and embedded-target compilation passed through the unit/snapshot suites and signed generic-iOS check | No real-device App Attest/mail exercised |
| Hosted unit suites | **1457 total: 1456 passed, 0 failed, 1 expected skip**. `/tmp/vaultify-ux-unit-clean.xcresult`; 1447 XCTest + 10 Swift Testing cases, session 53.982s | Favicon complete file protection is unavailable on Simulator; physical protection remains unverified |
| Snapshot suite | **12/12 passed** on final source, `/tmp/vaultify-ux-snapshots-latest.xcresult`; eight existing assertions plus four new cases producing 40 renders | New renders are manual-review attachments, not automatically approved pixel baselines |
| New UI suite | **3/3 passed**, `/tmp/vaultify-ux-ui-clean.xcresult`; 71.312s, six actual mounted captures | Synthetic recipient/association data; no live relay or CloudKit ceremony |
| Existing critical UI | **3/3 passed** in the earlier `/tmp/vaultify-ux-ui.xcresult` run | Earlier source receipt; distinct from the final new-feature cases |
| Localization | **149 mapped keys**, EN/VI/JA: 0 missing; prohibited fixed-copy punctuation: 0 violations | Completeness does not establish JA visual fit or VoiceOver traversal |
| Privacy manifests | Passed on the integrated source | No claim of release CI/archive acceptance |
| Whitespace / secret-pattern scan | Final integrated checks passed | Pattern scan is not a substitute for runtime/privacy review |
| Generic iOS development signing | **Final source passed**, `/tmp/vaultify-device-xc.log`, exit 0, app and extensions | Ready signed product only; no physical installation or device smoke was performed |
| Documentation | README, codebase summary, deployment runbook, feature map and quiet-banner guidance synchronized; 18 scoped Markdown files have no missing linked paths; plan validation and whitespace check passed | The prescribed `.Codex/scripts/validate-docs.cjs` is absent, so its checks were not run |

Receipts and scope: [tester report](./tester-261007-2124-native-verification.md),
[native visual review](./native-ui-review.md), [40-render manifest](../assets/native/capture-manifest.json)
and [six mounted-capture manifest](../assets/native-ui/capture-manifest.json).

Two existing Tutorial snapshot assertions use precision 0.9999 after an independent
[raster audit](./snapshot-noise-audit.md): 74/80 changed pixels, maximum delta 2/255,
unchanged geometry and reference PNGs. The comparator permits 436 differing RGBA bytes
at that size. No historical SDK cause is proven; other reference comparisons stay exact.

## Measured coverage

Final unit `xccov` receipt: `/tmp/vaultify-ux-coverage-final.json`. App-only line coverage
is **19.46%** and function coverage **25.07%**; branch coverage is unavailable. UI/snapshot
coverage is not merged into these numbers. Relevant line coverage: inbox repository
98.43%, coordinator 88.61%, alias relation repository 84.48%, ForwardingInboxService
72.73% (initial run 13.46%), RelayService 45.71%. Full Relay attestation and Quick View
ceremony paths remain substantially uncovered; these percentages are not device proof.

## External acceptance gates

- Physical Debug and a new TestFlight candidate: real inbox confirmation, foreground
  update, disclosure/conceal, no-Login creation, retry and link/restore flows.
- Gate M: correct D1 rights, namespace/routing verification, controlled production-apex
  `loox.pw` mail delivery and legacy regression, then coordinated server/signed registry
  activation using an increasing version.
- Two iCloud accounts/devices: Family item/Space invite, accept, ceremony, use, update
  and revoke with Approval Mode enabled and vault-item sync disabled.
- Full native DNA matrix: all required languages/sizes/themes/accents/live switches,
  contrast and VoiceOver. The fixture capture covers only its recorded variants.
- Exact green release revision, signing/upload, Apple processing and runtime smoke.

## Plan and documentation sync

All five phase files and their acceptance checkboxes were read. CLI local plan
`Vaultify/261007-1125` and phases 1–5 were set to `in-progress`; Markdown mirrors those
statuses. The installed CLI check/uncheck commands affect entire phases, so partial
acceptance is reconciled by targeted checkbox edits only when source/test evidence exists.
Every phase was reconciled against source and the final executable receipts. Checked
items are native/synthetic acceptance; no complete visual/physical gate was checked.
All phases remain in progress because remaining requirements are unproved. The original
exact-commit/CI release criterion remains unchecked despite green local working-tree checks.

| Phase | Checked acceptance items | Status |
|---|---|---|
| P1 | 4/6 | In progress |
| P2 | 5/6 | In progress |
| P3 | 6/8 | In progress |
| P4 | 5/7 | In progress |
| P5 | 1/7 | In progress |

CLI reports 21/34 acceptance items checked (61%, 0/5 phases complete). This measures
the original checklist, not release readiness or the fraction of source implemented.

Repomix generated a local filtered Swift-source/config compaction with security checks
enabled. It excluded resources, vendored C, generated projects and secret-file patterns.
The summary records the compaction's source counts; the generated `repomix-output.xml`
was moved to `/tmp/vaultify-native-source-20261007.xml` after inspection, keeping the
source checkout free of the 5.5 MB generated dump. It is not a release artifact.
Documentation coverage percentage is not measured. Test coverage is scoped above. Changed docs remain
below the 800-line limit; README remains below 300 lines.

## Recommendations and unresolved questions

Choose a release revision after deciding the remaining acceptance scope. Keep domain
activation and physical/two-account QA as explicit receipts. No physical target-device
selection was received, so no installation was attempted. Whether `loox.pw` becomes the
new default after successful activation
remains an operational/product decision; this patch preserves current signed policy.
