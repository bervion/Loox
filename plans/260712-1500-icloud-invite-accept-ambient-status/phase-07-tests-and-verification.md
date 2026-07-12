# Phase 07 — Tests + verification

## Context links

- Test target: `VaultifyTests` (in-memory VaultStore pattern; run via `make test DEST=...` with a concrete simulator UDID; scheme `Vaultify`)
- Existing pins to extend, not break: `VaultifyTests/ShareLifecycleStatusTests.swift` (status machine + monotonic store guard), `VaultifyTests/DeviceHPKEIdentityTests.swift:43-53` (merge basics)
- Depends on: phases 1-6

## Overview

- **Priority:** P1 (gate before merge)
- **Status:** completed (see verification notes at the bottom: local sim env crashes all UserDefaults-persisting tests, pre-existing at baseline — CI stable Xcode is the authoritative suite run)
- **Description:** Unit coverage for every pure decision added in phases 1-6, plus compile + full-suite runs and a device QA script for the push paths (pushes and CloudKit are not unit-testable — the plan keeps all push-adjacent logic behind pure helpers precisely so the decisions ARE testable).

## Key insights / test strategy

- **Unit (fast, deterministic):** everything that decides; nothing that transports.
- **Integration (compile-level):** `make check` proves app + AutoFill extension both compile with the shared `VaultifyCore` changes.
- **E2E (manual device QA):** push delivery, banner tap-routing, two-device conflict — scripted checklist in the PR, mirroring the existing device-QA discipline.
- CKContainer trap: test host must not touch CKContainer in init paths (known trap from prior work) — new tests stay on pure types (`ShareLifecycle`, `OwnerKeyVerification`, merge helpers, notifier decision).

## Test matrix

| Layer | What | How |
|---|---|---|
| Unit | `AppPushKind.classify` maps `approval-accept-<zone>` id → `.shareAcceptance`; unknown ids still default to `.vaultRemoteChange` | Build `CKQueryNotification` from a remote-notification dictionary fixture (`CKNotification(fromRemoteNotificationDictionary:)`); if CK refuses synthetic dicts in the test host, extract classification into a pure `classify(subscriptionID:)` overload and test that |
| Unit | `ShareStatusNotifier.shouldNotify` truth table: fires only on rank-advance INTO `.readyForCeremony` while app inactive; never on re-resolve of an already-ready share; never foregrounded | New `ShareStatusNotifierTests.swift` |
| Unit | `SharingStore.awaitingCeremonyCount` counts only `.readyForCeremony`, ignores confirmed/active and legacy records | Extend `ShareLifecycleStatusTests.swift` (store wipe pattern already there, `:73-99`) |
| Unit | Profile merge conflict convergence: server-record-with-device-A + incoming-device-B → both signing keys + both directory entries, order-independent, idempotent on repeat | Extend merge coverage (new `ParticipantProfileMergeConflictTests.swift`; pure `ParticipantProfileMerge` from `VaultifyCore/Sharing/ApprovalModels.swift:161`) |
| Unit | Request-refresh dirty-flag state machine: init → scan; clean+empty inbox → skip; push → scan; error → flag restored; mid-pass push survives (consume-then-restore) | Extract decision helper if inline (phase 4 note); `ApprovalRefreshGateTests.swift` |
| Unit | `OwnerKeyVerification` transitions: nil-on-new-pin ⇒ pending semantics, confirmed/skipped terminal (no re-prompt), backfill rule (pin exists + no marker → confirmed) | `OwnerKeyVerificationTests.swift` |
| Unit | Poll budget: waiting-sheet loop constant = 24 and every-tick acceptance check — pin via a small constants assertion only if extracted; otherwise covered by review | judgment: skip if it would force UI refactor (YAGNI) |
| Compile | App + extension | `make check` |
| Suite | Full unit run | `make test DEST=<sim UDID>` |
| Device QA | Banner-on-accept (bg + killed-cold-launch tap), no-banner-when-foregrounded, revoke removes subscription, two-device profile publish, verify-gate first-use + grandfathering, AutoFill withholding until decision | Scripted checklist in PR description |

## Related code files

**Create**
- `VaultifyTests/ShareStatusNotifierTests.swift`
- `VaultifyTests/ParticipantProfileMergeConflictTests.swift`
- `VaultifyTests/ApprovalRefreshGateTests.swift`
- `VaultifyTests/OwnerKeyVerificationTests.swift`

**Modify**
- `VaultifyTests/ShareLifecycleStatusTests.swift` — badge-count cases.
- Possibly `Vaultify/App/AppPushKind.swift` — pure `classify(subscriptionID:)` overload if CKNotification fixtures fail in the host (keep the CKNotification wrapper delegating to it).

## Implementation steps

1. Write unit files per matrix; keep each test file focused (one subject per file, mirrors existing suite style).
2. `tuist generate --no-open` (new test files are globbed) then `make check`.
3. `make test` with a concrete simulator UDID; fix failures per recommendations — never skip/weaken a failing test to pass.
4. Assemble the device QA checklist into the PR description (steps from phases 1, 2, 5, 6 success criteria).
5. Docs sync: update `docs/codebase-summary.md` sharing section (new subscription, notifier, verification gate) — docs impact: minor.

## Todo list

- [x] ShareStatusNotifierTests (passed)
- [x] ParticipantProfileMergeConflictTests (passed)
- [x] ApprovalRefreshGateTests (passed; RequestScanGate extracted as a pure struct in ApprovalCoordinator.swift)
- [x] OwnerKeyVerificationTests (passed)
- [x] ShareLifecycleStatusTests badge cases (written; crash-blocked locally — see notes)
- [x] AppPushKindClassificationTests via pure `classify(subscriptionID:)` overload (passed)
- [x] make check green (app + extension)
- [ ] make test green locally — BLOCKED by a pre-existing environmental host crash (see notes); all new suites pass, must be re-run on the CI stable Xcode before merge
- [x] Device QA checklist (below — for the PR description when the branch ships)
- [x] docs/codebase-summary.md sync

## Verification notes (local run, 2026-07-12)

- `make check` green (app + AutoFill extension).
- `make test` on iPhone 16 Pro (iOS 18.6) and iPhone 17 Pro (iOS 26.3), Xcode 27 beta (27A5218g): every test that WRITES `UserDefaults.standard` via a store `persist()` (SharingStore, SignedControlPlaneStore, SpaceHardening lastSelectedSpace, CloudSyncMerge, EmailAlias/ForwardingInbox/Persona LWW, Capability breaker...) hangs ~22s then the test HOST crashes with `malloc: pointer being freed was not allocated` plus `container_create_or_lookup_app_group_path... client is not entitled` — 30 tests total, including pre-existing tests that are green on CI.
- Attribution: reproduced identically on baseline commit 1c7e052 (pre phases 4-6) in a clean worktree, same simulator → environmental, NOT caused by this branch.
- All suites added by this plan passed: ShareStatusNotifierTests, ParticipantProfileMergeConflictTests, ApprovalRefreshGateTests, OwnerKeyVerificationTests, AppPushKindClassificationTests. The 3 new ShareLifecycleStatusTests badge cases use the same SharingStore-persist pattern as the crash-affected pre-existing cases and could not complete locally; they must be confirmed on the CI runner (stable Xcode).

## Device QA checklist (for the PR description)

1. Banner-on-accept: A invites, backgrounds the app; B accepts and unlocks → A gets the local banner within seconds-to-minutes; tapping opens the resume stepper on that share (warm and killed-cold-launch tap).
2. No banner while A is foregrounded (pending row on Home updates instead).
3. Revoking/leaving a share removes its acceptance subscription (no ghost pushes).
4. Two-device profile publish: accept the same invite on two of B's devices near-simultaneously (or re-run resume on device 2 right after device 1); owner-side profile lists BOTH deviceKeyIDs; a single-device grant to device 1 still decrypts on device 1.
5. Verify gate first-use: fresh share on B → opening the item shows the interstitial BEFORE any value; the code equals A's TrustFingerprintView code. Confirm → values + AutoFill after next refresh, relaunch no re-prompt. Skip → same, recorded. Dismiss → masked, re-prompts.
6. Grandfathering: a share active before this update shows zero new prompts.
7. AutoFill withholding: a pending share's credential does not appear in QuickType until confirmed/skipped in-app.
8. Request-scan gate: foreground with no requests logs the "request scan skipped" diagnostics line; a request push still surfaces the sheet; a request written while the app was dead surfaces on cold launch.

## Success criteria

- Full suite green including all pre-existing tests (notably `ShareLifecycleStatusTests`, `DeviceHPKEIdentityTests`, `SharedItemsProjectionTests`, `SharedCredentialsCacheTests` — the cache-exclusion change in phase 6 must not break them; update fixtures if the cache API grew a verification input, never delete assertions).
- Both targets compile.
- Device QA checklist executed once on hardware before release tag (push behavior cannot be signed off in simulator).

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| `SharedCredentialsCacheTests` / `SharedItemsProjectionTests` assume all zones feed the cache | M×M | Run suite early after phase 6; extend fixtures with verification state instead of loosening assertions. |
| CKNotification fixture rejection in test host | M×L | Pure classification overload fallback (planned above). |
| Simulator cannot validate silent-push wake | H×M | Explicit device QA gate; do not tag a release on simulator-only verification. |

## Security considerations

- Tests must not embed real credentials/keys — use fixture bytes as the existing suite does.

## Next steps

Ship: conventional-commit PR; after merge, consider the follow-ups noted in plan.md (ApprovalSpike removal, threat-model doc, R8 with the iPad/Mac plan).
