# Phase 01 — SharedItemsProjection data layer

## Overview
Priority P1 · Status: pending. Recipient-side shared grants become `VaultItem`-shaped models
served OUTSIDE `VaultStore` — the foundation every later phase renders.

## Key insights
- Shared items must NEVER enter `VaultStore`: vault-item sync would replicate them to B's other
  devices as owned ghosts; Watchtower/AutoFill/export/backup all read the store.
- All data already exists per accepted zone: `AccessGrant` (capabilities), `SharedDisplayEnvelope`
  (title/host), sealed shared-field values, pinned owner key. `SharedItemView.load()` shows the
  exact fetch/decrypt sequence to port.
- Id scheme `shared::<ownerName>::<zoneName>` — impossible to collide with UUID item ids, parses
  back into a `SharedZoneRoute`-equivalent.

## Related code
- Modify: `VaultifyCore/Models/VaultItem.swift` (+ `sharedOrigin: SharedOrigin? = nil`, Codable-optional; owned items stay nil; NEVER persisted non-nil)
- Create: `VaultifyCore/Models/SharedOrigin.swift` — `{ zoneName, ownerName, grantId }`, Codable/Hashable; `var zoneID: CKRecordZone.ID`-builder lives app-side (Core has no CloudKit dependency? CHECK — if Core already imports CloudKit elsewhere keep helper here, else app-side extension)
- Create: `Vaultify/Services/Sharing/SharedItemsProjection.swift` — @MainActor @Observable
- Read for port: `Vaultify/Features/Sharing/SharedItemView.swift` (load()), `ApprovalRecipientService` (fetchGrant, fetchSharedFieldValues, fetchDisplayEnvelope, pin API)

## Implementation steps
1. `SharedOrigin` model + `VaultItem.sharedOrigin` (default nil; exclude from equality-sensitive
   codepaths? — synthesized Codable optional decode is backward compatible).
2. `SharedItemsProjection`:
   - `private(set) var items: [VaultItem]` (projected, `sharedOrigin` set; category from grant
     capability shape — login if TOTP/password fields, else `.other`; fields built from shared
     values + placeholder TOTP fields for askEachTime capabilities).
   - `func refresh(identity:)` — enumerate `acceptedApprovalZones()`, per zone: fetchGrant →
     auto-pin (port from SharedItemView) → shared values → display envelope → build VaultItem
     (title = envelope.title ?? "Shared item", urlField from websiteHost). Single-flight.
   - `func item(id:)`, `func origin(for id:)`, `func requestModel(fieldId:)` cache — RequestCodeModel
     instances keyed by (grantId, fieldId), rebuilt ONLY on grant-id change (port modelsGrantId
     pattern — in-flight WAITING machines must survive refreshes).
   - `func leave(id:)` → `approvalRecipient.leave(zoneID:)` + refresh.
   - Triggers wired in phase 2 (recipientChangeCounter task id + foreground).
3. `AppEnvironment`: `let sharedItems = SharedItemsProjection(...)`; wipe on eraseEverything.
4. Facade: extend `VaultRepository` READ helpers used by UI only — decision: keep repository pure;
   add `env.sharedItems` merge at call sites instead (Home/Items/Search) to avoid store contamination.

## Success criteria
- Unit tests: projection builds correct VaultItem from grant fixtures (title fallback, TOTP
  placeholder fields, shared values mapping); id scheme round-trips; owned-item codepaths
  (repository.items) contain zero shared items.
- Compiles both platforms; suite green.

## Risks
- `VaultItem` Codable change ripples into sync/backup codecs — `sharedOrigin` must be nil there;
  add test asserting encode(ownedItem) unchanged (golden bytes or key-absence check).
