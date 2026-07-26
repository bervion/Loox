# Device Management: full peer list + Log Out Device (remote self-sign-out)

Status: implementing (260726)
Owner ask: Devices shows only the current device despite other devices on the same iCloud account; want the full list, a per-device detail screen, and revoke → the other side force-logs-out (queued until it comes online if offline).
Recon: workflow wf_484e54b5-b80 (registry map, CloudKit/lifecycle map, manage-devices UX patterns).

## Root cause (peer list)
`DeviceRegistryService.fetchDevices()` uses a TRUEPREDICATE `CKQuery`, which requires a
manual Queryable index on `recordName` per CloudKit environment (+ `OwnerDevice` deployed to
Production). Errors are silently swallowed → always "just this device".

## Design (decided)

- **Mirror, don't query**: the delta sync (`CloudSyncService.pull()`) already receives every
  `OwnerDevice` record in the Vault zone and drops it. New `DeviceRegistryMirror` persists
  them (UserDefaults JSON, non-secret metadata); `fetchDevices()` reads the mirror + merges
  `thisDevice`. CKQuery deleted — no dashboard index needed at all anymore.
- **Log Out Device = cooperative sign-out, NOT cryptographic revocation** (ADR-D stands:
  true revocation = vault-key rotation, future phase; doc'd on the service). Owner saves a
  `DeviceRevocation` record (`revoke-<deviceID>`) in the Vault zone.
- **Self-enforcement on the revoked device**: revocations arrive through the same delta pull
  (mirrored). After each sync (`SyncCoordinator.runSync` — which already fires on unlock,
  foreground, reconnect, silent zone push), if the mirror holds a revocation for MY device id
  → post `.vaultRemoteSignOut` → `AppEnvironment.handleRemoteSignOut()`: local-only erase
  (extracted from `eraseEverything`, minus remote teardown), best-effort delete of own
  `OwnerDevice` record, mint a NEW device id (prevents a re-pair wipe loop), land on
  onboarding + one-time explanatory alert. Offline device executes on next online — exactly
  the ask. Honest limit (doc'd + UX copy): a device kept permanently offline can't be forced.
- **List filtering**: revoked device ids are filtered out everywhere (no pending row);
  the confirm dialog states the next-online semantics (WhatsApp model).
- **Detail screen** `DeviceDetailScreen` (pushed from the Profile Devices card): glyph hero,
  model, app version, last seen; red "Log Out Device" + confirmation for non-current
  devices (Telegram/HIG wording).
- `VaultDevice` gains `appVersion`.

## CloudKit schema (owner, one-time)
Production needs record types `OwnerDevice` + `DeviceRevocation` deployed (dashboard →
Deploy Schema Changes). NO queryable indexes required (mirror + fetch-by-recordName only).

## Acceptance
- Two sim devices on one account both appear after a sync round-trip.
- Log Out from device A → B wipes local data + lands on onboarding on its next sync trigger
  (foreground/reconnect/push), shows the explanation alert; B re-pairs cleanly as a new device.
- EN+VI complete; unit tests for mirror upsert/filter/revocation detection; make check + macOS green.
