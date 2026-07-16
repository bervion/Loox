# Crypto-surface map — Vaultify iOS (read-only scout)

Date: 2026-07-15. Scope: ground two plan upgrades — family-sharing transport + vault-key rotation. Read-only; every claim cited file:line. Paths absolute-relative to repo root `/Users/bervion/Developer/Projects/mobile/ios/Vaultify`.

Key primitive: `AESGCM.seal/open(_:key:)` = AES-256-GCM, layout `nonce(12)||ct||tag(16)` (`VaultifyCore/Crypto/AESGCM.swift:11-30`). Vault Key = random 32B, generated once, only ever stored WRAPPED (`VaultifyCore/Crypto/KeyHierarchy.swift:10-41`).

---

## 1. SEALED-CIPHERTEXT INVENTORY

Legend: **VK** = Vault Key · **KEK** = password/recovery/passphrase-derived Argon2id key · **L2SK** = app-wide Level-2 secret key · **HPKE** = per-recipient/per-device Curve25519 key. "Re-seal on VK rotation?" answered per row.

### Sealed under the VAULT KEY

| # | Category | Store / record | seal | open | Re-seal on rotation? |
|---|----------|----------------|------|------|----------------------|
| a | Item payload/fields (`ItemSecret`: title, category, folderId, fields[], tags, iconAsset) | `ItemRecord.sealed` (`Store/ItemRecord.swift:11`) | `Data/Repositories/VaultRepository.swift:527`; `VaultWriter.swift:48` | `VaultRepository.swift:531,557`; `VaultReader.swift:94`; `VaultReader+Spaces.swift:23`; `WebExtensionFillPayload.swift:169`; `WebExtensionReader.swift:159` | **Y** — this IS the primary record; synced (`VaultItem` CKRecord). |
| a′ | Identity avatar JPEG | `ItemRecord.avatarSealed` (`Store/ItemRecord.swift:50`) | `VaultRepository+Avatar.swift:26` | `VaultRepository+Avatar.swift:13` | **Y** — separate CK Data column on the item; synced (`CloudSyncService.swift:196,218`). |
| b | Protected fields (`protected:true`) | plaintext strings INSIDE `ItemSecret.fields` | (sealed as part of item, no separate call) | — | **Y**, via the item re-seal — no standalone seal. |
| b′ | **Extra-protected** fields (`guard2==true`) — 2nd layer | field value replaced by `SecretGuard` `v2g:` payload, still inside `ItemSecret` | `SecretGuard.swift:30` (L2SK), `:46` (custom-code Argon2 key) | `SecretGuard.swift:37,55` | **N for the inner payload** — inner ct is keyed by **L2SK / custom code, NOT VK** (`Models/DynamicField.swift:13-19,35`). VK rotation re-seals only the OUTER item; the `v2g:` bytes survive byte-identical. |
| c | Attachments / file blobs | files `Attachments/<id>.enc` in App Group container; meta in item `.fileRef` field | `Services/AttachmentStore.swift:51` | `AttachmentStore.swift:59` | **Y** — sealed under VK on disk. **TRAP (non-ItemRecord, on-disk, NOT synced).** |
| d | TOTP seeds | a `DynamicField` kind `.totp` inside `ItemSecret.fields` (`Models/VaultItem.swift:88`) | (part of item seal) | — | **Y**, via item re-seal — no separate TOTP store. |
| e | Passkey private key + metadata (`PasskeySecret.privateKeyRaw` = P256) | `PasskeyRecord.sealed`; also `PasskeyRecord.largeBlobSealed`; and the HPKE-upgrade envelope private key `VaultKeyBundle.envelopePrivateKeySealed` | `Passkey/PasskeyVault.swift:135` (secret), `:108` (largeBlob); `Passkey/PasskeyEnvelope.swift:93` (envelope privkey under VK) | `PasskeyVault.swift:94,191`; `PasskeyEnvelope.swift:104` | **Y** — sealed under VK. **TRAP (PasskeyRecord is NOT an ItemRecord; device-local, NOT synced — absent from `CloudSyncService`).** |
| f | Persona data (`PersonaSecret`) | `PersonaRecord.sealed` | `VaultRepository+Personas.swift:17` | `:21` | **Y**. **TRAP** — separate record type; synced (`VaultPersona`). |
| f′ | Folders (`FolderSecret`: name) | `FolderRecord.sealed` | `VaultRepository+Folders.swift:12` | `:16` | **Y**. **TRAP** — separate type; synced (`VaultFolder`). |
| f″ | Email aliases | `EmailAliasRecord.sealed` | `VaultRepository+Aliases.swift:11` | `:15` | **Y**. **TRAP** — separate type; synced (`VaultEmailAlias`). |
| f‴ | Forwarding inboxes | `ForwardingInboxRecord.sealed` | `VaultRepository+ForwardingInboxes.swift:14` | `:19` | **Y**. **TRAP** — separate type; synced (`VaultForwardingInbox`). |
| g | Search / index tokens | **none found** — search is in-memory over decrypted `VaultItem.searchText` (`Models/VaultItem.swift:100-105`); no keyed/persisted index. | — | — | N/A. (Note the pwned-lookup cache under (non-VK) is item i-adjacent — see below.) |
| h | Sharing linkage/state — recipient (B) HPKE private key escrow | `ApprovalParticipantEscrow` CloudKit record (B's private DB), `[ver]||AES-GCM(privKey)` under VK | `Sharing/ParticipantIdentity.swift:31` | `:37` | **Y**. **TRAP** — synced CK record, not an ItemRecord. |
| h′ | Sharing state — recipient flattened shared logins (shared passwords, shared TOTP secrets, **shared passkey private keys**) | `SharedCredentialsCache` file in App Group (`sharedCredentialsCacheURL`) | `Sharing/SharedCredentialsCache.swift:93` | `:105` | **Y**. **TRAP** — on-disk file, device-local, survives lock deliberately (`SharedCredentialsCache.swift:77-84`). |
| h″ | Sharing state — recipient projection snapshot (items+grants+passkeys) | `shared-projection-snapshot.bin` in App Group | `Services/Sharing/SharedItemsProjection.swift:169` | `:157` | **Y**. **TRAP** — on-disk file, device-local. |
| i | Backup/export snapshots | `EncryptedBackup.sealed` (transient file the user exports) | `Services/ImportExport/VaultBackup.swift:122` | `:136` | **N** — sealed under a **passphrase KEK** (Argon2id), not VK; re-derived from live plaintext at export time. |
| j | Pending/outbox/sync queues | **none found** as a distinct VK-sealed queue — "dirty" is just `ItemRecord.dirty` (`Store/ItemRecord.swift:53`); the sealed bytes are the item's own. Approval request/response/grant CK records are signed/HPKE, not VK-sealed. | — | — | N/A. |
| k | App Group / AutoFill + local caches (VK-sealed) — Audit reports | `AuditReportRecord.sealed`, `FindingStateRecord.sealed` = AES-GCM(`AuditReportPayload`/`FindingStatePayload`) under VK | `Audit/AuditReportPayload.swift:51,72` (via `Services/Watchtower/AuditReportStore.swift:17,52` — "seals … under the Vault Key") | `AuditReportPayload.swift:55,76`; `AuditReportStore.swift:25,31,67` | **Y**. **TRAP** — separate record types; synced (`AuditReport`/`AuditFindingState`). |
| k′ | UI state snapshot (nav paths + in-progress editor DRAFT) | file `UIStateStore.fileURL` | `App/UIStateStore.swift:98` | `:108` | **Y** (or just delete) — on-disk, ephemeral. **TRAP.** |
| k″ | Relay principal signing key (P256) escrow | `[ver]||AES-GCM(principalID||epoch||privKey)` under VK; escrowed to a CloudKit singleton in the `Vault` zone | `Relay/RelayPrincipalIdentity.swift:89` | `:99` | **Y**. **TRAP** — has its OWN `epoch` (relay-key rotation, unrelated to VK), sealed under VK. |
| k‴ | The wrapped-key store itself | `VaultKeyBundle` file in App Group (`Keychain/VaultKeyBundle.swift:7-61`): `wrappedByPassword`, `wrappedByRecovery`, `wrappedL2SK`, `envelopePrivateKeySealed`, `envelopePublicKey` | — (wrap in `KeyHierarchy.swift:28`) | `KeyHierarchy.swift:39`; `VaultReader.swift:20` | **Y — ROTATION EPICENTER**: every VK wrap (password + recovery + biometric) must be regenerated and `envelopePrivateKeySealed` re-sealed. |
| k⁗ | Raw VK copy behind biometrics | `BiometricKeyStore` keychain item `vault.biometricKey` (Secure-Enclave-gated, shared access group) — stores the VK directly, not a wrap (`Keychain/BiometricKeyStore.swift:5-10`) | — | — | **Y** — must re-store the new VK. |

### Sealed under a NON-VAULT-KEY (independent — OUT of VK-rotation scope, listed to avoid false traps)

- `SecretGuard` inner layer → **L2SK** (level2) / **custom-code Argon2** key (`SecretGuard.swift:29-57`). L2SK itself is wrapped by an L2-password KEK in `VaultKeyBundle.wrappedL2SK` (`VaultKeyBundle.swift:30-35`).
- `VaultBackup` export → **passphrase KEK** (`VaultBackup.swift:118-123`).
- `AuditLocalCache` (device-local pwned-lookup cache) → **dedicated 64B keychain secret** `audit-pwned-cache-secret` (HMAC+AES halves), NOT VK, NOT synced (`Services/Watchtower/AuditLocalCache.swift:9-10,47-49,96,107`).
- `InviteLinkService` public-DB rendezvous → **ephemeral per-invite 32B link key** carried in the URL `#k=` fragment; payload is only the CKShare URL, not vault secrets (`Services/Sharing/InviteLinkService.swift:69-71,87,130`).
- Approval shared-field / display / response / invite blobs on CloudKit → **HPKE to recipient/ephemeral/device keys** (see §2), never VK.
- `VaultKeyBundle.wrappedByPassword/Recovery` → password/recovery KEK (`VaultKeyBundle.swift:14-28`).

**Rotation-scope headline:** VK seals FAR more than `ItemRecord`. Non-ItemRecord VK-sealed surfaces that a rotation must re-seal/regenerate: item avatars (a′), attachments files (c), passkeys + envelope key (e), personas/folders/aliases/inboxes (f–f‴), audit report/finding records (k), UI-state file (k′), relay principal escrow (k″), participant-identity escrow (h), shared-credentials cache (h′), shared-projection snapshot (h″), the `VaultKeyBundle` (k‴), and the biometric raw-key item (k⁗). Attachments, shared caches, passkeys, and the UI-state file are on-disk/device-local (not reachable by a pure server re-encrypt); personas/folders/aliases/inboxes/audit/participant-escrow/relay-escrow are synced CK records.

---

## 2. HPKE INFO / AAD BINDING (family-sharing transport)

Seal core: `ApprovalSeal.seal(_:recipientKeyRaw:info:)` (`Sharing/ApprovalCrypto.swift:152-162`) = `HPKE.Sender(recipientKey:, ciphersuite: Curve25519_SHA256_ChachaPoly, info:)` then **`sender.seal(plaintext)`** — plain overload, **NO `authenticating:` AAD**. So the ONLY per-message context binding is the HPKE `info`. Envelope wire = `version(1)||encap(32)||ct`.

**Shared field value** (the main transport; sealed in `publishGrant`, `ApprovalShareService.swift:257-276`):

- v1 path (`sealSharedField`, `ApprovalCrypto.swift:223-226`) → `info = sharedFieldInfo(grantId, fieldId)`, built by the canonical (length-prefixed) writer (`ApprovalCrypto.swift:106-112`):
  ```
  CanonicalWriter: string("Loox shared field v1"); string(grantId); string(fieldId)
  ```
- v2 per-device path (`sealSharedFieldForDevice`, `ApprovalCrypto.swift:237-243`) → `info = sharedFieldInfoV2(grantId, fieldId, deviceKeyID)` (`:125-133`):
  ```
  CanonicalWriter: string("Loox shared field v2"); string(grantId); string(fieldId); blob(deviceKeyID)
  ```
Recipient open re-derives the SAME info from `(grantId, fieldId[, deviceKeyID])` (`Services/Sharing/ApprovalRecipientService.swift:319-326`).

**Does it vary by field kind?** No. Identical construction for password/username/url/text, TOTP-`shared` seed, and passkey-`shared` private key. The only per-field discriminator is `fieldId` = `DynamicField.id` (or the synthetic passkey slot id `passkey::<hex>`, `Sharing/ApprovalModels.swift:87-99`). Capability/kind is a separate authorization check (`grant.capabilities[fieldId]?.isSharedValue`, `ApprovalRecipientService.swift:315`), not a crypto binding.

**Bound vs NOT bound in the shared-field seal:**

| Element | Bound? |
|---|---|
| protocol/version tag | **YES** — literal `"Loox shared field v1"`/`"v2"` (domain-sep + version) |
| grantId | **YES** |
| fieldId | **YES** |
| recipient device key id (`deviceKeyID`) | **YES (v2 only)** |
| environment | NO |
| zone identity (zoneName) | NO |
| owner principal id / owner signing pubkey | NO |
| owner persona id | NO |
| recipient principal id (opaque `recipientId`) | NO |
| itemId | NO |
| fieldKind | NO |
| capability | NO |
| any per-message AAD beyond `info` | NO (plain `seal`) |

**Sibling seals for reference** (same file): display envelope `info = "Loox display envelope v1" + grantId` / v2 `+ deviceKeyID` (`:114-119,135-141`); askEachTime response `info = "Loox approval response v1" + requestId + nonce` (`:98-104`); invite `info = "Loox invite envelope v1" + inboxID` (`:143-148`).

**What the owner SIGNATURE binds** (grant is signed, not sealed) — `AccessGrant.signingBody()` (`Sharing/ApprovalCanonical.swift:161-197`): version+typeTag(grant), grantId, itemId, `recipientId` (opaque), participantPubKey, pinnedDeviceSigningKeys[], capabilities{fieldId→cap}, [v2: deviceScope + deviceKeyBindings{deviceKeyID, hpkePublicKeyHash}], epoch, createdAtUnixMs, expiresAtUnixMs, ownerSigningPubKey. **NOT signed: zoneName, environment, owner persona.** So authorization binds itemId + recipient key material + capabilities + epoch, but is NOT tied to the zone it lives in.

---

## 3. ZONE / RECIPIENT IDENTITY

**Zone name derivation (per share):** `ApprovalConfig.opaqueZoneName()` = `"apz-" + opaqueName()`, where `opaqueName()` = 20 bytes CSPRNG hex (`Sharing/ApprovalConfig.swift:81-89`). Called at `ApprovalShareService.swift:79` (`existingZoneName ?? ApprovalConfig.opaqueZoneName()`).
```
static let zonePrefix = "apz-"
static func opaqueName() -> String { CryptoRandom.bytes(20).map { String(format: "%02x", $0) }.joined() }
static func opaqueZoneName() -> String { zonePrefix + opaqueName() }
```
Zone name is **pure random / meaning-free by design** (`ApprovalConfig.swift:5-8,77-89`). **It binds NOTHING** — no persona, no recipient, no item, no field. (The private vault-sync zone is the fixed `CKRecordZone(zoneName: "Vault")`, `Services/Sync/CloudSyncService.swift:22`; approval zones are separate custom zones in the same container `iCloud.com.bervion.vaultify`.)

**Persona binding in the zone:** NONE.

**Recipient identity:**
- Crypto identity = `ParticipantIdentity` (B's persistent Curve25519 HPKE key, `Sharing/ParticipantIdentity.swift:13-20`) + per-device `DeviceHPKEIdentity` (`Sharing/DeviceHPKEIdentity.swift`) + P256 device signing keys, published in the `ApprovalParticipantProfile` record (`ApprovalRecordMapping.swift:135-181`).
- In the grant, the recipient is named by `recipientId = ApprovalConfig.opaqueName()` — **opaque, never email/name** (`ApprovalShareService.swift:222`; `Sharing/ApprovalModels.swift:210-211`).
- Trust is established out-of-band via `TrustFingerprint.code(ownerSigningPubKey, participantPubKey)` (`ApprovalCrypto.swift:321-333`) then **TOFU-pinned**: value decryption is gated on `pinnedOwnerKey(zoneID) == grant.ownerSigningPubKey` (`ApprovalRecipientService.swift:293-295,337`), and v2 additionally requires this device ∈ signed bindings AND live pubkey-hash match (`:301-309`).

**Email as identity?** Email is used ONLY for (1) the CloudKit CKShare participant invite — `container.shareParticipant(forEmailAddress:)` + `share.addParticipant` (`ApprovalShareService.swift:73-91`), i.e. Apple's transport-level ACL for who may accept the zone share; and (2) UI label / dedupe — `recipientLabel`/`normalizedEmail` (`Features/Sharing/ShareAccessSheet.swift:80-88,279,316,448`; `Features/Sharing/SharingStore.swift:38`). Email is **NOT** bound into the grant crypto, **NOT** in any HPKE `info`, **NOT** in the signed grant body, and the grant's `recipientId` is opaque. So email = transport-invite + UI discovery only; it never gates value crypto (that is the fingerprint pin + participant/device keys).

---

## 4. EPOCH / VERSION / ROTATION / GENERATION

**No vault-key epoch/generation exists today.** Confirmed:
- `ItemRecord` has NO version/epoch/keyId column (`Store/ItemRecord.swift:9-72`). Nor do Folder/Persona/Alias/Inbox/Audit records.
- The only `epoch` fields are unrelated sub-systems:
  - `AccessGrant.epoch: UInt32` — sharing-grant revoke counter (bumped on revoke; requests verified against current epoch) — hard-coded `epoch: 1` at creation (`Sharing/ApprovalModels.swift:218-219`; `Features/Sharing/ShareAccessSheet.swift:432`).
  - `RelayPrincipalIdentity.epoch: UInt64` — email-relay signing-key rotation counter (`Relay/RelayPrincipalIdentity.swift:20,75-78`).
- `VaultKeyBundle.version: Int` (=1) is a bundle FILE-FORMAT version, not a key generation (`Keychain/VaultKeyBundle.swift:8,43`).
- `schemaVersion` hits are all wire/attestation models (`CapabilityManifest`, `QuickViewSignerKeyset`, `DomainRegistryDocument`, `CapabilitySnapshot`) — NOT the vault store.

**Store schema / migration mechanism:** SwiftData `ModelContainer` built directly with the model list and **`cloudKitDatabase: .none`** — **no `VersionedSchema`, no `SchemaMigrationPlan`** anywhere (`Store/VaultStore.swift:25-39`). Migrations therefore run as SwiftData's default lightweight/automatic inference; there is no explicit migration stage to hang a key-epoch rewrite on. `ItemSecret` does soft back-compat via a custom `init(from:)` (missing keys default, `Models/VaultItem.swift:141-149`) — the established pattern for evolving sealed payloads without a migration.

---

## 5. WRITE / MERGE PATH (sync PULL) — best epoch-gate insertion point

**Pull entry:** `CloudSyncService.pull()` (`Services/Sync/CloudSyncService.swift:154-169`) uses `ZoneDeltaFetch.pull(database:zoneID:cursor:)` and dispatches every fetched record through ONE closure by `recordType` → `apply` / `applyFolder` / `applyPersona` / `applyAlias` / `applyInbox` / `applyAuditReport` / `applyFindingState`.

**Item merge lands in:** `apply(_:)` (`CloudSyncService.swift:202-220`) reads the CK fields and calls **`store.upsertFromRemote(...)`** (`Store/VaultStore.swift:80-143`) — the actual LWW merge for items.

**Conflict resolution today (LWW, quoted `VaultStore.swift:86-128`):**
```
if let existing = record(id: id) {
    if let changeTag, changeTag == existing.ckChangeTag { return }   // same server rev → no-op
    let applyContent = updatedAt > existing.updatedAt
    let applyMeta = metaUpdatedAt > existing.metaUpdatedAt
    let localContentWins = existing.updatedAt > updatedAt
    let localMetaWins = existing.metaUpdatedAt > metaUpdatedAt
    guard applyContent || applyMeta else { ... re-dirty local winner ...; return }
    if applyContent { existing.sealed = sealed; ... existing.updatedAt = updatedAt ... }
    if applyMeta   { existing.pinned = pinned; existing.archived = archived; ... }
    ...
}
```
Two gates: content by `updatedAt`, meta (pinned/archived) by `metaUpdatedAt`; change-tag short-circuit makes re-processing the same server revision a clock-skew-proof no-op. Folders/personas/aliases/inboxes have the same single-gate shape (`VaultStore.swift:177-387`).

**Single best insertion point for a "reject/quarantine any record whose keyEpoch < committed epoch" check:** the `pull()` dispatch closure at **`CloudSyncService.swift:156-168`** — it is the ONE choke point every synced record type funnels through, BEFORE any per-type `apply*`/`upsert*`. Plumb a plaintext `keyEpoch` CK field (written alongside `sealed` in `ckRecord(from:)` etc., `CloudSyncService.swift:182-200` and siblings) and gate there:
```
// pseudo, at the top of the pull closure, before the switch:
guard (record["keyEpoch"] as? Int ?? 0) >= committedEpoch else { quarantine(record); return }
```
Rationale over the alternatives: gating inside `VaultStore.upsertFromRemote` (`:86`) would require duplicating the check across all six `upsert*FromRemote` variants; gating in each `apply*` is also N places. The `pull` closure is the sole per-record dispatch. (A `keyEpoch` field is also needed on the SEAL side and on every non-item synced record type — see §1 traps.) Note the epoch would be plaintext metadata (like `updatedAt`), so the gate is integrity-advisory, not authenticated — an attacker with write access to the private DB could forge it; the real guarantee remains that a stale-epoch record is undecryptable under the new VK.

---

## Open questions / notes for the design doc

1. **Rotation cannot be server-only.** Attachments (c), shared-credentials cache (h′), shared-projection snapshot (h″), passkeys (e), and UI-state (k′) are on-disk/device-local and NOT synced — a re-encrypt must run on each device that unlocks with the old VK, or these become permanently undecryptable after rotation. Passkeys are especially load-bearing (P256 private keys, device-local only).
2. **Two independent inner-key layers** ride inside VK-sealed data and are NOT affected by VK rotation but ARE affected by their own key loss: `SecretGuard` (L2SK/custom-code) inside items, and `wrappedL2SK` in the bundle. A VK rotation must NOT touch/discard L2SK.
3. **Relay principal escrow (k″)** already models an epoch-rotation ceremony (`RelayPrincipalIdentity.rotated()`, `:75-78`) — a possible reference pattern for VK rotation, though it rotates a signing key, not a symmetric data key.
4. **Sharing grant is not zone-bound** (§2/§3): `signingBody` omits zoneName, and shared-field HPKE `info` omits zone/owner-principal. If the rotation design wants shares to survive/rebind across a VK rotation, note the transport identity is the recipient's HPKE key + owner signing key (TOFU pin), decoupled from VK — owner VK rotation does NOT invalidate published grants (grants carry no VK-derived material).
5. `ExtensionSessionStore` (`Keychain/ExtensionSessionStore.swift`) and the biometric raw-key item (k⁗) are minted from the biometric path; both are torn down on biometric invalidation (`BiometricKeyStore.swift:82-89`) — verify they are also refreshed on rotation.
