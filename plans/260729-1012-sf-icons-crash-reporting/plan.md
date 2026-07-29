# SF icon system, passkey sync diagnosis, unlock polish, crash reporting

**Status:** IN PROGRESS (branch `feat/sf-icons-crash-reporting-260729`, based on `origin/main` @ v1.43.2)

Four owner requests from 2026-07-29, audited before implementation
(35-agent audit, every claim verified against source).

## Scope

| # | Request | Outcome |
|---|---------|---------|
| 1 | Move Space icons to SF Symbols + a richer picker | Code change. Owner widened scope to Space + item avatars + the whole `Icons` chrome enum. |
| 2 | Passkeys do not sync across devices on one iCloud account | **Not a code bug** — unclosed CloudKit Production schema gate. Code work is diagnosability + tests. |
| 3 | Unlock arrow is black; keyboard will not dismiss | Code change, three defects confirmed. |
| 4 | App freezes on lock screen after screen off/on; add Crashlytics | Two real latch bugs found + Crashlytics behind its own consent toggle. |

## Locked decisions (ADRs)

1. **Icons resolve at READ time; stored values are never rewritten.**
   `FolderRecord.iconAsset` is a plaintext column pushed verbatim to CloudKit and merged
   last-writer-wins. A stored-value rewrite would (a) blank icons on any device still on an
   older build during the mixed-version window, (b) break the seed-Space dedupe signature,
   which is built from the literal icon string, and (c) for item avatars require unseal →
   rewrite → re-seal of every item, re-dirtying the whole vault for CloudKit.
   Instead a resolver maps a legacy name to an SF Symbol at render time. Old builds keep
   rendering their Polaris asset; nothing in the store or the zone changes.

2. **Newly picked icons are stored with an `sf:` prefix.** The prefix makes the two
   namespaces unambiguous with no schema change (still a `String` column). A device on an
   older build renders `sf:` values blank — confined to icons the user newly picks, which is
   the smallest possible mixed-version surface.

3. **The catalog is hard-capped to SF Symbols available on iOS 17.3.** A newer symbol
   compiles clean and renders blank at runtime with no warning — the worst failure mode
   available here. The allowlist (6554 names) is derived from the CoreGlyphs
   `name_availability.plist`, filtered to releases mapping to iOS ≤ 17.3, and is enforced by
   a unit test rather than by reviewer discipline.

4. **`Icons` is the migration chokepoint.** 327 `PolarisIcon(...)` call sites across 125
   files, but 79 distinct references go through the `Icons` enum. Changing the enum's values
   plus the renderer migrates almost the whole app with no call-site edits.

5. **Crash reporting gets its OWN consent toggle** (owner decision), not the existing
   analytics toggle. Cost is new EN/VI/JA strings; benefit is that "usage stats" and "crash
   diagnostics" stay separable in a password manager.

6. **The passkey ops gate is not worked around in code.** The fix is a CloudKit Console
   deploy the owner performs. Code only makes the failure visible and adds the mapping test
   that would have caught a schema mismatch.

## Verified root causes

- **Passkey sync:** the `VaultPasskey` plane is fully implemented and wired into both
  `push()` and `pull()`. `plans/260717-1040-passkey-cloudkit-sync/plan.md:3` still records the
  Production schema deploy as PENDING. CloudKit Production has no just-in-time schema
  creation, so every passkey push is rejected, `dirty` never clears, and the other device
  pulls zero passkey records. Items and folders keep syncing because `push()` is
  fault-isolated per plane — which is exactly the reported symptom.

- **Freeze:** the Argon2 KDF is NOT the cause (every type in the derive chain is
  `nonisolated` and the call is wrapped in `Task.detached` — verified). Two independent latch
  bugs in `LockScreen` were found instead:
  `bioAuthenticating` can never be cleared except by the `defer` in `runBiometric()`, and in
  that state the screen renders zero usable controls; and `entered` is forced false on every
  `.background` and its restore path can no-op, leaving the whole chrome at `.opacity(0)`
  while still hit-testable.

## Migration traps this plan defends against

- Stored values are **not** only `dt_*`. Every onboarded vault holds `ic_lock_filled` (the
  seeded first Space); persona starter Spaces and every CSV import hold `ic_folder`.
- `PolarisIcon` renders `Image(name)` with no existence check and `FolderBadge` still paints
  its tinted tile, so an unmapped name yields an empty colored square — no crash, no log, and
  no test failure.
- `__monogram` is a reserved sentinel stored in the same field as item icon names. A blanket
  mapping pass that does not exclude it breaks every letter-avatar item.
- The seed-Space dedupe signature is built from the literal icon string, so the comparison
  must be normalised through the resolver or seeded Spaces stop converging and duplicate.

## Owner action required (blocking for request 2)

CloudKit Console → container `iCloud.com.bervion.vaultify` → **Production**: confirm the
record type `VaultPasskey` exists with fields `sealed` (Bytes), `largeBlobSealed` (Bytes),
`createdAt` (Date/Time), `updatedAt` (Date/Time), `deletedAtMs` (Int64). If missing, JIT-create
it in Development with one Debug run first, then Deploy Schema Changes to Production. Other
types flagged as possibly outstanding in the same state: `VaultPersona`, `VaultEmailAlias`,
`VaultForwardingInbox`, `AuditReport`, `AuditFindingState`, `OwnerDevice`, `DeviceRevocation`.

Do **not** use Erase Vault as a troubleshooting step — it deletes the whole zone, every
device's synced copy, and the recovery envelope.
