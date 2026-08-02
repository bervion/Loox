# Vault Types and Developer Workflows: Deep Audit

Date: 2026-08-02  
Scope: domain model, encryption/storage, backup/sync, sharing, AutoFill/Safari, Watchtower,
creation/editor/detail/list/search UX, and developer/iOS credential workflows.

## Executive Assessment

Vaultify has eight category labels but not eight product-quality type experiences. `login` has a
sectioned editor; the other types mostly reuse a flat dynamic-field form and a generic detail card.
The limiting factor is not the number of enum cases. It is that presentation kind, semantic role,
masking, authorization, audit, search, AutoFill, sharing, and export behavior are entangled or inferred
from editable labels and `FieldKind`.

The product should pause direct category expansion. First fix current P0 paths, then introduce a
versioned semantic schema with lossless supported IDs and centralized capability policy. Secure developer files need a new artifact
lifecycle before Vaultify can truthfully promise portable storage.

## Current-State Map

| Area | Current contract | Consequence |
|---|---|---|
| Taxonomy | Eight closed `ItemCategory` enum cases | Every type addition multiplies switches and can break old decoders |
| Template | Category returns a flat `[DynamicField]` | Template cannot express sections, repeating groups, validators, actions, or lifecycle |
| Field | label, kind, string value, protected, guard2 | No stable semantic role; binary is an encoded pointer inside a string |
| Editor | Login sectioned; all others generic fields | SSH/recovery/card/identity feel MVP and special cases leak into row code |
| Detail | One generic fields card | No type protagonist, metadata summary, or safe type-specific actions |
| Integration | Inference from `.password`, kind, or label | Developer secrets can be treated as login passwords or lose secret policy |
| Attachment | Encrypted sidecar file plus metadata pointer | Item can sync/backup while its bytes remain only on the original device |
| Compatibility | Unknown `FieldKind` falls back; category does not | Future category may make the full item undecodable and silently absent |

## Findings by Severity

### P0-1: Protected multiline values can render as plaintext

`ItemCategory` marks SSH private key and recovery codes as `protected` multiline values. The editor
uses a masked multiline component, but detail switches on `.multiline` first and sends the value to
`MarkdownNoteText`. The generic secret path does not protect that branch.

Evidence:

- `VaultifyCore/Models/ItemCategory.swift:110-116`
- `Vaultify/Features/ItemEditor/EditorFieldRow.swift:192-201`
- `Vaultify/Features/ItemDetail/DetailFieldRow.swift:134-184`

Impact: the existing developer-oriented SSH type violates the masking promise immediately after vault
unlock. Fix and regression-test before expanding type support.

### P0-2: Sharing loses category and field protection semantics

`SharedDisplayEnvelope.FieldMeta` transports label and kind but not protected/sensitivity policy.
Recipient projection rebuilds `DynamicField` without `protected`. The envelope supports an optional
category, but `publishGrant` currently does not populate it, and recipient fallback is `.login`.

Evidence:

- `VaultifyCore/Sharing/SharedDisplayEnvelope.swift:14-29`
- `Vaultify/Services/Sharing/ApprovalShareService.swift:235-252`
- `Vaultify/Services/Sharing/SharedItemsProjection.swift:452-503`

Impact: an owner-protected SSH field may become unprotected on the recipient, while the item can be
presented with login semantics. Wire changes must remain backward compatible and fail closed.

Quick Link has a related authorization gap: it excludes TOTP, files, and Level-2 values but offers
ordinary protected multiline fields. Approval Sharing starts fields off but permits the owner to opt in
any non-TOTP value. That means the current `protected` SSH private key can enter a share flow even though
the product has no developer-secret sharing policy.

Additional evidence:

- `Vaultify/Features/Sharing/LooxLink/LooxLinkEnvelope.swift:28-52`
- `Vaultify/Features/Sharing/ShareAccessSheet.swift:275-284,685-688`
- `VaultifyCore/Sharing/SpaceShareSafelist.swift:29-60` (good login-only fail-closed precedent)

Developer-secret roles should be absent from Quick Link and Approval selection in v1. Sharing must ask
the centralized capability resolver, not infer authorization from a display-masking boolean.

### P0-3: Attachments are neither complete nor portable

Attachment bytes are encrypted into the App Group container, while the item stores an `att:` metadata
pointer. The editor writes bytes before the item commit; cancel/remove/delete/erase paths do not form a
transactional lifecycle. CloudKit and encrypted backup serialize the sealed item/pointer, not the file.
Preview decrypts to a temp location without a complete cleanup lifecycle; import reads the full file
into memory and has no product size ceiling.

Evidence:

- `Vaultify/Services/AttachmentStore.swift:3-74`
- `Vaultify/Features/ItemEditor/ItemEditorScreen.swift:517-524,766-776`
- `Vaultify/Data/Repositories/VaultRepository.swift:507-518`
- `Vaultify/AppEnvironment.swift:373-405`
- `Vaultify/Features/ItemEditor/AttachmentPickerSheet.swift:39-50`
- `Vaultify/Features/ItemDetail/AttachmentFieldRow.swift:65-71`
- `Vaultify/Services/Sync/CloudSyncService.swift:347-364`
- `Vaultify/Services/ImportExport/VaultBackup.swift:132-151`

Impact: `.p8`, `.p12`, `.mobileprovision`, private-key files, or “Secure File” could appear safely
stored but be missing after restore or on another device. Do not launch those promises before Artifact v2.

### P1-1: `FieldKind` is doing too many jobs

`DynamicField` has no stable semantic role. `.password` currently means password-style presentation,
secret masking, login identity, password health, HIBP input, and rotation candidate. `.text` avoids
those integrations but loses secure defaults. PATs, API tokens, SSH passphrases, database passwords,
and `.p12` passphrases do not fit either branch.

Evidence:

- `VaultifyCore/Models/DynamicField.swift:7-35`
- `VaultifyCore/Models/FieldKind.swift:4-42`
- `VaultifyCore/VaultReader.swift:31-39`
- `VaultifyCore/WebExtensionReader.swift:46-66`
- `VaultifyCore/Audit/VaultAuditSnapshot.swift:37-69`
- `Vaultify/Services/Watchtower/Rules/PwnedPasswordRule.swift:16-25`
- `Vaultify/Data/Repositories/VaultRepository.swift:418-433`

Impact: adding developer types with the existing primitives produces wrong behavior by construction.

### P1-2: Editable/localized labels control behavior

Labels are user-editable and localized, but card rendering and Safari identity/card mapping compare
English label strings. Renaming/localization can silently change fill/render semantics.

Evidence:

- `Vaultify/Features/ItemEditor/EditorFieldRow.swift:302-309`
- `Vaultify/Features/ItemDetail/DetailFieldRow.swift:32-35`
- `VaultifyCore/WebExtensionFillPayload.swift:44-135`

Impact: behavior is not stable under customization, VI localization, or future copy changes. Stable
roles must be the sole behavioral key; labels become display-only.

### P1-3: Forward compatibility can hide data

`FieldKind` has an unknown fallback, but `ItemCategory` uses synthesized enum decoding. A newer raw
category can fail the complete secret decode. Repository reload catches and skips failures, so users see
a missing item rather than an unsupported item. Backup maps unknown categories to `.custom` and loses
the original identity; sharing falls back to `.login`.

Evidence:

- `VaultifyCore/Models/FieldKind.swift:18-23`
- `VaultifyCore/Models/ItemCategory.swift:4-13`
- `Vaultify/Data/Repositories/VaultRepository.swift:54-73`
- `Vaultify/Services/ImportExport/VaultBackup.swift:158-176`
- `Vaultify/Services/Sharing/SharedItemsProjection.swift:496-503`

Impact: adding a closed enum case without a compatibility release can make cross-version CloudKit data
appear lost. Unknown identity must be a preserved string, with a safe generic presentation.

### P1-4: Backup is encrypted but incomplete

Portable backup omits stable item IDs, favorite/pinned/icon state, rotation metadata/timestamps, and
attachment bytes. Version is decoded without a strict compatibility policy; import adds sequentially
without a transaction.

Evidence:

- `Vaultify/Services/ImportExport/VaultBackup.swift:5-57,132-181`
- `Vaultify/Features/Settings/ImportView.swift:159-179`

Impact: restore is a partial re-creation, not a faithful vault recovery. Binary developer assets raise
the severity and require a versioned, all-or-nothing backup contract.

### P1-5: `protected` is masking, not an access policy

The whole item is encrypted by the vault key. `protected` largely drives display/copy behavior; only
`guard2`/SecretGuard adds separate cryptographic protection. A private key may be hidden but still not
require biometric/Level 2 authorization per use. Sensitive iOS pasteboard writes expire but are not
marked local-only.

Evidence:

- `VaultifyCore/Models/DynamicField.swift:12-19`
- `VaultifyCore/SecretGuard.swift:3-18`
- `VaultifyCore/Platform/PlatformPasteboard.swift:19-27`

Impact: sensitivity, action authorization, crypto protection, sharing, and display masking need separate contracts.

### P1-6: CloudKit optional-clear and attachment planes need contract tests

The item mapper creates changed-key records but omits optional fields when nil; this can fail to clear
an old server value. The passkey plane already uses sentinel values and exact mapping tests, while item
records do not have equivalent coverage. Attachment bytes have no CloudKit plane.

Evidence:

- `Vaultify/Services/Sync/CloudSyncService.swift:235-287,347-384,453-484`
- `VaultifyTests/PasskeyCloudMappingTests.swift:92-99`

Impact: avatar/trash/delete state can diverge, and developer artifacts cannot converge. Add exact record
contract tests before expanding sync schema.

### P2: Ciphertext lacks object/purpose binding

The AES-GCM helper does not supply authenticated additional data. Item and attachment ciphertext are
therefore not cryptographically bound to record ID, field purpose, object type, or schema version.

Evidence: `VaultifyCore/Crypto/AESGCM.swift:4-29`.

Impact: swapping ciphertext under the same vault key may decrypt under the wrong identity/context.
Artifact v2 should use domain-separated AAD or an established envelope construction. Migrating all
legacy item ciphertext is a separate hardening project and should not block the semantic foundation.

## Root Causes

1. Closed taxonomy combines persistence identity and UI category.
2. Field kind combines control rendering, domain meaning, sensitivity, and integration eligibility.
3. Integrations each infer their own capabilities instead of consulting one policy authority.
4. Files are treated as a field encoding rather than an owned aggregate with state transitions.
5. Most feature screens render a generic field list, so type-specific workflow is implemented as label/kind exceptions.

## Recommended Product Model

Retain the common encrypted aggregate and add optional semantics:

- `ItemKindID`: lossless namespaced string.
- `FieldRoleID`: lossless namespaced string.
- `Sensitivity`: public/private/secret/keyMaterial.
- `ActionAuthorization`: none/device-owner re-auth/action-bound grant.
- `CryptoProtection`: vault key or Level-2 key/envelope.
- `FieldLifecycle`: changedAt/expiresAt/rotateDays.
- `ItemLink`: typed relationship to another vault item without secret duplication.
- `ItemTemplateDefinition`: localized composition, validation, summaries, actions, and import handlers.
- `ItemCapabilityResolver`: the only integration policy authority; unknown means fail closed.
- `ArtifactRecord`: first-class encrypted binary ownership and lifecycle.

## Recommended Developer Portfolio

### Release B: highest value, bounded risk

1. Enhanced SSH Key.
2. API Token / Secret.
3. Git Hosting Account with typed links to PAT/SSH/signing/recovery items.

### Release C: iOS developer specialization

4. App Store Connect API Key.
5. APNs Authentication Key.
6. Apple Signing Identity.
7. Provisioning Profile.
8. TLS Certificate.

### Follow-on after evidence

9. Server / SSH Connection.
10. Database Credential.
11. Environment Secret Set.
12. Cloud service account JSON and CI/CD secret.
13. Secure File only after artifact soak and quota/size policy validation.

## Product Boundaries

On iPhone, iPad, and the existing macOS app, Vaultify can store/import/inspect/copy/export assets, track
expiry, construct setup snippets, and link related credentials. The current macOS target must share safe
decode/resolver/storage behavior, even if developer UI remains iPhone-first. It still cannot act as the
agent/helper process used by Git or SSH in a terminal. That future helper/CLI needs signed IPC, sandbox,
code-signing, and a separate threat model.

## Proposed Metrics

- Item picker type found in under 10 seconds.
- SSH import and save completed in under 60 seconds.
- At least 90% of items in top developer templates need no custom field.
- Zero unintended integration eligibility in exhaustive type/role tests.
- Zero orphan ciphertext or plaintext temp artifacts after lifecycle tests.
- 100% legacy values remain intact; unknown IDs in supported schema round-trip. Unsupported future
  schema remains concealed/read-only with original sealed bytes preserved for encrypted recovery.
- 100% affected user strings have EN and VI values, existing JA coverage is preserved, and all touched screens pass Design DNA.

## Recommended Default Assumptions

- Keep offline-first/zero-backend; CloudKit remains opt-in.
- Private key, token, `.p8`, and `.p12` export requires re-auth by default.
- Developer artifacts are small, bounded credential files, not a general document vault.
- Git support means asset/link/snippet management in iOS v1, not seamless terminal authentication.
- Remote template distribution and network credential validation remain out of scope.
