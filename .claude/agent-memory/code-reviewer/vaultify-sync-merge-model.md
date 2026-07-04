---
name: vaultify-sync-merge-model
description: Phase-3 CloudKit sync merge model (two-gate LWW, changeTag short-circuit, snapshot markSynced) + known divergence gap found in review
metadata:
  type: project
---

Phase 3 sync merge model (plan 260704-1751): `VaultStore.upsertFromRemote` has TWO LWW gates — content by `updatedAt` (sealed/favorite/trashedAt/deletedAt/isDefaultIdentity/avatarSealed), meta by `metaUpdatedAt` (pinned/archived). `useCount`/`lastUsedAt` device-local, never synced. changeTag equality short-circuits re-pulls. `markSynced` clears `dirty` only when timestamps match the pre-push snapshot.

**Why:** pinned/archived deliberately don't bump `updatedAt` (keeps "Recently Modified" clean), so they need their own timestamp or pulls drop them.

**How to apply:** when reviewing sync changes, any new synced column must join one of the two gates AND bump its gate's timestamp on write, or it silently fails to propagate.

Known gap flagged in Phase-3 review (verify if fixed before re-flagging): sync() pushes BEFORE pulling with savePolicy `.changedKeys` on fresh CKRecords (no server tag) → blind server overwrite; when the local-newer side loses on the server, `upsertFromRemote`'s early return (VaultStore.swift ~75-78) does NOT mark it dirty → newer edit never re-pushes → permanent divergence until next edit. Recommended fix: mark dirty on changeTag-mismatch + strict local win (beware equal-timestamp ping-pong).
