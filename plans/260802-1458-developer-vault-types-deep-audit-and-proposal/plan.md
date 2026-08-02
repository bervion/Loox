---
title: "Developer Vault Types Deep Audit and Proposal"
description: "Evolve Vaultify from label-driven MVP item forms into a backward-compatible semantic vault platform for SSH, Git, API credentials, and Apple developer assets."
status: pending
priority: P0
effort: "Provisional 12-20 engineer-weeks for one senior engineer; re-estimate after compatibility and artifact-crypto spikes"
tags: [vault-types, developer-tools, ios, security, ux, migration]
blockedBy: []
created: 2026-08-02
---

# Developer Vault Types Deep Audit and Proposal

## Decision

Do not add more cases directly to `ItemCategory`. Keep the existing encrypted `VaultItem`
aggregate, then add a backward-compatible semantic layer: stable string `ItemKindID`, stable
`FieldRoleID`, sensitivity/action authorization/crypto protection, a compile-time template registry, and a centralized
fail-closed capability resolver. Developer files become first-class encrypted artifacts only
after their save, sync, backup, restore, deletion, and temporary-export lifecycle is complete.

## Why This Is P0

- Protected multiline values such as SSH private keys and recovery codes can render as plaintext
  in detail today.
- Sharing drops field protection metadata and does not publish the item category.
- A PAT, API token, or SSH passphrase represented as `.password` leaks into login AutoFill and
  password-health semantics; represented as `.text`, it loses secret defaults.
- Attachment records are pointers to device-local ciphertext. Backup and CloudKit can restore a
  convincing item whose file bytes do not exist.
- Unknown future `ItemCategory` values can fail decoding and the repository silently omits them.

## Product Scope

| Release | Outcome | Estimate |
|---|---|---:|
| A: Trust foundation | P0 rendering/share fixes, supported-schema semantics, writer-floor protocol, capability contracts | 3-4 weeks |
| B: Portable Developer Core | Artifact v2 local lifecycle + backup/stable IDs, template UX, SSH import-first, API Secret, Git links | 5-7 weeks |
| C: Synced Apple Developer | CKAsset convergence, ASC/APNs keys, signing identity/profile, multi-platform QA | 4-7 weeks |

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Eliminate current secret-rendering, sharing, decode-loss, and wrong-integration paths | P0 |
| 2 | Make type behavior depend on stable semantics, never editable/localized labels | P0 |
| 3 | Ship useful iPhone-first SSH, API, Git, and Apple developer workflows with safe iPad/Mac compatibility | P1 |
| 4 | Make imported key/certificate files durable across cancel, delete, backup, restore, and optional sync | P1 |
| 5 | Replace the flat MVP form with localized, accessible, template-specific creation, editor, and detail UX | P1 |

## Dependency and Estimate Model

| Phase | Depends on | p50 / p90 engineer-days | Primary ownership |
|---|---|---:|---|
| 1 | none | 3 / 5 | security + sharing/detail contracts |
| 2 | 1 | 8 / 13 | Core schema, compatibility, integrations |
| 3 | 2 + crypto/CloudKit spikes | 15 / 28 | artifact storage, backup, sync |
| 4 | 2; artifact UI waits for 3 | 8 / 13 | product UI/Design System/localization |
| 5 | 2 + 3 + 4 | 12 / 20 | developer workflows/SSH parser |
| 6 | 2 + 3 + 4 | 10 / 20 | Apple parsers/artifact UX |
| 7 | cross-cutting at every release | 6 / 12 | QA, migration, release operations |

Re-estimate after one-week combined spikes for unknown-payload/writer-floor behavior, the artifact
encryption construction, and Apple/SSH parser choices. Shared files have one active owner per phase;
parallel work starts only after an explicit file-ownership split.

## Non-goals for This Plan

- An SSH agent or Git credential-helper; the existing macOS app must decode/render the new model safely,
  but seamless terminal integration needs a future signed helper/CLI process, IPC, and threat model.
- Executing commands or snippets, cloning repositories, validating credentials over the network,
  installing identities into another app's Keychain, or automatically revoking provider secrets.
- Remote/community templates, arbitrary project archives, source repositories, or large-file storage.
- Exposing developer secrets to the Safari content script or broadening `getFillPayload`.

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Correctness and Compatibility Guardrails](./phase-01-start.md) | Pending |
| 2 | [Semantic Type Schema and Registry](./phase-02-semantic-type-schema-and-registry.md) | Pending |
| 3 | [First-Class Secure Artifact Lifecycle](./phase-03-first-class-secure-artifact-lifecycle.md) | Pending |
| 4 | [Template-Driven Vault UX](./phase-04-template-driven-vault-ux.md) | Pending |
| 5 | [Developer Core Pack: SSH, API, and Git](./phase-05-developer-core-pack-ssh-api-and-git.md) | Pending |
| 6 | [iOS Developer Asset Pack](./phase-06-ios-developer-asset-pack.md) | Pending |
| 7 | [Rollout, Migration, and Quality Gates](./phase-07-rollout-migration-and-quality-gates.md) | Cross-cutting |

## Delivery Gates

1. Phases 1-2 ship before any new developer type.
2. SSH original-file import and Git links wait for Phase 3 local lifecycle plus portable backup with
   stable item IDs. Text-only API Secret can be the first visible developer template after Phase 2/4.
3. No developer type ships until exhaustive capability tests prove it is absent from password
   AutoFill, password scoring/HIBP, Safari bridge, and default sharing.
4. Release B requires restore into a completely new vault/Keychain. Release C requires two-device
   CloudKit artifact convergence. Secure File remains deferred until post-release artifact metrics are clean.

## Success Criteria

- [ ] 100% of legacy items preserve category, field values, IDs, and user metadata through migration.
- [ ] Unknown IDs within a supported schema remain visible and round-trip; unsupported future schema is
      generic read-only/recovery and retains original ciphertext without typed re-encoding.
- [ ] Zero developer secrets enter login AutoFill, Safari fill, password health, or default sharing.
- [ ] Protected multiline values never appear before explicit reveal authorization.
- [ ] SSH fingerprints match `ssh-keygen`; import/export preserves original bytes.
- [ ] Cancel/delete/erase leaves zero orphan artifacts; export temp files are cleaned on dismiss,
      vault lock, and cold launch.
- [ ] Artifact ciphertext survives encrypted-backup restore and optional two-device CloudKit sync.
- [ ] All affected screens pass mandatory EN/VI, preserve existing JA catalog coverage, and pass
      Dynamic Type, VoiceOver, light/dark, Reduce Motion,
      Reduce Transparency, increased contrast, and 44pt target checks.

## Supporting Reports

- [Deep audit](./reports/deep-audit-report.md)
- [Product and platform benchmark](./reports/research-benchmark-report.md)
- [Architecture decision record](./reports/architecture-decision-record.md)
- [Red-team and validation log](./reports/red-team-validation.md)

<!-- slug: developer-vault-types-deep-audit-and-proposal -->
