# Code Review Summary

Reviewed 2026-10-07. Scope: uncommitted native implementation of the five-phase Email riêng tư / Loox Member plan and Linked services addendum. The initial and final reviews cover the changed app/core/repository/service/UI files and the new unit, snapshot and UI tests; generated Xcode output and planning-only HTML are not production evidence. This report is read-only with respect to implementation and plan status.

## Overall assessment

The requested feature destinations, canonical one-address-to-many-Login projection, local atomic unlink, signed historical domain proof, visible-scope verification coordination and explicit recipient disclosure are implemented. Initial code review found four high-priority defects and five medium-priority defects. All nine source corrections were independently re-reviewed; the relevant focused regressions passed in the final complete unit suite, while domain-picker/repair-screen variants retain only source evidence. No open source defect remains from this review checkpoint. **PASS for the implemented source and automated native acceptance gate**, after independent correction review and final executable receipt inspection. Production mail, physical Debug/TestFlight and two-account iCloud acceptance remain separate unverified gates. This is not full P5, Gate M or release approval.

## Findings and fix verification

| ID | Priority | Finding | Status |
|---|---|---|---|
| R1 | High | Resume forwarding changes local state without reenabling the backend alias | Fixed; source re-reviewed and focused regression passed |
| R2 | High | Cancelled Relay/Quick View admissions can strand half-open breakers | Fixed; source re-reviewed and focused regression passed |
| R3 | High | Optional `.none` inference rejects explicitly unprotected semantic fields | Fixed; source re-reviewed and focused regression passed |
| R4 | High | Restored existing-Login relation edits lose the original CAS baseline | Fixed; source re-reviewed and focused regression passed |
| R5 | Medium | Atomic editor detach skips password-rotation notification updates | Fixed; source re-reviewed and focused regression passed |
| R6 | Medium | Registry update silently swaps the selected creation domain | Fixed; source re-reviewed; full picker visual matrix pending |
| R7 | Medium | Retry form recipient can differ from its pinned reservation | Fixed; source re-reviewed; real retry/mail receipt pending |
| R8 | Medium | Minted reservation disables the link-conflict recovery action | Fixed; source re-reviewed; conflict-recovery interaction variant pending |
| R9 | Medium | Choosing Default from a stale inbox snapshot downgrades verified state | Fixed; source re-reviewed and focused regression passed |

The descriptions below record the defects in the initial review snapshot. Current source corrections and regression assertions are recorded separately below.

### R1 — Resume must acknowledge backend activation

`AliasDetailScreen` now offers Resume forwarding for paused/disabled aliases. `RelayService.activate` calls create only when `backendMinted == false`, so an already minted disabled alias receives only `rotateDestination`, then is marked active locally. The supplied backend contract reenables DISABLED only in `createAliasOp`; `rotateDestinationOp` changes encrypted destination without changing status. Pause → Resume therefore reports success while incoming mail remains blocked.

Evidence: [AliasDetailScreen.swift:131](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasDetailScreen.swift:131), [RelayService.swift:125](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:125), [backend createAliasOp:111](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/aliases.ts:111), [backend rotateDestinationOp:184](/Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-relay/src/aliases.ts:184).

Fix: use an explicit signed, same-namespace reenabling acknowledgment, retaining the immutable local part/domain. Do not collision-remint an issued alias. Only mark active after acknowledgment; preserve paused state if operator/domain policy rejects it. Test the emitted command and namespace, not merely the local status.

### R2 — Every admitted probe needs a terminal outcome

Relay `send` consumes `allowRequest` before awaiting escrow/attestation/API, but its cancellation/error exits do not release an admitted half-open generation. New coordinator lifecycle cancellation makes this reachable from resend. After a cancelled probe, both verification reads and relay mutations can remain blocked until process restart. Quick View has the same class of bug: `resolve` consumes admission, then new generation/scope early returns occur before `noteSuccess`; stale failed resolves can also publish error into a newer generation.

Evidence: [RelayService.swift:375](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/RelayService.swift:375), [DestinationVerificationCoordinator.swift:208](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/Relay/DestinationVerificationCoordinator.swift:208), [QuickViewApprovalFlowModel.swift:128](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Sharing/QuickView/QuickViewApprovalFlowModel.swift:128). Status GET already has operation-token terminal cleanup; that does not cover signed sends or Quick View.

Fix: capture the admitted service/probe generation and finish it exactly once on every exit. Cancellation releases its own generation without fabricating success/outage. HTTP response reachability may finish admission even if generation changed, while UI state remains generation guarded. Test cancelled begin and cancelled/stale Quick View resolve at half-open.

### R3 — Enum `none` must be explicitly typed

The checks `(field.semantics?.actionAuthorization ?? .none) == .none` infer both occurrences as `Optional<ActionAuthorization>.none`. A field explicitly marked `ActionAuthorization.none` is therefore rejected as protected; the legacy candidate scan also omits readable semantic Email/username fields. The initial compiler log warns about the exact inference. A standalone Swift reproduction prints false for the current expression and true with the enum qualified.

Evidence: [AliasWriteback.swift:27](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/AliasWriteback.swift:27), [AliasLinkedService.swift:40](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Models/AliasLinkedService.swift:40), [ItemTemplateDefinition.swift:33](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/VaultifyCore/Types/ItemTemplateDefinition.swift:33).

Fix: use `ActionAuthorization.none` on both sides. Tests must cover nil, explicit enum none, reauthenticate and level2. Existing nil-semantics fixtures alone miss the defect.

### R4 — Sealed drafts need the original relation baseline

`.restored` initializes both `draft` and `original` from the recovered edited item. The new save CAS compares live canonical fields against `original`. For an existing Login draft with an unsaved alias link or detach, lock/relaunch/layout remount changes the baseline to the edited fields, so save consistently rejects the user's valid work as stale. The persisted draft currently carries the edited item and alias context but no original canonical baseline.

Evidence: [ItemEditorScreen.swift:91](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:91), [ItemEditorScreen.swift:957](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/ItemEditor/ItemEditorScreen.swift:957), [UIStateStore.swift:14](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/App/UIStateStore.swift:14), [VaultRepository+AliasLinks.swift:71](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasLinks.swift:71).

Fix: retain the original relation baseline in backward-compatible sealed draft metadata and restore it for CAS. Do not silently adopt current live fields, which would erase concurrent-unlink protection. Test existing Login link/detach → restore → save, and actual concurrent relation change → restore → rejection.

### R5 — Atomic relation commit must retain normal item-update effects

An editor detach returns through `commitAliasRelation`, bypassing the normal `update` post-commit reminder scheduling. Editing password, cadence or title in the same save updates storage but leaves the OS reminder on the old date/title. Cadence zero does not cancel the already scheduled reminder. The independent scout reproduced the same control-flow gap.

Evidence: [VaultRepository+AliasLinks.swift:100](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasLinks.swift:100), [VaultRepository+AliasLinks.swift:181](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+AliasLinks.swift:181), [VaultRepository.swift:502](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository.swift:502), [RotationNotificationService.swift:32](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Services/RotationNotificationService.swift:32).

Fix: share the successful item-update effects, preserving side-effect/settings guards and the committed password baseline. Verify notification scheduling/cancellation via a meaningful sink test.

### R6 — Invalid creation selection requires explicit reselect

`AliasDomainPickerSection` resets an invalid domain ID to the global default on registry revision. This violates the agreed no-silent-suffix-swap contract: readiness changing while the form is open can create a different address suffix without the user's selection.

Evidence: [AliasDomainPicker.swift:47](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasDomainPicker.swift:47), [design spec](../design-spec.md).

Fix: preserve invalid selection, explain readiness/reselect and disable new mint until an explicit valid selection. Minted reservations retain their namespace and remain routing-resumable.

### R7 — Retry must display its checkpoint's actual recipient

The creation form defaults `selectedInbox` dynamically, but reservation writes pin the resolved inbox ID. After partial failure, changing the global default can make the form show/gate a new inbox while retry activates the original pin. This repeats the recipient-preview ambiguity the overhaul is meant to fix.

Evidence: [AliasEditorSheet.swift:34](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:34), [AliasEditorSheet.swift:174](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:174).

Fix: derive display/verification prerequisites from the live reservation's pin/resolver once a reservation exists, or explicitly capture the chosen inbox ID at reservation. Keep retry on the exact checkpoint.

### R8 — Recovery must remain actionable after a reservation

The login-review NavigationLink is inside the form section disabled whenever a reservation exists. A field conflict/protection introduced while mint/route is suspended sets `loginNeedsReview`, but the offered Open login action is disabled. A selected Login retained when switching to reusable type is also prevalidated despite not being used for that type.

Evidence: [AliasEditorSheet.swift:48](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:48), [AliasEditorSheet.swift:75](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:75), [AliasEditorSheet.swift:146](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Features/Personas/AliasEditorSheet.swift:146).

Fix: separate read/recovery navigation from disabled reservation inputs, and only prevalidate the selected Login for service-address creation.

### R9 — Default selection must patch the live inbox

`setDefaultInbox` originally sealed the caller's inbox snapshot. With P2 automatic refresh, a menu opened while Pending could remain visible after verification, then its Default action would restore Pending and stale destination identity. The corrected method fetches the live record by ID before changing only the default flag.

Evidence: [VaultRepository+ForwardingInboxes.swift:150](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/Vaultify/Data/Repositories/VaultRepository+ForwardingInboxes.swift:150). The new `testMakingStalePendingSnapshotDefaultPreservesLiveVerificationIdentity` asserts verified status, destination ID, generation and email survive the stale action.

## Independent source re-review of corrections

- **R1:** The minted paused/disabled path routes while disabled, then sends signed `createAlias` for the exact existing domain/local part. Status becomes active only after the reenabling ACK. `RelayLifecycleSafetyTests` assert actual service command ordering, fixed namespace, failed routing, refusal and no remint.
- **R2:** `CapabilityStore` stores tokenized request admissions; one terminal removes the token, and cancellation releases only its admitted half-open generation. Relay `send` uses `defer` across escrow/attestation/transport and preserves `CancellationError`, cancelled URL requests and CloudKit cancellation before failure mapping. Quick View resolves report a terminal outcome before generation/UI guards; late errors cannot overwrite cancelled state. `requestPolicyAllows` checks user/operator/per-operation/offline policy independently of transient breaker/health, so the admitted recovery reply is not rejected solely because its probe is half-open. Actual service policy remains server enforced. Relay and Quick View regression assertions cover cancellation, one-probe exclusivity, duplicate terminal delivery and stale errors.
- **R3:** Both helpers now explicitly use `ActionAuthorization.none`. The regression covers absent and explicit none, reauthentication and Level 2, canonical projection, legacy projection and AutoFill's readable value.
- **R4:** The sealed draft carries optional `originalItem` with a backward-compatible fallback. Restoration uses that original CAS baseline; real concurrent relation changes still reject. The regression seals/decodes and saves restored existing-Login link/detach, then checks concurrent-unlink rejection.
- **R5:** Ordinary updates and atomic relation commits call `didCommitItemUpdate` after successful persistence. Existing reminder settings/side-effect guards are preserved. The sink test checks cadence zero, changed password, removed canonical email and exact committed password baseline reaching that common effect. Physical OS notification scheduling is not exercised by the sink.
- **R6:** The invalid registry selection is retained, explained and rejected by the create button's exact domain-ID eligibility. Only explicit selection changes it. Repository creation proof still rejects inactive mappings. Minted retry retains immutable namespace.
- **R7:** Once reserved, the form derives its recipient from the reservation's pinned inbox ID. Creation captures the initial resolved inbox; a later global default change cannot change the displayed/gated retry target.
- **R8:** Open login recovery is outside the disabled reservation-input section. Selected-Login and website validation only applies to service addresses; stale optional service inputs do not block reusable creation.
- **R9:** Default selection fetches live inbox metadata before mutation. The stale-pending snapshot test verifies the refreshed state is preserved.
- Initial actor warnings were corrected in source: domain configuration constants and the pure `LooxLinkEnvelope.shareableFields` helper are `nonisolated`; the coordinator nested reduction explicitly captures `self`. Final compile/test receipts identify no new feature-source warning. Two inherited AppleAssetInspector main-thread runtime warnings remain in the unit log; these are not new feature failures.

## Spec compliance and acceptance evidence

Statuses distinguish source inspection, executable tests and real-world acceptance. Plan checkboxes are not updated by the reviewer.

| Requirement group | Source evidence | Remaining evidence |
|---|---|---|
| P1 Gate D, production Debug/TF parity | `DomainRegistryClient` uses production URL/env; injected test URL/env retained; trust suite 8/8 passes | Actual physical Debug/TF upgrade and operator/canary runbook execution |
| P1 trusted immutable address, backward blobs | Optional sealed hostname/proof/revision; signature/env historical mapping; nil unknown resolver; consumers migrated; minted update guard | Fresh-device offline and physical upgrade receipt |
| P1 Gate M / legacy delivery | No native hardcoded loox.pw activation or auth flag relaxation observed | D1 rights, routing, actual new/legacy mail and increasing signed-registry activation remain unverified |
| P2 pending wake / shared loop / policy | AppEnvironment ownership, Root lifecycle/repository/policy observers, visible registrations, process-wide 30/60s budget | Coordinator suite 12/12 passes; actual browser-confirm-return timing remains pending |
| P2 CAS/no downgrade/no-op | Exact inbox/email/destination/generation persistence checks and semantic no-op before seal | ForwardingInbox 12/12 and ForwardingInboxService 5/5 pass; physical server-state refresh pending |
| P2 privacy and actual/desired state | Dedicated deliberate detail reveal; lock/inactive/exit conceal; guarded sensitive copy; checkpoint vs desired rows | Native matrix and VoiceOver/device verification |
| P3 no-Login create / resumable checkpoint | Optional Login/label/website; reservation ID retained; backendMinted preserves routing retry | Native retry/reselect/recovery interactions and actual relay/mail |
| P3 linked services/open/local unlink | Canonical sealed fields, N associations, scoped projection, explicit legacy review, atomic item+alias save, original credentials retained | AliasLinkedServices 14/14 and RelayLifecycleSafety 8/8 pass; restored-editor UI variants remain pending |
| P3 localization/design/accessibility | Tokens/Polaris, wrapping email/domain, short inline titles, distinct neutral semantic fill | 149 declared EN-source/VI/JA strings audited with no missing VI/JA; 40 final renders and six mounted captures reviewed independently; remaining full runtime matrix below |
| P4 feature roots/scope | Hub routes to Share Links/Browser/Family; shared owned projection rejects missing folders; persona change dismiss/revalidation | Three new native UI cases pass, six mounted captures; populated histories and secondary routes remain partial |
| P4 truthfulness/auth/commerce | Historical links omit working URL; Browser attempts omit fields/codes/keys; existing signed signer/SAS/App Attest/Face ID/cohort/capability paths reused | QuickViewResolveSafety 2/2 passes; actual signed Browser ceremony and service-outage runtime pending |
| P4 Family | Share-derived people, explicit item approvalOnly/Space chooser, Approval Mode independent of item sync | Two iCloud account/device invite/accept/ceremony/update/revoke |
| P5 exact integrated validation/release | Final hosted unit/snapshot/UI pass; generic signed iOS workspace compile succeeds; final diff whitespace check and declared localization audit pass; integration owner reports privacy check pass | Physical Debug/TF, Apple candidate, external ceremonies and full DNA runtime matrix remain pending; no release performed |

## Edge cases and blast radius checked

- Extra Protection, explicit semantic authorization, duplicate canonical fields, foreign/missing folders, unknown domain proof, deleted items and stale confirmation were traced through repository and UI consumers.
- AutoFill's alternative Private email uses `privateEmailValue`; fail-closed protection/duplicates suppress that alternative without changing ordinary username/Email. R3 affects this consumer too.
- CloudSync pushes item and alias records independently. The one-save atomicity guarantee is local SwiftData; remote devices may transiently see different item/pointer snapshots. Canonical field projection remains authoritative. No claim of cross-device transactional atomicity is made.
- Existing Family resume activation still reads an item before participant-profile awaits; this inherited path was noted, not misclassified as a new diff defect. New Browser ownership revalidation was inspected across biometric, compose, attestation and entitlement-refresh suspension points.
- Link revoke credentials and orphan cleanup stores remain retained; no full historical URL/key persistence added. No backend/provider account auto-discovery introduced.
- App Attest/principal assertions, signer verification, Approval Mode prerequisites and vault-key checks remain in sensitive commands. No new plaintext endpoint or secret logs were found in the inspected changes.

## Final automated receipts and latest UI source review

The reviewer read the final tester report and executable logs rather than treating earlier failures or stale green output as final acceptance. See [Native QA receipt](tester-261007-2124-native-verification.md), [independent native UI review](native-ui-review.md) and [snapshot noise audit](snapshot-noise-audit.md).

| Check | Final result | Boundary |
|---|---|---|
| Hosted unit suite | 1457 total, 1456 passed, 0 failed, 1 expected skip; `/tmp/vaultify-ux-unit-clean.xcresult` | 1447 XCTest plus 10 Swift Testing; favicon data protection skip is physical-device-only |
| Snapshot suite | 12/12 passed; `/tmp/vaultify-ux-snapshots-latest.xcresult` | Four new render cases produce 40 images; images require manual review and are not pixel baselines |
| New native UI cases | 3/3 passed; `/tmp/vaultify-ux-ui-clean.xcresult` | Six mounted screenshots; reveal, feature destinations, decline/confirm local unlink and preserved ordinary fields |
| Earlier existing UI journeys | 3/3 passed | Earlier tree only; retained regression evidence, not relabeled as a final-tree rerun |
| Generic signed iOS Debug compilation | `/tmp/vaultify-device-xc.log` ends in successful workspace compilation | App plus embedded targets; no physical launch or App Attest ceremony proved |
| Body contrast | 504 ratios pass ≥4.5:1 | Four builtins × seven accents × three opt-in body roles × six content surfaces; not runtime/live-switch coverage |
| Declared new localization | 149 EN-source keys; reviewer confirms no missing VI/JA values | Does not prove spoken VoiceOver correctness |
| Git whitespace | Final `git diff --check` passes | Does not stage or commit changes |

Latest UI source changes preserve business boundaries: three composer selection menus wrap the selected value, reservation fields remain immutable and the inbox value follows its pin; accessibility disclosure actions use a vertical layout; paused inbox aliases use a paused status; See all/management controls use 44pt minimum frames; Unlink remains an overflow action with explicit destructive confirmation; availability/verification guidance ranks one actionable banner and relegates standing Receive only guidance to contextual copy. New opt-in semantic body roles preserve existing control/icon tokens, with measured text contrast. No new substantive defect was found in these changes.

Two existing TutorialTooltip assertions now use precision 0.9999 only. Independent raster audit reports 74/80 changed pixels, ≤2/255 channel deltas, unchanged references and geometry. The comparator allows up to 436 differing RGBA bytes at that size, so tiny future changes may pass; other existing snapshots remain exact. This scoped tolerance is accepted with its documented limitation.

## Validation and limitations

- Initial `/tmp/vaultify-ux-xc.log` ends in successful app/embedded-extension simulator compilation. It is a pre-fix receipt, not approval of later edits.
- `git diff --check` passed at the initial review checkpoint.
- Standalone Swift enum reproduction proved R3's false rejection. Compiler warnings also identified actor-isolation/capture warnings for later integration cleanup; no strict Swift 6 acceptance is claimed from the successful Swift 5-mode compile.
- Final hosted unit/snapshot/UI receipts were independently inspected after meaningful focused assertion review. Tester-measured app line coverage is 19.46% and function coverage 25.07%, without UI/snapshot merging; full Relay/Quick View ceremonies retain substantial uncovered branches. Branch/type coverage are not available. No project-wide coverage target is claimed.
- No physical device, production mail, live Browser session, two-account iCloud ceremony or TestFlight candidate was exercised by this reviewer. These remain P5/Gate M requirements.
- `./.Codex/rules/development-rules.md` and `./docs/code-standards.md` were not present. Repository AGENTS.md and both design-contract documents were read; the native SwiftUI rules govern this review.

## Review checklist disposition

- Concurrency and mutation: verified operation admission cleanup, generation/scope guards, repository CAS, local atomic relation persistence and rollback; remote CloudKit records remain independently synchronized.
- Error boundaries and API contracts: checked Relay command ACK semantics against supplied backend, cancelled escrow/attestation/transport exits, verification response identity/no-op, and opaque errors without secret disclosure. No catch-and-swallow path added by the final UI polish changes these reviewed boundaries.
- Compatibility and validation: optional encrypted alias/draft metadata remains backward compatible; unknown domain proof fails closed; canonical fields reject protected, duplicate and conflicting inputs; unsupported item schema stays read-only.
- Identity and permission: vault state, ownership/persona/folder, operation policy and existing App Attest/principal/signed Browser/Approval Mode paths remain enforced. No privilege bypass was introduced for Debug or TestFlight.
- Efficiency and privacy: reviewed projections are local bounded collections, without new database calls per visible row; no new plaintext endpoint, outgoing credential field command or persisted Browser secret/working historical URL was identified in this scope.
- Plan facts: paths and symbols were checked against actual source; implemented contracts have source evidence and relevant tests. The matrix above deliberately retains requirements without external/runtime receipts.

## Recommended actions

1. The source/automated gate passes with R1–R9 closed and final receipts attached. Keep full P5 and release acceptance open.
2. Independent representative native visual/interaction review and declared catalog audit pass; complete the remaining matrix variants. Screenshots alone do not prove VoiceOver focus/order and spoken privacy, Reduce Motion timing, Reduce Transparency material fallback, increased contrast, live theme changes, 44pt interaction targets, lifecycle concealment or browser-confirm return timing.
3. Preserve explicit pending physical Debug/TestFlight, real Browser signed ceremony, actual new/legacy mail and two-account Family invite/accept/update/revoke acceptance. Simulator fixture success cannot satisfy those requirements.
4. Keep loox.pw creation disabled until Gate M has real mail proof. Only the signed registry/operator rollout can activate it. No release/deploy was performed by this reviewer.
