# Verified Diagnosis — Approval Share "Stuck on Waiting" + Blind Pending

Date: 2026-07-08. Method: two parallel Explore scouts + direct code read of all cited files.
Confidence: 100% (source-verified).

## Symptoms (reported)
1. A shares to B; B accepts; A stays on "Waiting for them to accept…" forever.
2. During the wait, dismissing the popup or killing/relaunching the app leaves A blind — no
   indication the invite is pending, no signal when B accepts, needs a step to re-pair.
3. User suspected passkey items break sharing.

## Verified root causes

### Detection is single-path and fragile (Bug 1)
Owner learns of acceptance ONLY by polling a custom `participant-profile` record B publishes
after accepting. Full dependency chain (all verified):

- B accepts CKShare → sets `pendingShareAcceptanceKey` (`AppPushDelegate.swift:138`, **iOS only**).
- Resume needs B's vault UNLOCKED: `resumePendingShareAcceptance` guards `vaultKey`
  (`VaultShellBehaviors.swift:124-125`) → `completeAcceptance` → `publishProfile`
  (`ApprovalRecipientService.swift:123-127, 104`) writes to the shared DB.
- Owner polls `fetchParticipantProfile` from private DB (`ApprovalShareService.swift:133-142`),
  but the poll lives ONLY while `.waiting` is on screen, bounded ~80 tries/≈10 min
  (`ShareAccessSheet.swift:298-319`, driven by `.task(id: pollingZoneName)` at `:83-95`).
- Owner NEVER reads `CKShare.participants[].acceptanceStatus`.
- Owner subscription is deliberately scoped to `requestRecordType` only, NOT profile writes
  (`ApprovalShareService.swift:101-124`) → no push wakes A on acceptance.
- No foreground/unlock refresh targets pending outgoing shares — `refreshOwnerRequests`
  fetches `ApprovalRequest` (code-use) only (`VaultShellBehaviors.swift:70-74`).

**Failure modes that strand A on "Waiting":**
- B accepted but vault locked / never reached a resume surface → profile never published.
- A closed sheet / killed app / >10 min → poll dead; even a published profile is never seen.
- macOS acceptor: `userDidAcceptCloudKitShareWith` omits the breadcrumb
  (`AppPushDelegate.swift:170-181`) → resume only via visiting "Shared with Me".

### Pending state is ephemeral (Bug 2)
- Only persisted artifact: `ItemShareRecord(fingerprintConfirmed:false)` in UserDefaults
  (`SharingStore.swift:6-25, 63-67`). All tracking (`step`, poll, fetched profile) is sheet
  `@State` (`ShareAccessSheet.swift:26-52`) → lost on dismiss/kill.
- CKShare + zone + subscription persist server-side; dismiss does NOT cancel the share.
- Only surface for pending: a static "Pending" label inside the share sheet's config form for
  that one item (`ShareAccessSheet.swift:524-546`, label at `:529`). No management screen, no
  badge, no notification. `NotificationsScreen` shows incoming invites + code-use requests only.
- Resume forces re-typing the recipient email (`ShareAccessSheet.swift:225-231`).

### Passkey exonerated
Passkey is touched only in `confirmFingerprintAndPublish` → `publishGrant`
(`ShareAccessSheet.swift:351-367`), which runs AFTER acceptance is detected. `createShare` and
`fetchParticipantProfile` contain no passkey code. A passkey item cannot cause the "Waiting"
stall. (Separate, later failure: single-device + recipient without a device directory →
`Failure.recipientNeedsUpdate`, `ApprovalShareService.swift:166-168` — surfaces as a toast at
fingerprint-confirm, not a silent Waiting stall.)

## Fix direction (see plan.md)
1. Read `CKShare` acceptanceStatus as the authoritative accept signal; model accept vs
   profile-ready as two milestones. Refresh off-sheet on foreground/unlock. Fix macOS breadcrumb.
2. Surface + resume pending shares (NotificationsScreen, local notification, resume-from-record).

## Unresolved questions
- Confirm CloudKit propagation timing of B's shared-DB profile write into A's private DB in the
  production container (standard CKShare semantics assumed; verify during device QA).
- `ApprovalSpike.swift` defines a parallel `saveOwnerAlertSubscription` — confirm the live path
  before adding any accept subscription (Phase 2 stretch).
