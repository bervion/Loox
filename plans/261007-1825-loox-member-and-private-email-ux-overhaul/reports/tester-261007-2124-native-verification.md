# Native QA receipt

Date: 2026-10-07. Host: Xcode 27.0, iOS Simulator 26.5 (23F77), arm64 iPhone 17 Pro. Separate fresh simulator per final suite. App and embedded targets compiled through generated `Vaultify.xcworkspace`, scheme `Vaultify-Quality`, Debug, ad hoc signing with Keychain entitlements. No commit or deployment performed by this tester.

## Scope and selection

Diff-aware inspection found 63 tracked changes and 75 Swift/catalog files including new files. Changes span shared theme/banner components, repository operations, relay/capability services, feature roots and test fixtures. Test-helper changes and shared-component fan-out escalate to the complete hosted unit suite and complete snapshot suite. Relevant new UI cases run against synthetic local vault records; existing critical UI journeys also ran earlier.

Mappings: domain → AliasDomainTrust/registry tests; recipient → ForwardingInbox/DestinationVerificationCoordinator tests; relationship/writeback → AliasLinkedServices/AliasSuggestion tests; relay lifecycle → RelayLifecycleSafety tests; browser recovery → QuickViewResolveSafety plus existing QuickView tests; Member → MemberFeatureProjection tests; body tokens → BodyTextContrast plus existing contrast tests. Feature roots → native render receipts and navigation/reveal/unlink UI cases. Populated Family/Share Links history, external-account delivery and some secondary sheets have no direct visual or end-to-end receipts.

## Results

| Suite | Receipt | Total | Passed | Failed | Skipped | Execution |
|---|---|---:|---:|---:|---:|---:|
| Complete hosted VaultifyTests, final source | `/tmp/vaultify-ux-unit-clean.xcresult` | 1457 | 1456 | 0 | 1 | XCTest 43.843s; session 53.982s |
| Complete VaultifySnapshotTests, final source | `/tmp/vaultify-ux-snapshots-latest.xcresult` | 12 | 12 | 0 | 0 | 3.232s; session 6.577s |
| New PrivateEmailMemberUXUITests | `/tmp/vaultify-ux-ui-clean.xcresult` | 3 | 3 | 0 | 0 | 71.312s |
| Existing walkthrough/edit-save-relock/panic-restart journeys, earlier source | `/tmp/vaultify-ux-ui.xcresult` | 3 | 3 | 0 | 0 | 97.247s combined |

Hosted unit total includes 1447 XCTest cases plus 10 Swift Testing cases. Expected skip: `FaviconServiceTests.testCachedFileIsWrittenWithCompleteProtection`, because Simulator does not enforce data protection (`FaviconServiceTests.swift:260`). This remains a physical-device check.

Focused final passing suites: AliasDomainTrust 8; DestinationVerificationCoordinator 12; ForwardingInbox 12; ForwardingInboxService 5; AliasLinkedServices 14; RelayLifecycleSafety 8; QuickViewResolveSafety 2; MemberFeatureProjection 9; BodyTextContrast 1 with 504 assertions; AliasSuggestion 5. These counts include existing cases in expanded suites.

Meaningful new checks include maintenance/disabled status GET without reopening mutation, stale email/generation rejection, lock during half-open GET, no status-triggered resend, URL cancellation cleanup, single recovery-probe ownership, stale Quick View error suppression, same-address resume acknowledgment, failed initial route retry without a second mint, canonical unlink preserving ordinary credentials/other links, shared rotation side effects and stale pending default selection preserving live verification identity.

## Native evidence

- [Final render manifest](../assets/native/capture-manifest.json): 40 PNGs, ten roots across 375pt EN light, 375pt VI light, 430pt VI dark, 375pt VI accessibility3 dark/high contrast. Explicit interface-style traits prevent the earlier dark-host mismatch.
- [Final mounted-app manifest](../assets/native-ui/capture-manifest.json): six screenshots from passing UI cases, including full recipient reveal, paused receiving status, dedicated Member destinations, native Unlink confirmation and preserved ordinary fields on the other Login.
- New render cases validate successful rendering and dimensions; images are manual-review receipts, not approved pixel baselines. Existing eight snapshot assertions passed. Actual mounted light navigation titles are readable; static hosting retains white light-mode inline titles and cannot prove navigation chrome.
- UI unlink declined the native popover by tapping outside when iOS 26 omitted a Cancel row, then reopened and confirmed. Both paths exercised; Gmail remained linked and ordinary username/email stayed intact.
- Independent [native review](native-ui-review.md) owns visual acceptance and its remaining matrix limitations.

## Coverage

Source: `/tmp/vaultify-ux-coverage-final.json`, generated with `xccov` from the complete final unit suite. App-only line coverage: 18,275 / 93,897 = **19.46%**. App function coverage: 3,015 / 12,028 = **25.07%**, counting functions with nonzero execution. Branch coverage unavailable from this report. Coverage is not merged with UI/snapshot runs; shared code also appears in extension targets, so aggregate target coverage would misstate app coverage. No project-wide 80% claim.

| Relevant source | Line coverage |
|---|---:|
| VaultRepository+ForwardingInboxes | 98.43% |
| AliasWriteback pure model | 100% |
| MemberFeatureProjection | 97.01% |
| AliasLinkedService | 92.45% |
| DestinationVerificationCoordinator | 88.61% |
| VaultRepository+AliasLinks | 84.48% |
| DomainRegistryDocument | 80.67% |
| ForwardingInboxService | 72.73% (initial run 13.46%) |
| RelayService | 45.71% |
| QuickViewApprovalFlowModel | 30.89% |

Relay attestation and full Quick View approval/upload behavior retain substantial uncovered paths. New tests cover the specific cancellation/checkpoint boundaries; they do not substitute for signed-device/service tests. Feature UI is intentionally outside unit coverage and has render/navigation evidence instead.

## Failures investigated and resolved

1. Initial full unit run had two obsolete assertions. AliasSuggestion now requires an actual owned Login with canonical binding, rather than an orphan pointer. Recipient generation now compares with the live destination-assignment baseline. A separate regression checks stale default selection cannot overwrite verified state.
2. New Relay lifecycle fixture initially assumed a profile identity existed after repository initialization. All eight cases failed before exercising behavior. Fixture now creates an explicit manual verified default inbox through throwing APIs; all eight passed in the final complete run. Failed receipt retained at `/tmp/vaultify-ux-unit-final.xcresult`.
3. New unlink UI initially queried Cancel that native iOS 26 did not expose. Native popover decline and confirm now both pass. A reused simulator after the earlier panic-lock journey launched into a locked state; that contaminated run was stopped, and final new UI cases ran on a fresh simulator. Runner convention: fresh simulator per suite.
4. Two existing TutorialTooltip snapshots failed exact comparison twice, including a fresh-process isolated run. Independent [raster audit](snapshot-noise-audit.md) quantified 74/80 changed pixels out of 1,092,000, maximum channel delta 2/255, with reference PNGs byte-identical. Only those two assertions use precision 0.9999; every other reference remains exact. This permits up to 436 RGBA-byte differences and can accept tiny visual changes. No reference replacement. Original actual/reference/diff attachments retained in `/tmp/vaultify-ux-native-captures/manifest.json`.
5. Failed unit bundle finalization stalled in Apple's `simctl diagnose --timeout=600`. Only that diagnostics child was terminated; xcodebuild then finalized exit65 with all eight fixture failures retained. The final successful suite closed normally.

No unresolved automated test failures. Tests above were not silenced or removed to obtain passing results.

## Warnings and performance

- Final unit report contains two existing runtime warnings from AppleAssetInspector P12 inspection on the main thread. Earlier clean compilation also reported existing non-Sendable closure conversions in OnboardingSyncConsentTests and a harmless AppIntents metadata extraction notice. No new feature-source compiler warning identified.
- Static render host emits appearance-transition console notices; mounted UI receipts supply navigation evidence separately.
- Slowest final unit case: QuickViewFlowTests TOTP composition 17.970s, followed by ordinary backup import 2.756s, pwned-check total-failure handling 2.008s and 500-password performance check 1.859s. TOTP composition waits on a real time boundary; consider injecting its clock to reduce suite variance.
- No Instruments leak, startup latency or animation frame-time measurement performed. Reduced Motion/Transparency, VoiceOver traversal and live theme switching were not enabled by these render captures.

## Remaining acceptance work

1. Physical signed Debug and TestFlight: App Attest environment, foreground verification return, actual recipient verification, forwarding, enabled `loox.pw` creation and existing legacy-address delivery. Local synthetic checkpoints prove none of these external outcomes.
2. Two-account iCloud Family/Approval Mode ceremony, populated sharing histories, secondary Login/domain/legacy sheets and failed/loading state visuals.
3. Full DNA runtime matrix: all seven accents rendered, longest selected Login/inbox labels, accessibility XXL, increased contrast plus Reduce Motion/Transparency, VoiceOver and live theme switching. Current numerical body-role tests cover four builtins × seven accents × three roles × six surfaces; they do not replace runtime review.
4. Additional isolated branch cases for ForwardingInboxService begin prerequisites/stale requests and full Relay/Quick View ceremonies. Keep physical data-protection acceptance open for the skipped favicon case.

Unresolved questions: no automated-suite blocker; external/device acceptance remains unexecuted by this tester.
