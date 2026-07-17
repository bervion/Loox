# Deep Audit: restore-by-key failure, share-passkey loss, auto-lock mid-use

Date: 2026-07-17 · Branch: main (working tree) · Trigger: 3 user-reported bugs.
Method: 2 parallel read-only debugger agents (backup/restore plane, share pipeline) + direct trace (auto-lock); every claim re-verified against source before fixing.

## Bug 1 — "Key này không thể restore" after reinstall

### Root causes
1. **Recovery-envelope upload gated on FULL sync success** (`SyncCoordinator.runSync`): `pushRecoveryEnvelopeIfNeeded()` ran only when `cloudSync.status == .success`.
2. **Push is all-or-nothing** (`CloudSyncService.push()`): pushItems → … → pushPersonas sequential in one throw; any failure also skips `pull()`.
3. Since v1.18.0 every fresh vault auto-seeds a dirty `VaultPersona` (+ alias/inbox, audit types since v1.27). **Production CloudKit schema likely lacks these record types** (JIT schema creation is OFF in production; repo has an *unchecked* deploy reminder in `plans/260711-2102-vault-audit-upgrade/phase-11-qa-design-dna-docs.md:41`). → first sync always errors → envelope NEVER uploaded → reinstall finds nothing (or a stale pre-v1.18 envelope whose GCM rejects the new key → exactly "Khóa khôi phục đó không hợp lệ").
4. **`fetchRecoveryEnvelope` collapsed every error** (network/auth/throttle) into "No synced vault found" via `try?`.
5. Timing coincidence explains the passkey suspicion: v1.18.0 shipped the same release as passkey-sharing hardening; the sharing commits never touch this plane.

### Passkeys lost even when old restores worked
`PasskeyRecord` was **never part of CloudKit sync** (store uses `cloudKitDatabase: .none`; push/pull have no passkey plane). Recovery-key restore transfers the Vault Key then pulls items/folders only → passkeys mechanically cannot come back. Only the manual encrypted file backup includes them (`VaultBackup`), and that path had its own silent-drop hole (below). By construction since passkeys shipped — not a regression.

### Fixes (this change)
- `SyncCoordinator.runSync`: escrow push now attempted **whenever sync is enabled**, regardless of sync status.
- `VaultKeyEscrowService.pushRecoveryEnvelopeIfNeeded`: ensures its zone itself (`modifyRecordZones` idempotent) so the envelope uploads even if no item sync ever succeeded.
- `CloudSyncService.push()`: fault-isolated per record type — collects the first error, still runs all other planes AND `pull()` + reload, then surfaces the error as status.
- `OnboardingFlow` + `RegenerateKitView`: kit generation triggers `env.syncNow()` immediately (envelope must not wait for a debounced item sync).
- `fetchRecoveryEnvelope`: only server-authoritative `unknownItem/zoneNotFound/userDeletedZone` → `.noEnvelope`; everything else → new `.cloudUnavailable` ("iCloud can't be reached right now…", EN+VI).
- `ExportView`: encrypted export now **fails loudly** if resolvable passkey secrets < passkeys in vault (was: silently passkey-less backup).

### REQUIRED USER ACTION (no code can fix this)
CloudKit Console → container `iCloud.com.bervion.vaultify` → **deploy schema to Production**. Verify these record types exist in Production: `VaultItem` (incl. newer fields `metaUpdatedAt`, `pinned`, `archived`, `isDefaultIdentity`, `avatarSealed`), `VaultFolder`, `VaultPersona`, `VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState`, `VaultKeyEnvelope`, `VaultKeyPairingHandoff`, `OwnerDevice` (+ its queryable index), and the approval-mode types. One Console look also confirms RC diagnosis: check whether the account has a `VaultKeyEnvelope` record and its `updatedAt`.

## Bug 2 — Share vault: recipient gets nothing despite passkey selected

### Root causes (ranked)
1. **RC1 — flag flipped without its reader** (v1.33.0, commit `7e83ae1`): `FamilyShareTransport.perGrantEnabled = true` makes owners write grants under `grant:<grantId>`, but owner-side `ApprovalShareService.fetchGrantFresh` still read ONLY the legacy singleton `grant`. Its own doc said it was safe "while the flag is off (default)". Broken for every share created ≥v1.33:
   - `ApprovalCoordinator.refreshOwnerRequests:135` — `try? … else continue` → recipient's ask-each-time passkey/TOTP request **silently vanished from the owner inbox** → recipient's AutoFill times out → sign-in fails.
   - `verifyInbound` → approve impossible (`grantMissing`).
   - `ShareRecipientDetailSheet.loadGrant` → capability editor never renders; `republish*` → item edits/"Send update now" fail silently (`try?`).
2. **RC2 — forward-incompat**: recipients on ≤v1.32 fetch the fixed name `grant` only → a v1.33+ owner's share is invisible entirely ("bên kia không có gì" literal). Fix = update both devices; deliberately NOT dual-writing legacy records (TestFlight-only skew window, permanent complexity not warranted — YAGNI).
3. **RC3 — Space fan-out destroys foreign grants**: `ShareSpaceSheet` reuses the recipient's existing zone; `SpaceShareMembershipReconciler.plan` then revoked any grant whose item isn't in the Space (passkey-only items are never safelist-eligible → always revoked) and downgraded in-Space items to the safelist via a publish with `vaultKey: nil, itemPasskeys: []` → passkey stripped.
4. **Hardening — silent passkey drop at publish**: `SharedGrantComposer.publish` with nil `vaultKey` (or a secret that fails decode) published a grant that NAMES passkeys with zero display metadata/sealed key behind them.

### Fixes (this change)
- New owner-side fetches in `ApprovalShareService`: `fetchGrantFresh(zoneID:grantId:)` (per-grant name first, legacy fallback, decoded-id-matched — INV-FAM-01 mirror of the recipient path) and `fetchGrantFresh(zoneID:forItemId:nowUnixMs:)` (via verified `fetchAllGrants`, newest by epoch/createdAt/id). Legacy zone-only method deleted → compiler-enforced rewiring.
- `verifyInbound` resolves by `request.grantId`; coordinator inbox scan fetches all grants per zone and matches each request to ITS grant (multi-grant zones now correct); errors flow to the existing zone-gone/transient catches instead of `try?`.
- `republishDisplayEnvelope`/`republishSharedValues` take `itemId` (callers: editor auto-update per share record, sheet manual update).
- RC3: `ItemShareRecord.spaceManaged: Bool?` (device-local ownership registry; nil for all ceremony shares + pre-existing records) + `Reconciler.planManaged(desired:published:spaceManagedItemIds:)` — foreign grants are never revoked, never updated, and their items are removed from `desired` so a CREATE can't supersede them either. Executor feeds the registry and stamps its own publishes. 3 new unit tests.
- Composer throws new `ComposeError.passkeyMaterialUnavailable` (EN+VI) when any granted passkey slot can't materialize display meta or its hand-over blob.

### Back-compat
- Pre-v1.33 legacy-singleton grants: still readable everywhere (legacy fallback preserved).
- Space grants published before `spaceManaged` existed (feature is ~1 day old, TestFlight-only): treated as foreign → the reconciler won't auto-revoke/update them; owner can still manage/revoke via the share sheet or whole-zone revoke. Accepted degradation, documented in code.

## Bug 3 — Auto-lock fires mid-use on paywall/Profile screens

### Root cause
The iPhone shell wraps `MainTabView` in a UIKit `UINavigationController` (`VaultUINavShell`); `AppNavigator.push` (Profile, Settings, item detail from Home) makes UIKit remove the tab root's view from the window when the push settles. `UserActivityMonitor`'s probe left the window → `didMoveToWindow(nil)` → coordinator **removed the touch-observing gesture recognizer from the window**. From then on no touch on any pushed screen (or sheet above it, e.g. the paywall) refreshed `lastActivity`, while the 20s idle timer in `VaultShellBehaviors` kept running → lock at exactly 5' even during active use. Tab roots were unaffected — matching the report.

### Fix (this change)
`UserActivityMonitor.Coordinator`: recognizer now **stays parked on the window** when the probe merely leaves it; it moves only when the probe surfaces in a genuinely different window and is removed only on shell dismantle (lock/unlock recreation — the anti-leak path). Verified compile; behavior needs a device pass.

### Design note (unchanged, deliberate)
True idle — zero touches for the whole window — still locks in the foreground; that is the intended security posture. If "auto-lock" should count only time outside the app, say so and it's a small change (drop `lockIfTimedOut`, keep the background path).

## Verification
- `make check`: BUILD SUCCEEDED (app + AutoFill extension), full tree with all fixes.
- Targeted suites covering every changed area — **all passed** (iPhone 16, iOS 18.6 sim):
  SpaceShareMembershipReconcilerTests (+3 new planManaged tests), SpaceShareMembershipExecutorTests (+1 new foreign-grant test, 6 fixtures updated to the ownership contract), SharedGrantComposerTests, FamilyShareTransportTests, GrantWireV2Tests, ApprovalRequestWireV2Tests, ApprovalShareServiceSupersedeTests, CloudSyncMergeTests, ShareLifecycleStatusTests, SharingStoreIdentityTests, PasskeyVaultTests, PasskeyBackupRoundtripTests, ExtensionSessionStoreTests.
- **Full-suite verdict is blocked by a machine-level issue, not the fixes**: the test HOST intermittently crashes at launch with `malloc: pointer being freed was not allocated` (constant address → runtime/dyld object over-release). Proven ENVIRONMENTAL by bisect: `git stash` (yesterday's green baseline) crashes identically on both iOS 26.3.1 and 18.6 sims. Appeared the same morning Xcode/simulator state changed (duplicate "iPhone 16" devices also broke `make test`'s `name=iPhone 16` destination resolution). Remedy: reboot / `xcrun simctl shutdown all` + erase duplicate sims, then rerun `make test`; if the ambiguity persists, pin the Makefile destination by simulator id.

## Follow-ups (proposed, not implemented)
1. **Passkey CloudKit sync** — IMPLEMENTED same day: `plans/260717-1040-passkey-cloudkit-sync/` (branch feat/passkey-cloudkit-sync). Closes RC-2. Production schema deploy for `VaultPasskey` still required before shipping.
2. Escrow-upload status surfaced in Settings ("Recovery backup uploaded ✓ / pending") — monitoring gap that let Bug 1 ship silently.
3. Consider CI check: grep for new `recordType` strings vs a checked-in production-schema manifest.

## Unresolved questions
1. Production CloudKit schema contents (Console check — decides Bug 1 RC conclusively; the code fragility was real regardless).
2. Which build the share RECIPIENT device runs (decides RC1 vs RC2 for the observed symptom).
3. Whether a Space share to the same recipient ran before the passkey share "disappeared" (RC3 confirmation; CloudKit dashboard would show the grant record deleted).
4. Auto-lock fix + edit-mode flick fix both await on-device verification (iPhone 16 Pro Max).
5. Machine: test-host launch crash (environment, reproduced on clean baseline) — clear with reboot/sim reset, then a full `make test` should return to all-green; duplicate iPhone 16 simulators need deleting for `make test`'s named destination to resolve.
