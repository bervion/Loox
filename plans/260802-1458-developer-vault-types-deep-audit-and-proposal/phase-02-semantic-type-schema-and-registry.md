---
title: "Phase 2: Semantic Type Schema and Registry"
status: todo
---

# Phase 2: Semantic Type Schema and Registry

## Outcome

Create the open, additive domain contract that lets Vaultify add useful types without enum/switch
explosion, editable-label behavior, or cross-version disappearance.

## Requirements

- [ ] Stable namespaced string `ItemKindID`, `FieldRoleID`, and schema/template versions.
- [ ] Presentation, semantics, sensitivity, access policy, and lifecycle are independent dimensions.
- [ ] Built-in compile-time `ItemTemplateRegistry`; no downloaded/community template code.
- [ ] Central `ItemCapabilityResolver` is fail-closed and is the only authority used by integrations.
- [ ] All new fields are optional/additive and legacy items receive authoritative roles only where inference is provable.
- [ ] Unknown IDs within a supported schema preserve raw identifiers. Unsupported future schema is
  generic read-only/recovery and retains the original sealed payload without typed re-encoding.

## Proposed Contracts

```swift
struct ItemKindID: RawRepresentable, Codable, Hashable, Sendable { let rawValue: String }
struct FieldRoleID: RawRepresentable, Codable, Hashable, Sendable { let rawValue: String }

struct ItemSemantics: Codable {
    var schemaVersion: Int
    var kindID: ItemKindID?
    var templateVersion: Int?
    var links: [ItemLink]?
}

struct FieldSemantics: Codable {
    var roleID: FieldRoleID?
    var sectionID: String?
    var sensitivity: Sensitivity?       // public, private, secret, keyMaterial
    var actionAuthorization: ActionAuthorization? // none, reauthenticate, level2-code prompt
    var cryptoProtection: CryptoProtection?       // vaultKey, level2Key
    var lifecycle: FieldLifecycle?      // changedAt, expiresAt, rotateDays
}
```

Registry policy is a trusted minimum. Imported/stored policy may only tighten it, never relax it:
`effective = stricter(registryMinimum, storedPolicy)`. A known role on the wrong template, wrong
cardinality, malformed value, missing policy, or unsupported schema receives secret-safe defaults and
zero external capability. Capabilities are derived, not user-stored: password AutoFill, text insertion, Safari fill,
password audit, sharing, plaintext export, clipboard, search indexing, re-auth, and expiry audit.

## File Inventory

- Add core type/role/policy models under `VaultifyCore/Models/`.
- Add `VaultifyCore/Types/ItemTemplateDefinition.swift`, `ItemTemplateRegistry.swift`,
  `ItemCapabilityResolver.swift`, and legacy inference/migration helpers.
- Modify `DynamicField.swift`, `VaultItem.swift`, `ItemCategory.swift`, and `ItemSecret` codec.
- Route `VaultReader`, `WebExtensionReader`, Watchtower rules, rotation, sharing safelists,
  search projection, backup, and export through the resolver.
- Inventory and migrate every direct category/kind/password/totp consumer, including
  `CredentialIdentityService`, AutoFill UI, Quick View/Link, Approval/Space sharing, credential exchange,
  Home attention, CSV export, rotation, and TOTP identity. Prefer typed projections and add a CI rule
  preventing new direct eligibility checks outside the resolver/projection allowlist.
- Keep parser/import/artifact unwrap/export services in the app target. AutoFill/Safari compile only pure
  model and resolver surfaces; add dependency/command tests preventing those targets from gaining artifact APIs.
- Add contract tests under all three targets where shared Core behavior compiles.

## Implementation Steps

1. Write ADR and wire contract first. Use stable lowercase namespaced IDs such as
   `credential.login`, `developer.ssh-key`, and `ssh.private-key`. Every incompatible wire addition or
   new closed-value variant must bump `schemaVersion`.
2. Add optional semantic payload fields. Keep legacy `category` and `kind` for downgrade rendering;
   do not create a SwiftData migration for data already inside sealed JSON.
3. Implement conservative legacy inference. Current template field IDs are random, so assign an
   authoritative role only where category/kind/cardinality makes it provable. Label aliases and position
   may suggest a user-confirmed conversion but never grant AutoFill/share/export authority. Ambiguous
   fields remain role-less and safe; all newly created templates write roles immediately.
4. Define template descriptors: localized name/blurb, Polaris asset, family, sections, default fields,
   validator IDs, summary provider, action IDs, importer IDs, and version.
5. Implement a pure capability resolver. Unknown type/role defaults to visible, non-fillable,
   non-shareable, non-exportable, and secret-safe.
6. Replace kind/label checks surface by surface. Delete old paths only after parity tests prove all
   eight legacy categories behave intentionally.
7. Enforce capability at producer and consumer boundaries. A sender's serialized sensitivity is metadata,
   never authority; recipient extensions independently resolve known template/role capability.
8. Add lazy migration on successful unlock/edit. Migration failure retains original ciphertext and
   creates a diagnostic; it never partially rewrites an item.
9. Define template-version behavior: IDs/roles are append-only; version is creation provenance; registry
   retains render/policy support for active versions; required fields are not silently re-added; upgrades
   are explicit/idempotent and never grant a new capability without confirmation.

## Verification Matrix

- Golden JSON for pre-semantic, current-semantic, unknown IDs under supported schema, and unsupported
  future schema with unknown item/field keys and policy variants. Unsupported schema cannot be edited and
  re-sealed; recovery/export preserves original ciphertext.
- Exhaustive capability table for every built-in kind/role across AutoFill/Safari/audit/share/export.
- Label/localization mutation tests proving behavior remains unchanged.
- Real previous-release compatibility: new create → previous binary read/edit/sync → new read, under the
  minimum-writer protocol. Downgrade below the writer floor is explicitly unsupported.
- Hostile import/backup fixtures cannot lower registry sensitivity/authorization or spoof kind-role membership.
- Performance: registry lookup and summary projection do not materially regress unlock/list/search.

## Risks and Mitigations

- Duplicate sources of truth: legacy category is presentation fallback only; resolver uses semantic ID
  when present and a single tested inference path otherwise.
- Capability drift: exhaustive compiler-visible registry tests fail when a new type lacks a policy.
- Over-general schema: v1 registry supports built-ins only; defer arbitrary user-defined validation DSL.

## Success Criteria

- [ ] No product behavior depends on a localized/editable field label.
- [ ] Supported-schema unknown IDs survive decode-edit-encode; unsupported schema remains read-only and intact.
- [ ] All integrations use the centralized resolver.
- [ ] Legacy values are byte-for-byte unchanged; authoritative roles are assigned only where provable.
