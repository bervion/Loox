---
date: 2026-08-02
session: developer-vault-types-deep-audit
---

# Developer Vault Types: We Rejected Enum Growth Before It Deepened the Damage

**Date**: 2026-08-02 15:22  
**Severity**: Critical  
**Component**: Vault schema, secret rendering, sharing, artifacts, CloudKit  
**Status**: Ongoing

## What Happened

The audit rejected adding SSH, API, Git, and Apple developer cases directly to `ItemCategory`. The closed
enum feeds one mostly flat form. More cases would multiply switches while preserving label-driven
behavior and unsafe integration inference.

Three P0 failures made expansion irresponsible. Protected multiline values can reach
`MarkdownNoteText` before the secret path in `DetailFieldRow.swift:134-184`. Sharing transports label and
kind but drops protection metadata in `SharedDisplayEnvelope.swift:14-29`, and publication can omit the
category. Attachments are device-local encrypted sidecars referenced by strings
(`AttachmentStore.swift:3-74`), so backup or sync can restore an item whose `.p8`, `.p12`, or SSH bytes do
not exist.

## The Brutal Truth

The UI looked MVP because the domain model *is* MVP. We were one “quick type pack” away from a convincing
secure-file experience that could disclose a key or silently lose it after restore. That is worse than
lacking the feature. Spending a release on foundations is frustrating, but a polished lie is reckless.

## Technical Details

The accepted design keeps the encrypted `VaultItem` aggregate but adds lossless `ItemKindID`,
`FieldRoleID`, separate sensitivity/action authorization/crypto protection, a static template registry,
and one fail-closed capability
resolver. Editable labels never grant AutoFill, Safari, audit, sharing, or export authority. Artifact v2
is a release gate: transactional ownership, cleanup, portable backup, and optional CKAsset convergence
must exist before file-backed developer types ship.

Red-team review corrected four dangerous assumptions:

- unsupported future schema is concealed read-only recovery, preserving original ciphertext;
- Release A establishes a minimum writer floor so old writers cannot erase additive semantics;
- backup unwraps artifact DEKs and rewraps them under a backup KEK before restoring to a new vault key;
- CloudKit needs per-plane/versioned cursors or a mandatory full refetch after an old client consumes an
  unknown artifact change.

## What We Tried

We compared enum expansion, one entity per type, and downloaded schemas. The first keeps the bugs, the
second duplicates storage/sync machinery, and the third creates an unnecessary plugin security platform.

## Root Cause Analysis

`FieldKind` and editable labels currently combine presentation, semantics, secrecy, and integration
eligibility. Files are encoded as field pointers instead of owned lifecycle records. The architecture has
no single authority answering what an item is allowed to do.

## Lessons Learned

Never grow a security taxonomy until unknown-version behavior, outbound capabilities, and binary recovery
are explicit. “Encrypted” does not mean durable, and “hidden” does not mean access-controlled.

## Next Steps

Release A owners implement P0 containment, semantic contracts, and real previous-writer tests first.
Artifact/crypto owners then prove new-vault backup restore and cursor upgrade behavior before Release B.
iOS ships import, inspect, copy, export, and links only; SSH agent and Git credential-helper behavior stays
a future signed macOS helper/CLI with its own IPC threat model.
