# Phase 06 — Devices (CloudKit registry) — NET-NEW (large)

Type: net-new · Depends: 01 · **Needs ADR sign-off before coding.**

## Decision (user)
Full CloudKit device registry now: a cross-device list with revoke. Prior spec §5c envisioned it ("This vault syncs to" — This device Active, others "Synced Xh ago"). Zero code exists today.

## Current state
- Pairing (`PairDeviceSheet`, `VaultifyCore/Crypto/VaultKeyPairing.swift`) is a one-time QR / CloudKit-escrow key handoff — it persists NOTHING about devices.
- Recipient-device tracking exists for grants (`DeviceHPKEDirectoryEntry`) but NOT for the owner's own devices.
- Device name available via `UIDevice.current.name` (already used by `ApprovalRecipientService`).

## ADR-D (finalize before coding)
- **Record**: private-zone CloudKit `Device` { deviceID (stable, Keychain-persisted UUID), name, model, lastSeenAt, appVersion }.
- **Publish**: upsert own record on unlock + after a successful sync. No PII beyond device name; private DB only.
- **List**: query all `Device` records → "This device" (Active) + others ("Synced Xh ago" from `lastSeenAt`).
- **Revoke — SECURITY-CRITICAL**: true revoke = rotate the vault key + re-provision to remaining devices (heavy). MVP boundary to decide:
  - v1: "Remove device" deletes its record + stops recognizing it — does NOT rotate the key (documented limitation).
  - v2 (follow-up): key rotation on revoke.
  **Must preserve "Vault Key never syncs."**
- **Gate**: only meaningful when iCloud sync is on (`iCloudSyncEnabled` / `VAULTIFY_ICLOUD`).

## Files (new)
- `VaultifyCore/…/DeviceRegistry` (record model + service), `Vaultify/Features/Profile/DevicesScreen.swift`, a publish hook in the sync/unlock path.

## First slice
- Record type + publish own device + list (This device + others with `lastSeenAt`). Revoke = record delete (v1) with a clear note about the key-rotation follow-up.

## Risks / open
- Crypto/security surface (revoke, key handling) — `/ak:security` pass before shipping revoke.
- CloudKit schema addition (dev portal; the container + entitlements already exist).
- Privacy: device names are user-identifying — keep in the private DB only.

## Validation
- ADR approved. `make check`; a device appears/updates across two devices; EN + VI; security review for revoke before it ships.

## Status (session 260715) — ADR-D resolved
- **Revoke:** v1 is **list-only, NO revoke button.** A "Remove device" that only deletes the CloudKit record WITHOUT rotating the vault key would imply security it doesn't provide (the device keeps its copy of the key) — worse than absent. Real revoke = key rotation + re-provision, deferred to v2 behind its own security pass.
- **Schema:** the `Device` record type auto-creates in the CloudKit **development** environment on first save, but must be **promoted in the CloudKit dashboard** before a TestFlight/prod build can publish — a manual step outside code.
- **Blocked on device verification:** publish + cross-device list can't be validated headlessly (needs two devices + iCloud).

## Implemented — list-only registry (session 260715, PR #105 branch)
- `DeviceRegistryService` (`Services/Sync/`) publishes THIS device to a private-DB `OwnerDevice` record (deviceID, name, model, lastSeenAt, appVersion) and queries all such records; `DevicesScreen` lists them (this device = Active; others = locale-aware "N ago"). Best-effort + gated (`isConfigured` + `iCloudSyncEnabled` + not tests) → degrades to "just this device", never crashes. **No revoke** (ADR-D). Stable device id = 16 random bytes in the shared Keychain group (`OwnerDeviceIdentity`). Publishes when the Devices screen is opened (moving publish into the sync path so peers appear without opening the screen is a small follow-up).
- **Owner must do once in the CloudKit dashboard** before a TestFlight/prod build lists peers:
  1. Record type **`OwnerDevice`** in the private **`Vault`** zone (dev infers it on first save).
  2. A **Queryable index on `recordName`** for `OwnerDevice` (the list query uses it).
  3. Promote the schema Development → Production.
- Verify end-to-end on two signed-in devices with iCloud Sync ON.
