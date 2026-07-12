# Phase 01 — Silent acceptance push subscription (owner side)

## Context links

- Audit: `plans/reports/from-flow-audit-260712-1453-icloud-invite-accept-status-report.md` §2-F1, §5-R1
- Existing silent-sub patterns: `Vaultify/Services/Sharing/SharedZoneSubscriptionService.swift:26`, `Vaultify/Services/Sync/SyncPushService.swift:28`

## Overview

- **Priority:** P1 (unblocks phases 2, 3)
- **Status:** completed
- **Description:** Nothing pushes owner A when recipient B publishes their `ApprovalParticipantProfile` (the event that unblocks the ceremony). Add a per-zone SILENT `CKQuerySubscription` on the profile record type in A's private DB, classify it in the push router, and have `OwnerShareRefresher` react to the hint. Delete the subscription on revoke.

## Key insights

- B writes the profile via the shared DB into A's private-DB zone — record CREATE events in that zone fire A's private-DB query subscriptions. Proven mechanism: the existing `approval-req-<zone>` alert sub fires exactly this way when B creates request records (`ApprovalShareService.swift:107-124`).
- The request sub was deliberately narrowed to `ApprovalRequest` creation to kill phantom alerts caused by profile (re)publishes (`ApprovalShareService.swift:101-106`). A SILENT sub on the profile record cannot recreate that problem — no banner, no sound; the idempotent acceptance-resume re-publish just triggers a redundant (single-flighted, cheap) refresh.
- `OwnerShareRefresher.refresh()` already does the right thing on a hint: re-resolves only unconfirmed shares, monotonic store guard drops downgrades (`OwnerShareRefresher.swift:33-63`). It reads only CloudKit metadata + UserDefaults — works with the vault LOCKED, so a background silent push advances status without unlock.
- Background delivery infra already exists: `remote-notification` background mode + `registerForRemoteNotifications` (`AppPushDelegate.swift:20`), and `didReceiveRemoteNotification` routes CK pushes while backgrounded (`AppPushDelegate.swift:38-49`).

## Requirements

**Functional**
1. `createShare` also saves a silent per-zone `CKQuerySubscription` on `ApprovalConfig.participantProfileRecordType`, `.firesOnRecordCreation`, id `approval-accept-<zoneName>`.
2. Push router classifies the new subscription-id prefix and posts a dedicated `Notification.Name`.
3. `OwnerShareRefresher` observes that name and calls `refresh()`.
4. `revoke` deletes the acceptance subscription alongside the request subscription.
5. In-flight shares created BEFORE this change get the subscription backfilled (one best-effort pass per launch).

**Non-functional**
- Silent only: `shouldSendContentAvailable = true`, no alert/sound/title keys.
- Idempotent: re-saving the same subscription id on a resume/nudge `createShare` call must not error the flow.
- Gating: the refresh reaction stays behind `approvalModeEnabled` (already inside `refresh()`, `OwnerShareRefresher.swift:34`). Never touch `iCloudSyncEnabled`.

## Architecture / data flow

```
B unlocks → resumePendingShareAcceptance → publishProfile (CREATE in A's zone)
  → CloudKit fires approval-accept-<zone> silent push to A (bg or fg)
  → AppPushDelegate.didReceiveRemoteNotification → AppPushKind.classify
  → post .shareAcceptanceHint
  → OwnerShareRefresher observer → refresh() → resolveStatus (profile fetch)
  → SharingStore.updateStatus(.readyForCeremony)  [persisted, monotonic]
  → (phase 2 hooks here for the local banner)
```

## Related code files

**Modify**
- `VaultifyCore/Sharing/ApprovalConfig.swift` — add `acceptSubscriptionPrefix` + `acceptSubscriptionID(zoneName:)` next to `requestSubscriptionPrefix` (`ApprovalConfig.swift:46-52`).
- `Vaultify/Services/Sharing/ApprovalShareService.swift` — new `saveAcceptanceSubscription(zoneID:)`; call it in `createShare` next to `saveOwnerAlertSubscription` (`ApprovalShareService.swift:95`); add the id to the delete list in `revoke` (`ApprovalShareService.swift:394-395`).
- `Vaultify/App/AppPushKind.swift` — new case + prefix classification (`AppPushKind.swift:15-33`); new `Notification.Name` (`AppPushKind.swift:36-52`).
- `Vaultify/App/AppPushDelegate.swift` — route the new case in BOTH the iOS `route(_:)` (`AppPushDelegate.swift:51-62`) and the macOS branch (`AppPushDelegate.swift:158-171`).
- `Vaultify/Services/Sharing/OwnerShareRefresher.swift` — NotificationCenter observer in `init` (pattern: `ApprovalCoordinator.swift:47-51`, `MainActor.assumeIsolated`, retain `[NSObjectProtocol]`); backfill pass in `refreshAll`.

**Create / delete:** none.

## Implementation steps

1. `ApprovalConfig.swift`: add
   - `static let acceptSubscriptionPrefix = "approval-accept-"`
   - `static func acceptSubscriptionID(zoneName: String) -> String`.
2. `ApprovalShareService.swift`: add `private func saveAcceptanceSubscription(zoneID:)`:
   - `CKQuerySubscription(recordType: ApprovalConfig.participantProfileRecordType, predicate: NSPredicate(value: true), subscriptionID: …, options: [.firesOnRecordCreation])`, `subscription.zoneID = zoneID`.
   - `CKSubscription.NotificationInfo()` with only `shouldSendContentAvailable = true` (mirror `SyncPushService.swift:28`).
   - Save via `database.modifySubscriptions(saving:deleting:)`. Comment must explain WHY it is silent (a zone-wide/alert sub on profile writes produced phantom notifications — same rationale block as `ApprovalShareService.swift:101-106`), not reference the audit.
3. Call it in `createShare` right after `saveOwnerAlertSubscription` (`:95`). Wrap as `try await` — if it fails, share creation should still succeed? NO: keep it `try` like the alert sub; a share whose acceptance can't push is exactly the bug being fixed, and `createShare` is retried idempotently by the resume path.
4. `revoke` (`:394-395`): delete `ApprovalConfig.acceptSubscriptionID(zoneName:)` in the same best-effort `modifySubscriptions` call (pass both ids in `deleting:`).
5. `AppPushKind.swift`: add `case shareAcceptance`; in `classify`, check `subscriptionID.hasPrefix(ApprovalConfig.acceptSubscriptionPrefix)` BEFORE the default fallthrough. Add `static let shareAcceptanceHint = Notification.Name("shareAcceptanceHint")` with a doc comment (hint-only payload, observers re-resolve against CloudKit — same contract as the other hints).
6. `AppPushDelegate.route` + macOS `didReceiveRemoteNotification`: `case .shareAcceptance: post(.shareAcceptanceHint)`.
7. `OwnerShareRefresher`: add `private var observers: [NSObjectProtocol] = []`; in `init`, observe `.shareAcceptanceHint` → `MainActor.assumeIsolated { self?.refresh() }`.
8. Backfill for pre-existing in-flight shares: in `refreshAll`, after computing `pending`, if a `private var subscriptionsBackfilled = false` flag is unset, best-effort `try? await shareService.saveAcceptanceSubscription(zoneID:)` for each pending zone, then set the flag. Requires making `saveAcceptanceSubscription` internal (not private). One pass per process lifetime; failures retry next launch.
9. Compile check (`tuist generate` + workspace xcodebuild per CLAUDE.md).

## Todo list

- [x] ApprovalConfig: accept-subscription id helpers
- [x] ApprovalShareService: saveAcceptanceSubscription + createShare wiring
- [x] ApprovalShareService: revoke deletes acceptance sub
- [x] AppPushKind: case + prefix + Notification.Name
- [x] AppPushDelegate: route (iOS + macOS branches)
- [x] OwnerShareRefresher: observer + one-shot backfill
- [x] Compile check passes (app + extension)

## Success criteria

- Device QA: A invites, backgrounds app. B accepts + unlocks. Within ~1 min A's `SharingStore` record reads `.readyForCeremony` on next A launch WITHOUT A having foregrounded in between (verify via `ShareDiagnostics` log / DEBUG file self-test — stdout capture is unreliable per CLAUDE.md).
- `revoke` leaves zero `approval-accept-*` subscriptions for the zone (inspect via CloudKit dashboard or a DEBUG listSubscriptions probe).
- Re-running `createShare` for the same zone (nudge path, `ShareResumeStepperSheet.swift:234`) does not throw.

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| iOS throttles silent pushes (budgeted, not guaranteed) | M×M | This is a HINT layer; existing foreground/unlock refresh triggers (`VaultShellBehaviors.swift:75-97`) remain the safety net. Never remove them. |
| Push arrives while device locked → CloudKit fetch fine (no vault key needed), but SharingStore write to UserDefaults must not require unlock | L×M | `SharingStore` is plain UserDefaults (`SharingStore.swift:117-121`), not file-protected vault data — writes succeed after first unlock since boot. Acceptable; foreground pass covers the cold-boot edge. |
| Subscription save fails mid-createShare → share exists without acceptance push | L×M | Backfill pass in `refreshAll` (step 8) self-heals every launch. |
| New prefix collides with existing classification order | L×H | Prefix `approval-accept-` is checked with `hasPrefix`; verify no other id starts with it (inventory: `vault-zone-changes`, `approval-req-*`, `approval-shared-db`, `loox-invite-inbox` — no collision). |

## Security considerations

- Silent push carries no payload beyond subscription id; observers re-resolve against CloudKit (verify-before-show is untouched). Same hint-only model the audit rated solid (§3-S4).
- No new data written to CloudKit; subscription metadata only.

## Next steps

Phase 2 (local notification fires from the background refresh this phase enables); phase 3 (waiting sheet listens to `.shareAcceptanceHint`).
