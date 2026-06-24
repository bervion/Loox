---
title: Identity & Profile Feature
description: >-
  Mandatory default identity at onboarding + Profile screen (avatar,
  default-identity switch, payment cards, per-field copy). Default identity =
  synced ItemRecord column.
status: pending
priority: P2
branch: main
tags:
  - identity
  - profile
  - sync
  - onboarding
  - tdd
blockedBy: []
blocks: []
created: '2026-06-24T03:02:00.500Z'
createdBy: 'ck:plan'
source: skill
---

# Identity & Profile Feature

## Overview

Make every install own ≥1 **default identity** (an `ItemCategory.identity` vault item), surfaced
through a new **Profile** screen (avatar, default-identity switch, payment cards list, per-field
copy). Default-identity marker is a **synced plaintext column on `ItemRecord`** (`isDefaultIdentity`),
mirroring the `pinned`/`archived` pattern — NOT a local `SettingsStore` flag (UserDefaults is
device-local and not in CloudKit, so a local pointer breaks multi-device).

Authoritative spec: `plans/reports/brainstorm-summary-260624-0959-identity-profile-feature-report.md`

**Autofill scope (this round) = manual copy.** iOS `ASCredentialProviderExtension` cannot auto-fill
name/address/card into 3rd-party web forms; auto web-fill is deferred (future: in-app browser /
iOS18 insert-text). Profile exposes per-field copy buttons (clipboard auto-clear already exists).

TDD: phases 1–3 carry pure/near-pure logic with a ready harness (`VaultRepositoryFolderTests`
pattern: in-memory `VaultStore` + `session.adoptUnlocked`). Tests-first per phase. Phase 4 is UI —
automated coverage limited to avatar-store round-trip + seed/copy helpers; rest is manual verify.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Data Model & Sync Column](./phase-01-data-model-sync-column.md) | Completed |
| 2 | [Default-Identity Invariant](./phase-02-default-identity-invariant.md) | Completed |
| 3 | [Onboarding Identity Step](./phase-03-onboarding-identity-step.md) | Completed |
| 4 | [Profile Screen & Avatar](./phase-04-profile-screen-avatar.md) | Pending |

## Key Decisions (locked)

- Reuse `ItemCategory.identity` item; extend its `fieldTemplate`. No new entity (DRY).
- New `ItemRecord` columns (defaulted/optional → SwiftData lightweight migration ok), both synced:
  `isDefaultIdentity: Bool`, `avatarSealed: Data?` (avatar). (Sync gate is whole-record LWW by
  `updatedAt`, so `setDefaultIdentity`/`setAvatar` bump `updatedAt`; the once-planned
  `defaultIdentitySetAt` column was dropped as redundant.)
- Single active default enforced in-app; `normalizeDefaultIdentity()` converges sync conflicts by
  `max(updatedAt)` (then `createdAt`).
- "≥1 identity" enforced at UI mutation gates (trash/archive); zero-identity → empty-state CTA (no fabrication).
- Profile entry = avatar in `HomeHeaderBar`.
- Avatar = ≤256px JPEG, AES-GCM sealed in `ItemRecord.avatarSealed` → syncs cross-device.

## Review gate (red-team + validate) — RESOLVED

Report: `reports/red-team-and-validate-260624-1008-identity-profile-plan-review-report.md`. All findings
applied; both decisions resolved by user:
- **F1 (sync tie-break) = `updatedAt`.** Sync gate (`VaultStore.upsertFromRemote`) is whole-record LWW
  by `updatedAt`, so synced changes must bump `updatedAt`; `setDefaultIdentity`/`setAvatar` do →
  `updatedAt` tracks the default change. Winner: `max(updatedAt)` → tie `max(createdAt)`. The
  `defaultIdentitySetAt` column was dropped as redundant (discovered at implementation).
- **F4 (avatar) = sync cross-device.** Avatar = ≤256px JPEG, AES-GCM sealed, stored in new
  `ItemRecord.avatarSealed: Data?` column → rides the item CKRecord (zero-knowledge). Resolves F3
  (no orphan: column dies with record).
- Also enforced: zero-identity empty state (existing TestFlight users have no identity item).

## Dependencies

- Phase 2 blockedBy Phase 1 (needs column + mirror).
- Phase 3 blockedBy Phase 1 (needs column + seed helper).
- Phase 4 blockedBy Phases 1–3.
- No cross-plan dependencies (scan clean: no overlapping identity/profile plans).

## Out of scope

Automatic web form filling; per-identity card ownership/linking; multiple profile roles
(`isDefaultIdentity: Bool`, not `profileRole: String?`).
