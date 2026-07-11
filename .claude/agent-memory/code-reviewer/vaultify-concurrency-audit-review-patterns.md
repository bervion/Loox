---
name: vaultify-concurrency-audit-review-patterns
description: Approachable Concurrency trap (nonisolated async runs on CALLER actor, not off-main), erase/lock wipe checklist for new device-local caches, unsalted-hash-of-secret in synced identifiers
metadata:
  type: project
---

Vault Audit review (260711, feat/vault-audit) surfaced recurring bug classes:

1. **nonisolated async ≠ off-main.** `Project.swift` sets `SWIFT_APPROACHABLE_CONCURRENCY=YES`
   → NonisolatedNonsendingByDefault (SE-0461): a `nonisolated` async func runs on the
   CALLER's actor. A plain `Task {}` inside a @MainActor type inherits MainActor, so
   "engine runs off-main" doc comments are wrong unless the call goes through
   `Task.detached` (project's established pattern: VaultSession.swift:223, SecretGuard.swift:62)
   or `@concurrent`. Check every new "heavy work in nonisolated type" claim against this.
2. **Erase/lock wipe checklist.** Any NEW device-local artifact (file in App Group,
   keychain secret) must be added to `AppEnvironment.eraseEverything()` (AppEnvironment.swift
   ~160-192) — grep it on every review that introduces a cache/secret holder.
   AuditLocalCache (audit-pwned-cache.bin + keychain `audit-pwned-cache-secret`) was missed.
3. **Unsalted SHA256(secret) inside synced identifiers** = offline guessing oracle when the
   identifier becomes a plaintext CK recordName/column (AuditFingerprint.secretMarker).
   Suggested fix pattern: HMAC keyed from a vault-key-derived key (vault key is required on
   every syncing device anyway, so cross-device stability holds).
4. LWW checklist for new record types passed cleanly when copied verbatim from the folder
   pattern (strict `>` gate, changeTag no-op, re-dirty local win, tombstone bumps updatedAt,
   markSynced snapshot compare) — compare new `upsert*FromRemote` against
   `upsertFolderFromRemote` (VaultStore.swift:177) as reference.
5. Determinism nits to watch in rule engines: Dictionary iteration order (tie-order jitter),
   `Dictionary.first(where:)` for suffix matching (nondeterministic winner when multiple
   keys match — prefer longest-suffix), `Calendar.current` day math (timezone-dependent).

**How to apply:** grep `SWIFT_APPROACHABLE_CONCURRENCY` / `Task.detached` on any PR claiming
off-main work; grep `eraseEverything` on any PR adding persistence; check fingerprint/marker
construction on any PR persisting derived-from-secret values.
