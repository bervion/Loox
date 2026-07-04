---
phase: 3
title: "CloudKit Sync Enablement"
status: code-complete (147 tests pass, review PASS-w-concerns→all 4 findings fixed; BLOCKED on 2-device real-hardware QA before claiming sync works)
priority: P1
effort: "2-3d + provisioning + device QA"
dependencies: []

<!--
Implementation (2026-07-04, commit 9ed1bdf):
- LWW fixes ALL landed: #2 tombstone bumps updatedAt (item+folder); #8 pin/archive via new
  metaUpdatedAt column + two-gate merge in upsertFromRemote; #9 pull cursor loop; #10 changeTag
  short-circuit (same-revision no-op, clock-skew-proof); #11 markSynced snapshot guard.
- Review found H1 (blind push overwrites newer server rev; loser never re-pushes → edit stranded
  forever) → FIXED: local strict-winner re-marked dirty on tag-mismatch; 2 regression tests.
- #16: useCount/lastUsedAt no longer uploaded (device-local); honest e2e copy in SyncSettings.
- #3: normalizeDefaultIdentity already existed (identity half); folder half = mergeDuplicateSeedFolders,
  narrowed to exact seed signature (localized "My Vault"+lock+blue), runs ONLY post-remote-pull
  (reloadAfterRemoteSync flag) so user-created identical folders never collapse.
- Key provisioning: VaultKeyPairing (HPKE Curve25519_SHA256_ChachaPoly, pairingId bound in info,
  QR = loox-pair/1/<id>/<pubkey-b64url>); VaultKeyEscrowService (VaultKeyEnvelope singleton =
  recovery-wrapped key+salt+kdf, fingerprint-gated push, LAST-WRITER semantics documented;
  VaultKeyPairingHandoff TTL 10min delete-on-read); VaultSession.joinVault (no seeding, optional
  recovery-key re-wrap); JoinVaultFlow (onboarding entry) + PairDeviceSheet (Approve gate) + QRCodeView.
- SecureBytes for received key in join flow (review M1 — CoW zeroization defect fixed).
- Erase Vault deletes CloudKit zone best-effort + clears fingerprint + disables sync toggle (M2).
- SyncCoordinator: immediate + 3s-debounced (.vaultLocalMutation), single-flight+follow-up,
  pushes recovery envelope post-sync. Entitlements (both platforms) + VAULTIFY_ICLOUD flag ON.
- 31 strings localized EN+VI (incl. 2 P1 leftovers).
PENDING (ship gate): 2-device real-hardware QA — pairing round-trip decrypt, recovery join,
conflict convergence, signed-out states. CI note: match profiles must carry iCloud capability.
Follow-ups (low): scrub legacy useCount fields server-side once; RegenerateKitView copy note re
envelope last-writer; SyncCoordinator observer deinit (app-lifetime, cosmetic).
-->

---

# Phase 3: CloudKit Sync Enablement

## Overview

Turn ON the **already-written** CloudKit sync so vaults converge across iPhone/iPad/Mac. The
push/pull + LWW engine exists (`CloudSyncService.swift`); this phase is provisioning, flipping the
gate, wiring automatic sync triggers, and real-device multi-device QA — NOT building sync.

**Independent of P1/P2** — can run in parallel (only shares `Project.swift` entitlements edit).

## Requirements

- Functional: Edit on device A appears on device B after sync (LWW by `updatedAt`).
- Functional: Sync runs automatically (foreground/return-to-active + after local mutation), not only manual.
- Functional: Graceful states when iCloud is signed-out or unprovisioned (no crash, clear message).
- Non-functional: Zero-knowledge preserved — only sealed blobs + non-secret metadata leave device.
- Non-functional: No launch crash when the flag is off (keep `VAULTIFY_ICLOUD` honesty).

## Architecture

**Existing (verify, don't rebuild)**: `CloudSyncService` uses `CKContainer("iCloud.com.bervion.vaultify")`,
zone `"Vault"`, record types `"VaultItem"` + `"VaultFolder"`, `savePolicy: .changedKeys`,
LWW via `store.upsertFromRemote(...)` gated on `updatedAt`. Passkeys intentionally NOT synced (keep deferred).

**Provisioning (manual, outside code — user action)**:
- Enable **iCloud (CloudKit)** capability + container `iCloud.com.bervion.vaultify` in Apple Developer portal.
- Add the iCloud entitlement to app entitlements (iOS + macOS) — ONLY once provisioned (else launch crash).
- Add `VAULTIFY_ICLOUD` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (both platforms) in `Project.swift`.

**Wiring (code)**:
- Trigger sync on `scenePhase == .active` and after mutations (debounced) — a `SyncCoordinator` that
  calls `CloudSyncService.sync(reload:)` and feeds `VaultRepository.reload`. Hook in `RootView`/`AppEnvironment`.
- Optional (stretch, YAGNI-check): CloudKit **subscription + silent push** for near-real-time cross-device.
  Requires remote-notification background mode + `CKDatabaseSubscription`. Default: **poll-on-activate** only
  unless user confirms push is needed (Open Question 4). Do not build push speculatively.
- Ensure synced-column mutations bump `updatedAt` (LWW gate) — audit `setDefaultIdentity`, avatar,
  folder edits already do; confirm no column change is dropped (memory: sync-LWW-updatedAt-gate).

## Related Code Files

- Create: `Vaultify/Services/Sync/SyncCoordinator.swift` (auto-trigger + debounce)
- Modify: `Project.swift` (iCloud entitlement + `VAULTIFY_ICLOUD` condition — gated on provisioning)
- Modify: `Vaultify/Vaultify.entitlements` + new `Vaultify-macOS.entitlements` (iCloud container)
- Modify: `Vaultify/App/AppEnvironment.swift` / `RootView.swift` (invoke coordinator on activate)
- Verify (no logic rebuild): `Vaultify/Services/Sync/CloudSyncService.swift`,
  `Vaultify/Features/Settings/SyncSettingsView.swift`, `VaultifyCore/Store/ItemRecord.swift`

## Implementation Steps

1. **iCloud container + capability already provisioned** (Validation Session 1) → just add the iCloud
   entitlement (iOS + macOS) + `VAULTIFY_ICLOUD` flag. No portal step needed.
   <!-- Updated: Validation Session 1 — container already provisioned -->
1b. **Build the QR-pairing + Emergency-Kit key provisioning** (see §Key Provisioning) — the gating,
   heaviest task; a 2nd device cannot decrypt without it.
2. Add iCloud entitlement (both platforms) + `VAULTIFY_ICLOUD` condition; `tuist generate`.
3. Build `SyncCoordinator`: sync on activate + debounced post-mutation; wire into app lifecycle.
4. Audit all synced columns bump `updatedAt`; add any missing bumps.
5. Manual multi-device QA: create/edit/trash/favorite/folder/identity/avatar on A → verify on B; conflict
   (edit same item both offline) resolves by latest `updatedAt`, no data loss.
6. Verify signed-out iCloud + flag-off builds: clear messaging, no crash.

## Success Criteria

- [ ] With flag on + iCloud signed-in, a create/edit/delete on one device appears on another.
- [ ] LWW conflict resolves to the newest `updatedAt`; no item resurrected or lost.
- [ ] Sync auto-runs on foreground; no manual tap required for basic convergence.
- [ ] Flag OFF build launches with no iCloud entitlement and no crash (regression guard).
- [ ] Signed-out iCloud shows the localized "Sign in to iCloud" state (EN + VI).
- [ ] Only sealed blobs + metadata in CloudKit dashboard (no plaintext, no passkey material).

## Risk Assessment

- **Unprovisioned iCloud entitlement crashes at launch** (documented trap) → never commit the
  entitlement/flag until portal provisioning confirmed; keep off-by-default path intact.
- **CloudKit needs a real Apple ID / device** — simulator iCloud is flaky → QA on real hardware.
- **Full-record LWW drops un-bumped column changes** → the `updatedAt` audit is mandatory, not optional.
- Passkey sync stays deferred — do not scope-creep it in here.

## Red Team Amendments (2026-07-04) — P3 is NOT "flip a flag"

The sync engine was written for one device. The findings below are correctness/security defects that
surface the moment a 2nd device exists. **This phase must fix them, not just enable sync.** Consider
splitting P3 into **P3a (Key Provisioning + correctness)** and **P3b (enable + QA)**.

### §Key Provisioning — [CRITICAL #1] BLOCKS all multi-device value

Each device generates its **own random Vault Key** at creation (`VaultSession.swift:57-73` →
`KeyHierarchy.newVaultKey()` = `CryptoRandom.bytes`), wrapped under a per-device salt and saved ONLY to
the local App-Group keybundle (`VaultKeyBundle.save`), in a `…ThisDeviceOnly` keychain item
(`KeychainStore.swift:27`). `CloudSyncService` syncs only sealed item/folder blobs — never key material.
→ A 2nd device with the *same master password* derives a *different* Vault Key and **cannot decrypt any
pulled blob** (rows appear, every AES-GCM open fails).

**DECIDED (Validation Session 1) — QR device-pairing + Emergency-Kit fallback:**
<!-- Updated: Validation Session 1 — key provisioning = QR pairing + Emergency Kit (not keybundle-sync) -->

- **QR device-pairing (primary path).** The trusted device (iOS = source of trust) authorizes a new
  device. New device (Mac/iPad/second iPhone) generates an **ephemeral Curve25519 keypair** and shows
  its public key as a QR. The trusted device scans it, **HPKE-seals the Vault Key** to that ephemeral
  public key, and hands it over (via a CloudKit hand-off record or a response QR). New device opens the
  envelope with its ephemeral private key → obtains the Vault Key, then re-wraps it under its own
  local master-password KEK + biometric keychain. **Reuse the existing HPKE infra**:
  `VaultKeyBundle` already carries a `Curve25519_SHA256_ChachaPoly` envelope keypair (added for iOS-18
  silent passkey upgrades) — the seal/open primitives exist; this phase adds the pairing ceremony UI +
  ephemeral-key exchange, not new crypto.
- **Emergency-Kit fallback (no trusted device handy).** New device enters the **Recovery Key** (Crockford
  base32) or imports the **Emergency Kit PDF**; it unwraps the recovery-KEK-wrapped Vault Key (that
  wrapped blob is synced alongside the vault). Same path the existing recovery flow already uses.
- **New-user-first-on-Mac** just creates a fresh vault normally — pairing only applies when *adding* a
  device to an *existing* vault.
- The Vault Key is **never** uploaded as plaintext; only HPKE-sealed (to an ephemeral device key) or
  recovery-KEK-wrapped ciphertext leaves a device. Do NOT claim "sync works" until a 2nd device
  round-trips a real decrypt via both paths.
- Scope: pairing ceremony UI (QR display + camera scan — iOS/iPad have cameras; the *new* Mac device
  only displays a QR, the trusted iOS device scans), ephemeral-key exchange, hand-off record schema,
  Emergency-Kit import on 2nd device. This is the heaviest part of P3.

### §LWW / tombstone correctness fixes

- **[Critical #2] Delete never propagates + resurrects.** `VaultRepository.delete()` sets
  `deletedAt + dirty` but NOT `updatedAt` (`VaultRepository.swift:212-216`); pull gate is
  `updatedAt > existing.updatedAt` (`VaultStore.swift:65`) → tombstone dropped on the other device, and
  a later edit there resurrects the "deleted" secret on both. **Fix:** bump `updatedAt = .now` on delete
  / empty-trash; add regression test (delete on A → gone on B after pull).
- **[High #8] Pin/archive dropped.** `setColumn` (`togglePin`/`archive`/`unarchive`,
  `VaultRepository.swift:165-182`) deliberately does not bump `updatedAt`, so pull drops them at the same
  gate. The plan's original audit named only identity/avatar/folder — **it misses pin/archive.** Decide:
  bump `updatedAt` for synced columns, or a per-field merge, or a separate `metaUpdatedAt`.
- **[High #9] Single-query pull truncates large vaults.** `pull` binds the continuation cursor to `_`
  and never follows it (`CloudSyncService.swift:97-106`); `maximumResults` is a per-request ceiling, not
  "fetch all." Large vault → partial pull → perceived data loss. **Fix:** loop on the cursor
  (`records(continuingMatchFrom:)`) until nil. This is a correctness requirement, not MVP-optional.
- **[High #10] Wall-clock LWW loses edits under clock skew.** `updatedAt` is device-local `Date()`
  (`VaultRepository.swift:134`); a slow-clock device's genuinely-newer edit is rejected. `recordChangeTag`
  is already fetched/stored but unused for conflict decisions. **Fix:** use CloudKit server
  `modificationDate`/`recordChangeTag` as the tiebreak, or a monotonic per-record version. At minimum
  document + add a change-tag guard.
- **[High #11] `markSynced` clears `dirty` unconditionally → lost in-flight edit.** Push snapshots dirty
  records, `await`s `modifyRecords` (a suspension point), then `markSynced` sets `dirty = false`
  (`CloudSyncService.swift:68-77,95-99` → `VaultStore.swift:95-99`). An edit made during the await is
  silently un-dirtied → never pushed. Auto-sync-on-mutation (this phase) makes it MORE likely. **Fix:**
  capture `updatedAt`/change-tag at snapshot; clear `dirty` only if unchanged since snapshot. The
  `SyncCoordinator` must specify this ordering.

### §First-sync merge — [Critical #3]

Onboarding seeds a "My Vault" folder (`OnboardingFlow.swift:62`) and a default identity
(`OnboardingFlow.swift:73-81`, `IdentitySeed.swift:29-30`, `isDefaultIdentity:true`) with fresh UUIDs
**per device**. Two already-onboarded devices merge by `recordName` (UUID) → different UUIDs → both
survive → **two default identities** (violates the single-default invariant `VaultRepository.swift:96-104`)
+ two "My Vault" folders. **Fix:** deterministic recordNames for seeded singletons (stable
"default-identity"/"my-vault"), or a post-pull dedup that collapses multiple defaults and merges
same-name seed folders. New task — the plan had none.

### §Honesty — [Medium #16]

`useCount` (`CloudSyncService.swift:117`) and folder `iconAsset`/`colorRaw`/`sortIndex`
(`:147-149`) upload as **plaintext** CKRecord fields. Either seal them into the encrypted blob, or
restate the guarantee honestly ("secrets sealed; limited organizational metadata in cleartext") in the
plan AND user-facing sync copy. Drop the flat "no plaintext" success-criterion wording.

### §Also
- **[Medium #20]** Add `Localizable.xcstrings` (e.g. "Sign in to iCloud" state) — EN + VI.
- **[#19]** P3 shares the iCloud-entitlement `Project.swift` edit with P1 → serialize, not parallel.
- Reconcile the duplicate sync trigger: `RootView` already calls `env.syncNow()` on `.active` — the new
  `SyncCoordinator` must replace/absorb it, not double-fire.
