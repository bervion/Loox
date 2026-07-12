# iCloud Invite → Accept → Status Flow Audit (Approval Mode)

Date: 2026-07-12 · Scope: owner-side acceptance detection, status surfacing, push/background, security, performance. READ-ONLY audit; no code changed.

---

## 1. Current flow (concise sequence)

**Owner A creates invite**
1. `ShareAccessSheet` → "Share with a Loox user" → prerequisites gate (iCloud available + notification permission, `Vaultify/Services/Sharing/ApprovalPrerequisites.swift:20-41`).
2. `createShare` (`Vaultify/Features/Sharing/ShareAccessSheet.swift:269-325`) → `ApprovalShareService.createShare` (`Vaultify/Services/Sharing/ApprovalShareService.swift:73-99`): per-recipient opaque zone `apz-…` + zone-wide CKShare restricted to looked-up email participant; owner ALERT subscription created — but scoped ONLY to `ApprovalRequest` record creation (`ApprovalShareService.swift:107-124`).
3. Pretty invite link minted (public DB), rendezvous drop into B's armed inbox if it exists (`InviteInboxService`), `SharingStore` record persisted at `.inviteSent` (`ShareAccessSheet.swift:314-319`), `approvalModeEnabled = true`.

**Recipient B accepts**
4. B gets push hint (`inviteRendezvousReceived`, public-DB `CKQuerySubscription`, `Vaultify/Services/Sharing/InviteInboxService.swift:100-111`) or taps link → `VaultSceneDelegate` accepts CKShare, sets resume breadcrumb BEFORE accept (`Vaultify/App/AppPushDelegate.swift:132-150`).
5. On unlock/foreground, `resumePendingShareAcceptance` (`Vaultify/Features/Main/VaultShellBehaviors.swift:148-187`): escrow identity → `publishProfile` into every accepted zone (6-attempt backoff — the shared-DB zone lags `container.accept`) → arm B's silent shared-DB subscription.

**Owner A learns of acceptance — POLLING ONLY**
6. In-sheet poll `pollForProfile` (`ShareAccessSheet.swift:349-378`): 80 attempts, 3s→10s backoff ≈ 10 min, bounded; profile fetch each tick; `CKShare.acceptanceStatus` checked only every 6th tick (~30-60s) via `participantAccepted` (`ApprovalShareService.swift:137-149`).
7. Off-sheet: `OwnerShareRefresher.refresh()` (`Vaultify/Services/Sharing/OwnerShareRefresher.swift:33-63`) fired on scene `.active`, shell `onAppear` (`VaultShellBehaviors.swift:75-97`), and Notifications screen `.task` (`Vaultify/Features/Sharing/NotificationsScreen.swift:92-98`). Profile found → `.readyForCeremony`; else share-accepted → `.accepted`. Monotonic store guard (`Vaultify/Features/Sharing/SharingStore.swift:99-105`, pinned by `VaultifyTests/ShareLifecycleStatusTests.swift`).
8. Manual "Check Now" (`ShareAccessSheet.swift:382-398`, `ShareResumeStepperSheet.swift:254-273`).

**Activation**
9. A confirms fingerprint (`TrustFingerprintView`) → `publishGrant` → `fingerprintConfirmed: true` → `.active` (`ShareAccessSheet.swift:400-447`). B's projection picks it up via silent shared-DB push / foreground (`Vaultify/Services/Sharing/SharedItemsProjection.swift:156-254`).

**Status surfaces today**
- Home: pending-share rows (`Vaultify/Features/Home/HomeScreen.swift:277-319`, orange = waiting on them, green = waiting on YOU) + approval attention row (`HomeScreen.swift:325-364`).
- Bell badge: invites + approval requests ONLY (`Vaultify/Features/Home/Components/HomeHeaderBar.swift:15-18`).
- Notifications screen: "Shares you sent" with per-state copy (`NotificationsScreen.swift:59-66,168-175`) + bounded history (`NotificationHistoryStore.swift`).
- Resume stepper: 4-step picture, reachable from Home/Item Detail/Notifications (`ShareResumeStepperSheet.swift`).

**Complete subscription inventory** (verified by grep — nothing else exists):
| Sub | DB | Fires for | Silent? |
|---|---|---|---|
| `vault-zone-changes` (`SyncPushService.swift:24`) | A private, Vault zone | vault-item sync only | yes |
| `approval-req-<zone>` (`ApprovalShareService.swift:112`) | A private, per apz zone | `ApprovalRequest` CREATE only | alert |
| `approval-shared-db` (`SharedZoneSubscriptionService.swift:24`) | B shared DB | owner writes (responses, edits) | yes |
| `loox-invite-inbox` (`InviteInboxService.swift:100`) | B public DB | invite drops to B | alert |

**Nothing pushes A when B accepts the CKShare or publishes `ApprovalParticipantProfile`.** The profile write lands in A's private DB approval zone, but A's only subscription there is the `ApprovalRequest`-scoped query sub (deliberately narrowed to kill phantom alerts, `ApprovalShareService.swift:101-106`). Acceptance detection is exactly the prior-bug fix (plan 260708-2151): polling, foreground-gated.

---

## 2. Friction points (UX), ranked

**F1 — CRITICAL: acceptance status is foreground-poll only; the "sit in the app" complaint is real.**
If A closes the app after inviting, NOTHING updates until A next opens it: no silent push (no subscription covers the profile record), no background refresh, no local notification. iOS never wakes the app. The "ambient status" on Home is a *cache of the last foreground poll*, not live state. `OwnerShareRefresher.swift:6-13` documents this as by-design gap-filling.

**F2 — HIGH: the UI promises a ping that does not exist.**
`ShareInviteSentSheet.swift:34`: *"No need to wait here. They'll get a notification, and we'll ping you the moment they accept."* Grep confirms zero local-notification scheduling anywhere in the sharing path (only rotation reminders use `UNUserNotificationCenter.add`). The promise is false today — worst kind of trust damage in a password manager.

**F3 — HIGH: bell badge ignores the one state that needs A's action.**
`HomeHeaderBar.swift:15-18` counts `pendingInvites + pendingOwnerRequests`. A share at `.readyForCeremony` (B did everything; A must confirm) does not badge the bell. A must scroll Home or open Notifications to discover it.

**F4 — MEDIUM: accepted → active limbo has no prompt.**
After B accepts, A must return for the fingerprint ceremony + grant publish. Until then B sees "The owner hasn't finished setting up this share yet" (`ApprovalRecipientService.swift:31`). With no notification (F1/F2), shares can sit in limbo for days. The ceremony being foreground-manual is correct (security); the *absence of a prompt* is not.

**F5 — MEDIUM: in-sheet acceptance feedback lags up to ~60s.**
`pollForProfile` checks `acceptanceStatus` only on `attempt % 6 == 5` (`ShareAccessSheet.swift:366-371`), so the "Accepted. Finishing on their device" copy switch lags the actual accept by 30-60s while the profile check runs every 3-10s. Poll exhausts silently after ~10 min except for one footnote (`pollExhausted`).

**F6 — LOW: share status is device-local.**
`SharingStore` persists to UserDefaults (`SharingStore.swift:72-73`); A's other devices (iPad/Mac plan) will show nothing about outgoing shares.

---

## 3. Security findings (severity-ranked)

**S1 — MEDIUM-HIGH: recipient auto-TOFU pins the owner key with no verification.**
`SharedItemsProjection.swift:176-179`: *"Auto-TOFU pin on first sight (single-confirm pairing model)"* — B pins `grant.ownerSigningPubKey` from whatever grant appears in the zone, before any human check. The fingerprint ceremony is one-sided: only A compares the code; B's `safetyCode` is an optional detail-row (`SharedItemsProjection.swift:69-75`). Failure scenario: A's iCloud account (or CloudKit itself) is compromised between B's accept and B's first fetch → attacker publishes their own grant → B pins the attacker's key, decrypts attacker-sealed values, and sends future `askEachTime` requests attacker-verifiable. The pin does reject later key *changes*, and A's side independently verifies requests against A's own device identity (`ApprovalCoordinator.swift:86-94`), so the attacker can't extract A's secrets — the exposure is B trusting spoofed content/responses. Likely an accepted trade-off; it should be an *explicit* one (documented threat-model note or an optional recipient-side code-compare step).

**S2 — MEDIUM: `publishProfile` read-modify-write race can silently drop a device.**
`ApprovalRecipientService.swift:84-108`: fetch existing profile → merge own signing key + HPKE entry → save with `.allKeys`. `.allKeys` ignores the server change tag, so two of B's devices publishing concurrently (both resuming acceptance after the same invite) last-writer-wins: the loser's directory entry is erased. Consequence: single-device grants sealed to a vanished device key (INV-04 promise breaks in the *availability* direction — recipient gets Tier-0 placeholder, no error). Fix: `.ifServerRecordUnchanged` + conflict-retry merge loop.

**S3 — LOW: unauthorized-acceptance surface is properly closed.** CKShare participant is a looked-up identity with `publicPermission = .none` (`ApprovalShareService.swift:84-92`) — only the addressed iCloud account can accept; no bearer-URL semantics. Good.

**S4 — LOW: push payloads are hint-only and verified-before-show.** Routing is by subscription-ID prefix (`AppPushKind.swift:15-33`); the inbox refetch runs the full kernel verifier before any UI, with a non-burning `PreviewNonceStore` (`ApprovalCoordinator.swift:82-99`). Replay is closed by the authoritative create-if-not-exists nonce record (`ApprovalShareService.swift:422-458`) plus the 120s lifetime clamp and fail-closed checks in `ApprovalVerifier.swift:82-150`. Solid.

**S5 — INFO: `SharingStore` keeps recipient email ↔ item-id mappings plaintext in UserDefaults.** Consistent with the stated M2 model (labels never leave the device, CloudKit sees opaque names) — acceptable, worth a line in the threat model.

**S6 — INFO: LWW on singleton records is deliberate** ("singleton naming gives last-writer-wins conflict election for free", `ApprovalConfig.swift:33-35`). Fine for owner-written singletons (one writer); it is exactly what makes S2 bite on the *multi-writer* profile record.

---

## 4. Performance findings

**P1 — `refreshOwnerRequests` does a full zone scan per owned zone on EVERY foreground + shell appear + Notifications visit** (`VaultShellBehaviors.swift:75-97`, `ApprovalCoordinator.swift:69-112`). `fetchLiveRequests` uses stateless `ZoneDeltaFetch.pull(cursor: nil)` (`ApprovalShareService.swift:322-330`) which pages ALL records in the zone — grant, display envelope, every sealed field blob, nonce markers — just to find request records. N active shares → N full-zone scans per app activation, ~always yielding zero requests (requests have a 120s TTL). A `CKQuery` on `requestRecordType` or a delta cursor dedicated to requests would cut this to near-zero.

**P2 — In-sheet poll: up to ~80 CloudKit fetches per invite** while the waiting sheet is open (`ShareAccessSheet.swift:353`); push (R1) makes it redundant.

**P3 — `OwnerShareRefresher.refreshAll` is serial** — up to 2 round trips per unconfirmed share, one at a time (`OwnerShareRefresher.swift:44-49`). Fine for N≤3; `withTaskGroup` if pending lists grow.

**P4 — Main-thread: acceptable.** Services are `@MainActor` but CloudKit ops run internally off-main behind `await`; only trivial JSON persistence executes on main.

**P5 — `publishGrant`/`republishSharedValues` full-zone GC scans** (`ApprovalShareService.swift:253,300`) — low frequency, acceptable.

---

## 5. Concrete optimization recommendations

**R1 (core, fixes F1): add an owner-side silent push for acceptance.**
In `createShare` (`ApprovalShareService.swift:95`, next to `saveOwnerAlertSubscription`), also save a **silent** `CKQuerySubscription` on `participantProfileRecordType` `.firesOnRecordCreation` (per zone, id prefix e.g. `approval-accept-<zone>`), `shouldSendContentAvailable = true`. Add a case to `AppPushKind.classify` (`AppPushKind.swift:15`) → new `Notification.Name.shareAcceptanceHint` → observer calls `env.ownerShareRefresher.refresh()`. Being silent it cannot recreate the phantom-alert problem the request sub was narrowed for (`ApprovalShareService.swift:101-106`); background modes (`remote-notification`, `Project.swift:95`) and `registerForRemoteNotifications` (`AppPushDelegate.swift:20`) are already in place, so this works with the app backgrounded/killed-by-user-not. Optionally also a second silent query sub on `CKShare` acceptance isn't available — profile creation is the right (and sufficient) trigger since it's what unblocks the ceremony. Delete both subs in `revoke` (`ApprovalShareService.swift:385-397`).

**R2 (fixes F2/F4): post a LOCAL notification when status advances.**
In `OwnerShareRefresher.refreshAll` (`OwnerShareRefresher.swift:44-49`), when `resolveStatus` advances a record to `.readyForCeremony` (and the app is backgrounded), schedule a `UNUserNotificationCenter` local notification: "<recipient> accepted. Tap to finish setting up the share." Notification permission is already guaranteed by `ApprovalPrerequisites` before any share exists. Tap-routing → open `ShareResumeStepperSheet` for that zone (mirror the existing `NotificationsRoute` pattern). This is what makes the `ShareInviteSentSheet.swift:34` promise true. R1+R2 together = fully ambient: A locks phone, gets a banner when B accepts, taps, confirms code, done.

**R3: fix the copy** at `ShareInviteSentSheet.swift:34` if R1/R2 don't ship in the same release — do not promise a ping that doesn't exist (EN + VI both).

**R4 (fixes F3): include actionable shares in the bell badge.** `HomeHeaderBar.swift:15-18`: add `env.sharingStore.shares.filter { $0.status == .readyForCeremony }.count`.

**R5 (fixes P1): stop full-zone-scanning for requests.** Replace `fetchLiveRequests`'s zone pull with `CKQuery(recordType: requestRecordType)` scoped to the zone, or short-circuit `refreshOwnerRequests` when no `approvalRequest` push was received since the last pass (dirty-flag set by `AppPushDelegate.route`). Keep one unconditional pass per cold launch as the missed-push safety net.

**R6 (fixes S2): make `publishProfile` conflict-safe.** `ApprovalRecipientService.swift:106`: save with `.ifServerRecordUnchanged`; on `serverRecordChanged`, refetch, re-merge (`ParticipantProfileMerge` already exists), retry (bounded).

**R7 (improves F5): react to push while the sheet is open.** Have `pollForProfile` also listen for the R1 hint (or simply check `participantAccepted` every tick — it's one record fetch) so the "Accepted" copy flips within seconds; with R1 the 10-minute budget can drop to ~2 minutes of fallback polling.

**R8 (F6, later): sync `ItemShareRecord` status cross-device** once the iPad/Mac plan lands — piggyback on the existing vault sync channel or derive purely from CloudKit state on each device (zone list + profile presence), which needs no new storage.

**R9 (S1, decide): either add an optional recipient-side "compare the safety code before first use" interstitial, or record the one-sided-ceremony trade-off explicitly** in `docs/` threat-model notes so audits stop re-flagging it.

---

## Open questions

1. Is the one-sided fingerprint ceremony (recipient auto-TOFU, S1/R9) a user-confirmed product decision, or drift? Memory notes lean "single-confirm pairing model" as chosen, but no doc states the threat trade-off.
2. Should R2's local notification fire also for `.accepted` (B accepted, device still finishing) or only `.readyForCeremony`? Two banners for one accept may feel noisy; recommend readyForCeremony-only.
3. Priority of R8 (cross-device share status) relative to the iPad/Mac multiplatform plan — currently moot on iPhone-only.
4. `ApprovalSpike.swift` still ships a `CKRecordZoneSubscription` code path (spike file, 289 lines) — dead-code removal candidate; confirm nothing references it at runtime.

**Status:** DONE
**Summary:** Owner-side acceptance detection is poll-only (no push subscription covers profile publish); report delivers push-driven ambient-status design + 2 security fixes.
