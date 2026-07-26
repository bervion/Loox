# Ghost "Shared item" on Home — root cause + cleanup

Date: 2026-07-26 · Repo: `/Users/bervion/Developer/Projects/mobile/ios/Vaultify` · Read-only audit.
Scope: issue 4 only (permanent "Shared item" / "Mục được chia sẻ" row). App Attest and the missing
`VaultPasskey` schema are diagnosed elsewhere and are **not** on this causal path.

---

## 1. Verdict

**The row is not stored on the phone. It is a live read of the user's iCloud *shared* database, and
the app has no durable way to say "I left".** `SharedItemsProjection` rebuilds Home's shared rows on
every unlock from `container.sharedCloudDatabase.allRecordZones()` filtered to the `apz-` prefix
(`ApprovalRecipientService.swift:51-57`), which is **iCloud-account state owned by the other Loox
account** — that is why deleting the app, reinstalling from scratch, and even Erase Vault change
nothing (**half a**: no code path in the repo ever enumerates or deletes a shared-DB zone on erase —
`AppEnvironment.eraseEverything` only drops the *private* "Vault" zone and revokes *owner* zones from
a UserDefaults registry, `AppEnvironment.swift:329-363`), and why both devices agree. **Half b** is a
separate defect stacked on top: "Leave Share" is a one-sided, **unverified** delete of the recipient's
mirror — `ApprovalRecipientService.leave` discards CloudKit's per-zone `deleteResults`
(`:263-266`), the confirmation refresh that follows is documented as possibly being a single-flight
no-op (`SharedItemsProjection.swift:122-124` + the `!refreshing` guard at `:194`), and the same call
`clearPin`s the zone — deleting the *only* local state that distinguished a seen zone from a new one.
So a leave that never landed server-side still reports success and clears the row optimistically;
the next unlock / foreground / silent push re-enumerates the surviving zone, `verifyGrant` passes on
the grant's own self-signature because the pin is now nil (`ApprovalVerifier.swift:57-72`), the
auto-TOFU block silently **re-pins and re-adopts** it (`SharedItemsProjection.swift:227-243`), and an
identical generic row is rebuilt. There is **no tombstone anywhere in the codebase** for a left or
declined share, so re-adoption is byte-for-byte indistinguishable from a first acceptance. The title
reads the literal constant `appString("Shared item")` (`SharedItemsProjection.swift:469-471`) because
the reinstalled vault can no longer open the display envelope — new `ParticipantIdentity` for a v1
grant, or `deviceNotAuthorized` for a v2 device-bound grant. **The authoritative fix is owner-side:
the master copy is the owner's private-DB zone (`ApprovalShareService.swift:73-97`), and only
`revoke(zoneName:)` deleting that zone (`:466-469`) removes the recipient's mirror for good.**

---

## 2. Causal chain (file:line)

### Half (a) — survives delete-app → fresh install → set up from scratch

| # | Step | Evidence |
|---|------|----------|
| 1 | Home pools shared projections unconditionally into the item list | `Vaultify/Features/Home/HomeScreen.swift:74` — `env.repository.allItems(folder:) + env.sharedItems.items` |
| 2 | The projection refresh runs on every unlocked-shell pass, **not** gated by `approvalModeEnabled` or `iCloudSyncEnabled` | `Vaultify/Features/Main/VaultShellBehaviors.swift:129-135` (`.task(id: recipientChangeCounter)`); only guard inside is `CloudSyncService.isConfigured` (`SharedItemsProjection.swift:194`), compile-time true under `VAULTIFY_ICLOUD` |
| 3 | Its zone list is raw account state | `ApprovalRecipientService.swift:51-57` — `container.sharedCloudDatabase.allRecordZones()` filtered by `ApprovalConfig.zonePrefix` |
| 4 | Nothing on the device owns that list. Erase Vault deletes only the **private** "Vault" zone and revokes only *owner* zones read from `UserDefaults` | `AppEnvironment.swift:329-363`; `CloudSyncService.swift:91` (private DB); `ApprovalShareService.swift:44-56` (`approval_owner_zone_names` in UserDefaults) |
| 5 | The only recipient-side zone delete in the whole repo is per-item | `ApprovalRecipientService.swift:263-266`, reached only from `ItemDetailScreen.swift:341-350` |
| 6 | On the fresh install the pin is gone, so `verifyGrant` checks only the grant's self-signature → a still-live grant verifies | `ApprovalVerifier.swift:57-72` (nil pin skips the pin check) |
| 7 | The zone is silently auto-TOFU-re-pinned, no prompt | `SharedItemsProjection.swift:227-243` |
| 8 | Values/display fail to open under the new identity → generic title, zero fields | v1: `ApprovalRecipientService.swift:379-392` / `:415-420` (`try?` swallows); v2: `:363-372` throws `deviceNotAuthorized` → `SharedItemsProjection.swift:272-279` Tier-0 |
| 9 | Fallback title is a hardcoded constant | `SharedItemsProjection.swift:468-471` — `display?.title.isEmpty == false ? display!.title : appString("Shared item")` |

**Consequence:** a visible ghost row is *proof* that at least one accepted `apz-` zone with a live,
signature-verifying `ApprovalGrant` still exists in the account's shared database. It cannot come
from a stale local snapshot on a from-scratch install: `seedFromSnapshot` reads the App Group
container (`SharedItemsProjection.swift:158-176`, `SharedConfig.containerURL`), destroyed on
uninstall, and it is AES-GCM-sealed under the *old* Vault Key anyway.

### Half (b) — leaving removes it, it silently returns

| # | Step | Evidence |
|---|------|----------|
| 1 | User confirms "Leave Share" | `ItemDetailScreen.swift:313-321` → `:341-350` |
| 2 | Zone delete on the shared DB; **per-zone result discarded** — only operation-level errors throw, a per-zone failure is invisible and unlogged (no `LEAVE` diagnostic exists) | `ApprovalRecipientService.swift:263-266` — `_ = try await sharedDatabase.modifyRecordZones(saving: [], deleting: [zoneID])` |
| 3 | `clearPin` deletes both the pinned owner key **and** the verification marker — the zone is now indistinguishable from a never-seen share | `ApprovalRecipientService.swift:219-223`, called at `:265` |
| 4 | Row removed optimistically, snapshot + AutoFill cache rewritten, UI reports success | `SharedItemsProjection.swift:125-131` |
| 5 | The "confirmation" refresh **can be a no-op** — the author documents this | `SharedItemsProjection.swift:122-124` ("a concurrent shell refresh would make the follow-up refresh below a single-flight no-op") + `:194` `guard CloudSyncService.isConfigured, !refreshing else { return }` |
| 6 | Later: foreground, unlock, or a silent shared-DB push bumps `recipientChangeCounter` → refresh | `AppPushKind` → `ApprovalCoordinator.swift:97-101`, `:200-202`; `VaultShellBehaviors.swift:129-135`; also `SharedWithMeScreen.swift:34` |
| 7 | Surviving zone re-enumerates; pin is nil (step 3) so the stale grant verifies again | `ApprovalVerifier.swift:57-72` |
| 8 | Auto-TOFU **re-pins**, writes a fresh `pending` marker, rebuilds the identical row, re-persists the snapshot | `SharedItemsProjection.swift:227-243`, `:311-328` |
| 9 | No tombstone exists to veto step 8 | grep: tombstones exist only for vault items/folders/personas/aliases; nothing for shared zones, declined invites, or left shares |

**Ruled out as the return mechanism** (checked, not assumed): every `container.accept` site needs an
explicit user gesture — `AppPushDelegate.swift:212` and `:257` (system share-URL tap),
`InviteLinkService.swift:160` (universal-link tap), `InviteInboxCoordinator.swift:65-75` (tapped
Accept button). `createShare` has three call sites, all behind a Button
(`ShareAccessSheet.swift:590`, `ShareSpaceSheet.swift:234`, `ShareResumeStepperSheet.swift:234`).
`OwnerShareRefresher` is read-only. The rendezvous inbox cannot silently re-discover old invites:
`invite_inbox_id_v1` lives in `UserDefaults` (`InviteInboxService.swift:312-317`), so a reinstall
mints a **new** inbox ID and old public `LooxInvite` drops are orphaned.

**Two sub-cases remain, both consistent with the evidence and indistinguishable without device logs
(inference — I cannot read CloudKit server state):**
- **b1 — the delete never landed.** Per-zone failure swallowed at `:264`. Most likely given the
  symptom shape (gone, then back later rather than "the button does nothing").
- **b2 — sibling orphan zones.** The user re-invited many times while debugging; each `createShare`
  without `existingZoneName` mints a **new** zone (`ApprovalShareService.swift:74-81`), and each
  accept adds one to the shared DB. Zones whose grant fetch throws (`grantMissing`, throttle,
  offline) contribute nothing on that pass (`SharedItemsProjection.swift:245-259`) and then surface
  later as an *identical* "Shared item" row, because the title is a constant. Note item ids embed
  `grantId` (`VaultifyCore/Models/SharedOrigin.swift:38`), so N live grants = N distinct rows — count
  the rows to discriminate.

Both are fixed by the same thing: delete the **owner's** zone.

---

## 3. Cleanup the user can run today (ranked by safety)

> **First, blunt truth:** Erase Vault will **not** help and is pure downside here — it deletes the
> private "Vault" zone including the recovery-key envelope (`AppEnvironment.swift:329-331`,
> `CloudSyncService.swift:89-96`) and does not touch a single shared zone. Same for "Delete Data from
> iCloud" on the *recipient's* account: shared zones bill to the owner, not to the participant.
> Turning off Approval Mode or iCloud Sync will also not hide the row — the refresh is gated by
> neither (`VaultShellBehaviors.swift:129-135`, `SharedItemsProjection.swift:194`).

> **Also blunt:** the in-app Share Diagnostics panel (which prints the `ZONES` line listing every
> shared-DB zone, `ApprovalRecipientService.swift:53-55`) is behind `#if DEBUG`
> (`SettingsScreen.swift:174-177`). **It is not reachable on the TestFlight build.** To read zone
> names today you need a Debug build from Xcode on the device.

**Step 0 — observe before acting.** [blast radius: none]
Count the ghost rows on Home / "Shared with Me". One row = one live grant. Two or more = sub-case b2
(multiple orphan zones), and you must leave every one of them. Note whether the user's account is the
**recipient** here, and which account is the **owner** (the other Loox account they shared to).

**Step 1 — repeat the leave, and verify with a Debug build.** [blast radius: exactly the shared zones;
never touches VaultStore, backups, or the private "Vault" zone]
Both devices online, one at a time, other device force-quit (two projections racing is what makes the
confirmation refresh a no-op). Open each shared row → "…" → **Leave Share** → confirm. Force-quit,
reopen, wait for a refresh, re-check. If you can run a Debug build: Settings → Share Diagnostics, read
the `ZONES` line (`sharedDB total=… approval=…`) immediately before and after each leave. **If
`approval=` does not decrease, sub-case b1 is confirmed outright** and no amount of tapping Leave will
ever fix it — go to Step 2.

**Step 2 — owner-side revoke (the authoritative fix).** [blast radius: that one share only; the
owner's vault and every other share are untouched]
On the **owner** device (the other Loox account), open the shared item → share button → Share access →
the recipient row → **Revoke access**. This runs `ApprovalShareService.revoke(zoneName:)`
(`:466-479`), which deletes the owner's private-DB zone — that removes the CKShare, every
grant/blob/request/response in it, the alert subscriptions, and the recipient's shared-zone mirror.
The recipient's row disappears on the next refresh. Callers: `ShareAccessSheet.swift:157`,
`ShareRecipientDetailSheet.swift:256`, `ShareResumeStepperSheet.swift:279` — all driven by the local
`SharingStore`.

**Step 3 — if Step 2 shows nothing to revoke.** This is the expected state if the owner device was
also deleted/reinstalled: owner zone names live only in `UserDefaults`
(`approval_owner_zone_names`, `ApprovalShareService.swift:44-56`) and the revoke UI reads the local
`SharingStore` — both wiped by reinstall. **The app then has no way to see, let alone delete, its own
zones.** Options, safest first:

- **3a — one-off Debug build on the owner device** [blast radius: exactly the `apz-` zones]. Sign into
  the owner iCloud account, run a Debug build, and once enumerate
  `CKContainer(identifier: "iCloud.com.bervion.vaultify").privateCloudDatabase.allRecordZones()`,
  deleting only zones whose `zoneName.hasPrefix("apz-")`. **Never delete the zone named `Vault`** —
  that is the vault mirror + recovery-key envelope + participant escrow.
- **3b — CloudKit Console, owner account** [blast radius: whatever you delete]. Production →
  `iCloud.com.bervion.vaultify` → Records, switch the database to Private and the account to the
  owner's, and delete the `apz-…` zones. *Unverified from here:* I could not confirm the current
  Console exposes per-zone delete for a private database in this build of the web console. Check; if
  the affordance is absent, use 3a.
- **3c — last resort, owner account only** [blast radius: the owner account's **entire** container
  private DB — sealed item mirror, recovery envelope, device registry, participant escrow, every
  `apz-` zone]. iOS Settings → Apple Account → iCloud → Manage Account Storage → the Vaultify/Loox
  entry → Delete Data from iCloud. The owner's on-device vault survives; its iCloud recovery does
  not. Only acceptable if the owner account is a throwaway test account. *Menu wording varies by iOS
  version; unverified from here.*

**Step 4 — only if a row survives Step 2/3.** [blast radius: the recipient device's local caches]
That means a sealed snapshot is being re-appended by the `grantMissing` fallback
(`SharedItemsProjection.swift:245-259`). Delete the app on the recipient device and reinstall (this
removes the App Group snapshot + AutoFill cache), then restore from the recovery key / backup. Do
**not** use Erase Vault for this.

**Also worth purging while the Console is open** (unrelated to the ghost, but it is real litter from
the debugging sessions): Public Database → `LooxInvite` rows with a past `expiresAtMs`, and every row
with `recipientInboxID == "schema-bootstrap"` (the JIT-schema bootstrap drops,
`InviteInboxService.swift:88-97`). Public records are creator-delete-only and the sender's GC list
died with the reinstall, so nothing else will ever clean them.

---

## 4. Code fix (so it cannot recur)

Priority order. Each is small and independent.

**F1 — `leave` must prove it landed.** `Vaultify/Services/Sharing/ApprovalRecipientService.swift:263-266`.
Drain `deleteResults` and rethrow the per-zone error; treat `.zoneNotFound` / `.userDeletedZone` as
success. Only call `clearPin` on confirmed success. Add
`ShareDiagnostics.log("LEAVE", "zone=… result=…")` — this path is currently the only CloudKit
mutation in the sharing stack with zero instrumentation.

**F2 — durable "left" tombstone (does not exist today).** New store beside the pin, in
`ApprovalRecipientService`: account key `approval_left_zone_<ownerName>_<zoneName>` written through
`KeychainStore` (`VaultifyCore/Keychain/KeychainStore.swift:16-38`) — **Keychain, not UserDefaults**,
because Keychain survives app deletion and UserDefaults does not, and this repo already depends on
exactly that property (`SharedItemsProjection.swift:490-497`). Write it *before* the delete in
`leave`; clear it only on a genuine new `container.accept` for that zone. Then in
`SharedItemsProjection.refresh` (`:214`), skip any tombstoned zone entirely and re-attempt the delete
in the background — so a leave that failed offline self-heals instead of resurrecting.

**F3 — no silent re-adoption.** `SharedItemsProjection.swift:227-243`: never auto-TOFU-pin a zone
carrying a tombstone (F2). A zone that reappears after an explicit leave must surface as a *new*
invite decision, never as a silently restored item.

**F4 — validity gate before projecting.** `SharedItemsProjection.swift:262-289`: when
`deviceAuthorized == true` but `values.isEmpty && display == nil`, the current identity cannot open
anything in that zone — it is dead, not Tier-0. Drop it (or render an explicit "this share is no
longer readable — leave it" state) instead of the generic `appString("Shared item")` placeholder at
`:468-471`. Keep the `deviceNotAuthorized` Tier-0 path unchanged (INV-10 is deliberate).

**F5 — erase must actually erase.** `AppEnvironment.eraseEverything` (`:329-363`): add a best-effort
`await approvalRecipient.leaveAllAccepted()` (enumerate `acceptedApprovalZones()`, delete each, write
a tombstone) plus a sweep of the `approval_pinned_owner_key_*` / `approval_owner_key_verification_*`
Keychain items. Today Erase Vault leaves every accepted share fully live.

**F6 — owner registry must survive a reinstall.** `ApprovalShareService.swift:44-56`:
`approval_owner_zone_names` in `UserDefaults` means one owner reinstall orphans every share that
account ever created — permanently unrevocable from inside the app, which is exactly the corner this
user is now in. Fix `revokeAllOwned` (`:485-489`) to enumerate `privateCloudDatabase.allRecordZones()`
for the `apz-` prefix rather than trusting the registry, and mirror the registry into the private DB
(or into `SharingStore`'s synced state) so a fresh install can still see and revoke its own shares.

**F7 — observability in TestFlight.** `Vaultify/Features/Settings/SettingsScreen.swift:174-177`:
Share Diagnostics is `#if DEBUG`, so the one screen that could have answered this in ten seconds is
invisible on the build the user actually runs. Gate it on `AppTransaction`/beta instead of `DEBUG`,
matching how the purchase surfaces already do it in the same section.

**F8 — don't trust the post-leave refresh.** `SharedItemsProjection.swift:132` calls `refresh`, which
may return immediately on the `!refreshing` guard (`:194`). Once F1 exists this is cosmetic, but the
leave path should either await the in-flight refresh or force a bypass so the UI never reports a
success it did not verify.

---

## 5. Open questions for the user

1. **How many ghost rows?** One, or several? Item ids embed `grantId`
   (`SharedOrigin.swift:38`), so N rows = N live grants — this alone separates sub-case b1 (failed
   delete) from b2 (a pile of orphan zones from the repeated debug invites).
2. **Who owns the zone?** Is the other Loox account still available and signed in on a device? If
   yes, Step 2 (owner-side revoke) ends this today. If no, we are into Step 3.
3. **Was the *owner* device also deleted/reinstalled without restore?** If yes, `approval_owner_zone_names`
   and `SharingStore` are gone and there is no in-app path to revoke — 3a/3b/3c only.
4. **Can you run a Debug build on the recipient device?** That is the only way today to read the
   `ZONES` diagnostic and settle b1 vs b2 empirically (F7 fixes this permanently).
5. **Did you ever tap an "Accept" prompt or an invite link between two leaves?** You describe the
   return as silent, which points at b1 — but a tapped accept would make it a straightforward
   re-acceptance instead.
6. **Are the ghost rows empty (no fields, generic title) on both devices?** If one device shows a
   *real* title, the grant is v2 device-bound and only one device's HPKE key is in the bindings —
   that changes which of the two decryption paths (`ApprovalRecipientService.swift:363-372` vs
   `:379-392`) is producing the placeholder.

### What I could not verify
- CloudKit server state: I have no read access to `iCloud.com.bervion.vaultify` from here. Every
  claim about which zones/grants actually still exist is inference from the code paths above.
- The exact per-zone error `modifyRecordZones(deleting:)` returns on this user's device — it is
  discarded at `ApprovalRecipientService.swift:264` and never logged. That is precisely why F1 is
  the first fix.
- CloudKit Console's current per-zone delete affordance for a private database, and the exact iOS 26
  wording/placement of "Delete Data from iCloud".
