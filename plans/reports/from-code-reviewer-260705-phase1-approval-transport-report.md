# Code Review — Phase 1 Approval Mode Transport (uncommitted)

Scope: 4 modified + 5 new Swift files, ~560 LOC. Compile green (iOS sim + macOS) per orchestrator.
Plan: `plans/260705-1137-approval-mode-sharing/phase-01-icloud-ckshare-enablement.md`

## Overall Assessment

Solid phase-1 landing. Push-pipeline separation (ADR-5) is correctly implemented and provably
bypasses the `iCloudSyncEnabled` gate; legacy sync-push behavior is byte-equivalent. Prereq gates
are genuinely fail-closed. No launch-time CloudKit touch. No Critical findings; nothing blocks
the spike run. Medium items are mostly "must address by Phase 3/7", one doc-comment lie to fix now.

## Critical

None.

## High

None.

## Medium

1. **Cold-launch approval-alert taps are silently dropped.**
   `AppPushDelegate.route()` (AppPushDelegate.swift:51-60) is fire-and-forget via NotificationCenter.
   The only `.approvalRequestReceived` observer is `ApprovalSpike.shared` (ApprovalSpike.swift:37),
   created lazily when `SyncSettingsView` first renders. Owner taps the alert with app killed →
   `didReceive` posts before any observer exists → event lost; owner must re-trigger. Tolerable for
   the spike (may confuse T_transport measurement runs), but AppPushDelegate is *durable* plumbing —
   Phase 3 must buffer the last routed push (or make pending state pull-queryable, which the
   "fetch latest from zone" design already half-supports).

2. **`approvalModeEnabled` is a dead flag + misleading doc comment.**
   SettingsStore.swift:64 adds the flag; nothing reads it. SharedZoneSubscriptionService.swift:9
   claims the service "is gated by `approvalModeEnabled`" — the code gates only on
   `CloudSyncService.isConfigured` (line 21). Plan step 7 says "the approval push observer + spike
   are gated by it". Deviation from phase-01; at minimum fix the comment so Phase 3 doesn't inherit
   a false contract.

3. **macOS share-accept posts success on failure.**
   AppPushDelegate.swift:136-140: `try? await container.accept(metadata)` then unconditionally posts
   `.vaultShareAccepted`. iOS branch (lines 103-113) posts only on success. Observers on macOS will
   believe an accept happened when it didn't.

4. **Erase Vault leaves approval artifacts in iCloud.**
   `CloudSyncService.eraseRemote()` (CloudSyncService.swift:72-81) deletes the Vault zone + sync
   subscription only. Spike/approval zones (`apz-*`), the zone-wide CKShare, alert subscriptions,
   and the shared-db subscription flag survive; `SharedZoneSubscriptionService.clearLocalFlag()` is
   never called. Phase-7 (revocation/share management) scope, but record it there explicitly —
   an "erased" vault keeping a live share grant is a trust-model surprise.

5. **Scene-delegate injection needs one runtime smoke test** (risk spot 1).
   The pattern — adaptor delegate returning `UISceneConfiguration` with a `delegateClass` that
   conforms to `UIWindowSceneDelegate` and never creates a window (AppPushDelegate.swift:30-36,
   97-114) — is the established SwiftUI-lifecycle approach for `userDidAcceptCloudKitShareWith`;
   SwiftUI still hosts the WindowGroup. Failure mode if wrong is a black screen at launch, so do one
   cold-launch check on the simulator before merging (the spike run will exercise it anyway).

## Low

1. **Double-post of `.approvalRequestReceived`** (risk spot 4): willPresent routes AND banners
   (AppPushDelegate.swift:83-88); tapping that banner routes again via didReceive (line 66-74).
   Downstream `ownerFetchRequest()` is idempotent (full refetch, reassigns `pendingRequest` to
   newest) — confirmed safe. Both runs are @MainActor-serialized.
2. **Rotation local notifications unaffected** (risk spot 2): previously no UN delegate → foreground
   notifications suppressed by default; `willPresent` returning `[]` (line 90) is exactly
   equivalent. Rotation content sets no userInfo (RotationNotificationService.swift:92-108), so
   `CKNotification(fromRemoteNotificationDictionary:)` returns nil on tap → no routing side effect.
3. **`MainActor.assumeIsolated` in observers** (risk spot 3): identical to the established
   SyncCoordinator pattern (SyncCoordinator.swift:38,45) with `queue: .main` delivery — safe.
   No retroactive fire during `ApprovalSpike.init`, so no reentrancy on `shared`.
4. **`fetchAll` pagination** (risk spot 5): terminates on `moreComing == false`
   (ApprovalSpike.swift:210-220); token advances per page, so an infinite loop requires server
   misbehavior. No page cap — add one in the Phase 3 non-throwaway version.
5. **TTLs defined but unenforced in spike**: `ApprovalConfig.requestTTL/responseTTL` unused;
   `ownerFetchRequest` can resurrect an already-approved stale request (`records.max` by
   creationDate; spike never deletes requests). Fine for spike; Phase 5 owner UI must enforce.
6. **`startOwner` rerun fails**: zone name persisted (ApprovalSpike.swift:58), so a second run saves
   a second zone-wide CKShare onto an already-shared zone → server error surfaced in `status`.
   Spike ergonomics only.
7. **Alert-push copy is English-only and lives server-side in the subscription**
   (ApprovalSpike.swift:89-91). DEBUG-accepted per plan, but Phase 3 must switch to
   `alertLocalizationKey` on `CKSubscription.NotificationInfo` for EN/VI.
8. Nits: pointless optional cast `request.recordID.zoneID as CKRecordZone.ID?`
   (ApprovalSpike.swift:126); `requestRecordName` not reset alongside `requestCommittedAt`
   (ApprovalSpike.swift:193) — harmless, guard requires both.

## Acceptance Criteria Verdicts

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| a | Approval pushes bypass `iCloudSyncEnabled`; never `.vaultRemoteChangePush` | PASS | AppPushKind.swift:19-23 routes `approval-req-*` / `approval-shared-db` to approval names; approval observers (ApprovalSpike.swift:37-45) never check the toggle |
| b | No sync-push regression | PASS | `vault-zone-changes` + nil/unknown IDs → `.vaultRemoteChange` (AppPushKind.swift:15-17,28); same post + `.newData` completion as before |
| c | No launch crash / no CloudKit at launch | PASS | All `CKContainer`s lazy (ApprovalSpike.swift:23, SharedZoneSubscriptionService.swift:16); didFinishLaunching adds only UN-delegate assignment; VaultSceneDelegate touches CK only inside accept callback |
| d | Opaque naming; no leaky push payload | PASS | `apz-` + 40-hex CSPRNG zone names (ApprovalConfig.swift:37-45); record names opaque; alert = static copy, zero payload keys (ApprovalSpike.swift:88-92) |
| e | Fail-closed gates | PASS | ApprovalPrerequisites.swift:20-40: isConfigured → `.available` → auth; `.denied`/`@unknown` → blocked; prompt only on `.notDetermined`. Requester side checks accountStatus only — acceptable (silent push needs no alert perm) |
| f | iOS 17.6 API floor | PASS | Everything used ≥ iOS 15/16: `CKShare(recordZoneID:)` 15.0, `CKRecordNameZoneWideShare` 15.0, `shareParticipant(forEmailAddress:)` 15.0, async CKDatabase APIs 15.0, `URL.documentsDirectory` + `ShareLink` 16.0 — no guards needed |
| g | MainActor default + explicit imports | PASS | Explicit CloudKit/Foundation/UserNotifications imports throughout; `nonisolated` on VaultifyCore types (ApprovalConfig.swift:9); compile green both slices |
| h | Existing patterns | PASS | Guarded-flag subscription mirrors SyncPushService 1:1; `@ObservationIgnored lazy` container matches CloudSyncService.swift:21 |
| i | No contract breaks; no RELEASE-shipped unlocalized strings | PASS | AppPushDelegate only gains conformances; all new UI/alert strings inside `#if DEBUG`; `CKSharingSupported: true` correct Boolean plist type |

Note: ApprovalConfig.swift lives in VaultifyCore → also compiles into the AutoFill extension
(Foundation + CryptoRandom only — harmless, intentional-looking).

## Positive Observations

- `AppPushKind.classify` defaults unknown IDs to sync-pull with the rationale documented inline —
  exactly the right fail-safe direction.
- Per-record error surfacing via `try result.get()` on `saveResults` in the spike catches CloudKit
  partial failures most spikes miss.
- Alert push carrying *no* payload (owner refetches from zone) is stronger than the plan's
  "requestOpaqueID only" — good deviation.
- Prereq check prompts for notification auth only on flow entry, never at launch (ADR-2 honored).

## Recommended Actions (priority order)

1. Fix the SharedZoneSubscriptionService doc comment (or wire the flag) — 1-line, do before commit.
2. Align macOS share-accept with iOS (post only on success) — 3 lines.
3. One cold-launch simulator smoke test for the scene-delegate injection.
4. Carry forward to Phase 3: push buffering for cold-launch taps, page cap in fetchAll successor,
   `alertLocalizationKey`; to Phase 7: approval-zone/subscription cleanup on Erase Vault.

## Metrics

- New/changed LOC: ~560 across 9 files
- File sizes: all new files ≤ 143 lines except ApprovalSpike.swift (241 — DEBUG throwaway, exempt)
- Localization debt shipped to RELEASE: 0

## Unresolved Questions

- Should `approvalModeEnabled` gate the spike section visibility now, or stay dormant until
  Phase 3 wires the real observer? (Plan step 7 implies the former.)
