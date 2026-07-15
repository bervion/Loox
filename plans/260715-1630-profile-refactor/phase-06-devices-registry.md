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
