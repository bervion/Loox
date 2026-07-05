# Code Review — sharing v1.1 rendezvous batch (d27b9ab^..HEAD, 14 commits)

Branch: `feat/sharing-v11-invite-deeplink` · Reviewer: code-reviewer · Date: 2026-07-05
Compile: **SUCCEEDED, 0 warnings** (tuist generate + xcodebuild Debug, generic iOS Simulator).
Localization: all 23 new user-facing keys verified present in `Localizable.xcstrings` with non-empty VI (incl. `invite.push.title/body`, the `%@` iMessage body key, and `%@ has joined…`). No case-variant dupes.

## Invariant scorecard (plan USER-LOCKED)

| # | Invariant | Verdict |
|---|-----------|---------|
| 1 | No PII in public DB; 256-bit inboxID; descriptor keyed by opaque userRecordID | PASS (`InviteInboxService.swift:58,185-187`) |
| 2 | CKShare URL only inside sealed envelope | PASS (drop carries `blob` ciphertext only) |
| 3 | Missed push must not lose an invite; persisted dedup | **PARTIAL — H2** (seen-set persisted before surfacing) |
| 4 | Sign-then-seal, inboxID-bound info, 24h–7d at mint AND open, fail-closed | PASS (`InviteEnvelope.swift:98-133`; tests cover all branches) |
| 5 | Gate on `approvalModeEnabled`, never `iCloudSyncEnabled` | PASS (`InviteInboxBehaviors.swift:70`; grep clean) |
| 6 | Creator-only public-DB deletes; recipient dedups | PASS (recipient never deletes; sender GCs at activate/revoke) |
| 7 | No regression to ceremony/sync stack | PASS (owner sheet still decoupled-@State; sync untouched) |
| 8 | MainActor/SwiftUI state races | **FAIL — H1** (invite alert binding) |
| 9 | Localization EN+VI | PASS |

## High

**H1 — Invite alert re-presents during in-flight accept; double-`advance()` silently drops a queued invite.**
`Vaultify/Features/Sharing/InviteInboxBehaviors.swift:43-66`.
`invitePresented` is a computed Binding whose `set` is a no-op; "Accept" spawns a Task and only calls `advance()` after `await acceptShare` returns. After the button tap SwiftUI sets the binding false (no-op) and re-reads `get` — still true (pendingInvites unchanged, acceptError nil) → the SAME invite alert re-presents while the accept is in flight. Scenario: tap Accept → alert reappears → tap "Not Now" → `advance()` removes invite A; the in-flight Task's `advance()` then does `removeFirst()` again → invite B is removed without ever being shown, and it is already in the persisted seen-set → permanently lost. Double-Accept is server-benign (`.alreadyShared` tolerated, `InviteLinkService.swift:143`) but other failures produce spurious error alerts.
Fix: drive the alert off an explicit `@State presentedInvite: InviteEnvelope?` (Phase-5 pattern already used for `presentedApproval`); remove by `inviteID` (`pendingInvites.removeAll { $0.inviteID == invite.inviteID }`), never `removeFirst()`; keep the alert down while an accept is in flight.

**H2 — Seen-set persisted BEFORE the invite is ever shown → lock/relaunch permanently loses the invite.**
`Vaultify/Services/Sharing/InviteInboxService.swift:117-121` + `InviteInboxBehaviors.swift:14` (`@State pendingInvites`).
`reconcile` writes the dedup set to UserDefaults before returning; the only surfacing is in-memory `@State` on the unlocked shell. Lock-on-background (default ON) recreates the shell → `pendingInvites` gone; the next reconcile skips the drop (seen). The drop still sits on the server but the recipient can never see it again, and the owner's UI now says the link is "just a backup". Violates invariant 3 in spirit; "Not Now" as permanent dismiss is a choice, but losing an invite with NO user decision is not.
Fix: persist seen only on user action (Accept/Not Now); dedup the surfacing queue in-memory per session, or persist the pending queue alongside the seen-set.

**H3 — Cold-launch invite link likely dropped: NotificationCenter post before any subscriber exists.**
`Vaultify/App/AppPushDelegate.swift` (`scene(_:willConnectTo:)` → `forwardInviteLink` → post `.inviteLinkReceived`) vs `Vaultify/App/VaultifyApp.swift` (`.onReceive`).
`willConnectTo` runs during scene connection, before SwiftUI installs the content view's `onReceive` subscription; a synchronous post there is fire-and-forget → the cold-tap path (app killed, user taps invite link) very likely does nothing, silently — exactly the failure the commit claims to fix. Warm path (`scene(_:continue:)`) is fine.
Fix: buffer instead of post — stash the URL in a static `pendingInviteURL`, drain it from a `.task` on the root view (also keep the post for the warm path). Verify on device either way; the buffer removes the ordering dependence for ~5 lines.

## Medium

**M1 — Envelope's documented participant cross-check is not implemented; unauthenticated one-tap join.**
`VaultifyCore/Sharing/InviteEnvelope.swift:22-24` promises "the acceptor cross-checks the fetched share metadata actually matches who this invite claims (U7)". `InviteInboxBehaviors.acceptFirst` (`:52-67`) calls `acceptShare(url:)` which fetches metadata and accepts — no comparison of `envelope.recipientParticipantID` to own `userRecordID`, nor `envelope.ownerParticipantID` to the share's owner identity. Anyone knowing the recipient's email can resolve their userRecordID → descriptor → seal a drop → OS push + "Share invitation" alert naming no sender → one tap joins the attacker's zone (followed by auto-TOFU pin + profile publish into it). Same write-only-contract class as the display-envelope `revision` field.
Fix: implement the cross-check in the alert accept path (fail → drop silently or "invitation not addressed to this account"), and consider carrying a claimed sender label into the alert copy (explicitly unverified).

**M2 — SharedWithMeScreen burns the acceptance breadcrumb even when completion failed.**
`Vaultify/Features/Sharing/SharedWithMeScreen.swift` `load()`: `try? completeAcceptance(...)` then unconditional `removeObject(forKey: pendingShareAcceptanceKey)`. One offline visit deletes the flag → the shell's `resumePendingShareAcceptance` (which correctly keeps the flag on failure, `VaultShellBehaviors.swift:106-117`) never retries → owner's waiting screen finds no profile unless B happens to revisit this screen online.
Fix: only remove the key after `completeAcceptance` succeeds (mirror the shell's do/catch).

**M3 — `handledRequestIds` is per-session; failed best-effort delete re-presents an answered request after relaunch.**
`Vaultify/Services/Sharing/ApprovalCoordinator.swift` (in-memory Set) + `ApprovalShareService.respond()` (`try?` delete). Offline-at-respond: response saved later? — no: if respond succeeded but the follow-up delete failed, relaunch re-verifies the record (nonce still displays), sheet re-presents; re-approving fails verification with a confusing error. TTL eventually clears it. Growth of the set itself is trivially bounded (per-session).
Fix: persist handled ids (small capped array in UserDefaults, same pattern as the invite seen-set) or have the verifier treat an existing response record for the requestId as handled.

**M4 — Same-Apple-ID multi-device flap: descriptor + subscription are account-scoped, inboxID is device-scoped.**
`InviteInboxService.ensureArmed`: inboxID lives in UserDefaults (per device), descriptor recordName is per account, and CK subscriptions are per (container, db, account). Second device arms → `.allKeys` overwrites the descriptor and delete-then-save replaces the one shared subscription with ITS inboxID → drops now address only the last-armed device; the other device reconciles a stale inboxID forever and its sealed drops (bound to the old inboxID via HPKE info) can never open. iPhone-only today, but the iPad/Mac plan (260704-1751) makes this real soon.
Fix (later phase is fine): read-back the server descriptor's inboxID instead of overwriting when the record exists and carries a valid self-signature over the same identity keys, or make the inbox key material account-derived (escrowed) rather than device-random.

**M5 — `sentAtMs` stores the exact mint timestamp while the same code comments "coarse timing only" and hour-coarsens `expiresAtMs`.**
`InviteInboxService.swift:171-173` vs class doc `:11-12`. The field is never read by the recipient (ordering uses envelope `createdAtUnixMs`). Self-contradictory privacy contract; note CK's own record `creationDate` is exact regardless, so either coarsen both and document the CK caveat, or drop the field.

## Low

- **L1** `Array(seen.suffix(200))` (`InviteInboxService.swift:120`) — `Set` is unordered; "capped FIFO" comment is false. Eviction is arbitrary once >200 lifetime invites and could evict a live inviteID (re-prompt while its ≤7d drop persists). Persist an ordered `[String]` and append/trim on that.
- **L2** `InviteEnvelope.decode` (`InviteEnvelope.swift:73-91`) tolerates trailing bytes — every other wire decoder (`ApprovalCanonical.swift:198,248,292`) enforces `r.isAtEnd`. Not a forgery vector (AEAD-sealed; signature covers all semantic fields; dedup key covered) but breaks canonical-encoding hygiene. One-line `guard r.isAtEnd else { throw Failure.malformed }`.
- **L3** DEBUG spike shares the production descriptor recordName, record type, AND `inviteInboxSubscriptionID` (`InviteRendezvousSpike.swift:58-59,79-83`) with a different UserDefaults key — running "Arm invite inbox" on a dev device overwrites the real descriptor minus `encryptionKey`/`signingKey` (auto-invite to that account fails; senders address the spike inboxID) until the next real `ensureArmed` pass. Namespace spike records (`spike-inbox-…`) or delete the spike now that Phase 3 is proven.
- **L4** `confirmFingerprintAndPublish` final upsert (`ShareAccessSheet.swift:280-283`) drops `inviteRecordName`/`dropRecordName`; if either best-effort delete failed, the names are lost and `revoke()` can no longer GC them — covered only by the 7d expiry-in-client (records themselves persist server-side; known GC-gap class).
- **L5** "Check Now" (`ShareAccessSheet.swift:234-242`) silently no-ops on offline/no-profile (`try?` guards) — no feedback distinguishes "not accepted yet" from "network failed".
- **L6** `pollExhausted` never resets when a new `.waiting` poll starts (Try Again → new zone) — stale "Still waiting" hint. Reset it at `createShare`/`.task(id:)` entry.

## Scrutinized items with NO finding

- `ensureArmed` latch: set only after full success; failures retry next pass — correct. `.allKeys` bypasses the oplock so the descriptor re-publish is genuinely idempotent; delete-then-save subscription window is benign (push = hint).
- `respond()` delete-after-save: idempotent (response re-save `.allKeys`; delete of a gone record is `try?`); recipient poll never depends on the request record. Ordering is safe — response exists before the request disappears.
- `dropInvite` email: `shareParticipant(forEmailAddress:)` NSException-on-empty trap is guarded — the only caller passes `normalizedEmail`, and Create Share is `.disabled(!recipientEmail.contains("@"))` (`ShareAccessSheet.swift:349`); no empty-string path.
- Owner sheet dual-trigger (`onAppear` + `onChange`): `presentNextApprovalIfIdle` guards on `presentedApproval == nil` — no double-present.
- `navigationDestination` moves: `SharedWithMeRoute`/`SharedZoneRoute` now registered exactly once per stack root inside `vaultNavigationDestinations()`; old in-screen registrations removed (HomeScreen, SharedWithMeScreen). No duplicates; compile shows zero warnings.
- Poll loop applies both prior lessons: `.task(id: pollingZoneName)` structural cancellation + explicit `Task.isCancelled` check before each iteration.
- Owner alert subscription fix (zone-wide → `CKQuerySubscription` on ApprovalRequest creation) is the right shape and includes the delete-then-save migration for the previously deployed zone-wide sub. Note: migration only runs when `createShare` re-runs for that zone — pre-existing active shares keep phantom alerts until then (pre-release, acceptable).
- `CKRecordZone.ID(zoneName:)` one-arg uses are all owner-side private DB (correct); recipient side threads full `route.zoneID`.
- Alert-accept downstream chain verified end-to-end: `acceptShare` sets breadcrumb + posts `.vaultShareAccepted` → coordinator bumps `recipientChangeCounter` → shell `.task(id:)` resumes escrow/profile publish.
- Single-confirm pairing (recipient auto-TOFU-pin, owner one-tap activation) is a user-locked model change per commit d5fd430 — reviewed for implementation correctness only: key CHANGE still rejected, safety code retained for out-of-band comparison. Not re-litigated.

## Positive observations

- `InviteEnvelopeTests` are genuinely good: mint AND open lifetime enforcement, boundary values, inbox-binding, tamper, claimed-vs-actual signer mismatch.
- Fail-closed discipline in `InviteEnvelope.open` (decrypt → shape → policy → signature → expiry, each terminal) matches the plan exactly.
- The seal binds ciphertext to the target inboxID via HPKE info — drop-copy and inbox-rotation replay are dead by construction.
- Doc comments consistently carry the *why* (creator-only deletes, push-as-hint, TOFU boundary), which made this review materially faster.

## Recommended actions (priority order)

1. Fix H1 (explicit presented-invite state + remove-by-id) and H2 (persist seen on user action) together — same file pair, same test pass.
2. Buffer the cold-launch invite URL (H3) and device-verify cold + warm taps.
3. Implement the U7 metadata cross-check (M1) before shipping the rendezvous tier.
4. M2 one-line guard; M3 persist handled ids; sweep M5/L1/L2 as a small hygiene commit.
5. Defer M4 to the multiplatform plan but record it there now.

## Unresolved questions

- H3 ordering (willConnectTo vs onReceive subscription) is high-confidence from UIKit/SwiftUI lifecycle but not device-verified here — the buffering fix is warranted regardless.
- Is "Not Now" intended as a PERMANENT dismiss (current behavior once seen-set persists)? If it should be "later", H2's fix must also not persist on Not Now.

**Status:** DONE
