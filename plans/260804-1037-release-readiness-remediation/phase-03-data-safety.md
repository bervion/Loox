# Phase 3 — Import / export / artifact data safety

Three agents, no file overlap with Phase 2. None of this is visible to App Review — these
are real security and data-loss bugs with real user harm and zero review exposure. Ship
them because the product is a password manager, not because Apple will catch them.

## Threat model — the audit had this backwards

The source audit reasoned that a malicious backup "requires knowing the passphrase," and
softened the priority accordingly. That premise is inverted.

**The attacker authors the backup**, therefore the attacker chooses the passphrase and hands
it to the victim: *"here's the shared team vault, the password is X"*, *"import this to
migrate from LastPass"*. The victim's own passphrase is never involved. The bar is not
cryptographic — it is "get a user to import a file," which is the single thing the import
feature exists to do.

---

## Agent 3A — KDF policy and Level-2 adoption

**Owns:** `VaultifyCore/Crypto/KdfParams.swift`,
`Vaultify/Security/VaultSession+Level2.swift`,
`VaultifyTests/Level2LifecycleTests.swift`.

### P1-02 — unclamped KDF parameters

`VaultBackup.swift:67-73` decodes `KdfParams` from the file and feeds `memoryCostKiB`,
`timeCost`, `parallelism` straight to Argon2. Opening an attacker-supplied `.vaultify` and
tapping Decrypt kills the app via jetsam (memory band) or wedges it in a permanent spinner
with a pegged core, thermal throttle and battery drain (time band).

The salt is unvalidated too: an empty `backup.salt` makes Argon2 return
`ARGON2_SALT_TOO_SHORT`, surfaced to the user as "Couldn't decrypt" — indistinguishable
from a wrong password.

Add to `KdfParams` a **validating decoder** with `maxMemoryCostKiB`, `maxTimeCost`,
`maxParallelism` and an `isWithinPolicy` check. One change closes both P1-02 and M10.

### M10 — the persisted-DoS escalation

`Level2Wrap.kdf` from a malicious backup is persisted **verbatim** into this device's key
bundle. Import once and the Extra Password is permanently broken: every reveal of a
protected field runs a 2 GiB or 4-year Argon2, triggered by the app's own bundle with no
attacker file needed again.

The AutoFill extension is the sharper edge — `KdfParams.swift:19-26` documents that the
extension already halves memory to 32 MiB specifically to survive its tight jetsam budget,
so a planted 256 MiB profile terminates the credential UI every time. And because turning
Extra Password off demands the foreign password, **the user cannot undo it.**

In `level2AdoptedBundle` (~`:116`), return nil unless `kdf.isWithinPolicy` and the salt
meets the minimum length.

### M11 — silent data stranding on wrap collision

`adoptLevel2WrapIfAbsent`'s never-overwrite semantics produce two silent-data-loss shapes,
neither requiring an attacker:

1. User has an Extra Password on device B and restores their own device-A backup: every
   protected field imports as permanently unopenable ciphertext, reported as a successful
   import, discovered days later as "Couldn't decrypt this field."
2. User has no Extra Password and imports someone else's backup: M10's unremovable foreign
   wrap.

Give `adoptLevel2WrapIfAbsent` a typed result — `adopted` / `skippedDeviceHasOwnWrap` /
`refusedInvalidPolicy` — so the caller can tell the user the truth.

---

## Agent 3B — path containment

**Owns:** `Vaultify/Services/Artifacts/ArtifactStore.swift`,
`Vaultify/Services/ImportExport/VaultBackup.swift`,
`VaultifyTests/ArtifactStoreTests.swift`, `VaultBackupV2Tests.swift`.

### P1-03 — artifact path traversal, confirmed empirically

Verified by running the real Foundation APIs against a real filesystem and physically
writing files outside both the artifact root and the temp-export directory.

Two facts that change the fix:

- **`URL.appending(path:)` and `appendingPathComponent(_:)` behave identically here.**
  Neither normalizes nor rejects `..`; the string is passed through and the kernel resolves
  it at write time. Swapping one for the other fixes nothing.
- Percent-encoded `..%2F` is inert, so encoding is not the attack vector.

**Only a `standardizedFileURL` prefix-containment assertion fixes this.**

Blast radius, honestly: the id-based leg always appends `.enc`, so `Vault.store` and
`vault-keybundle.json` cannot be clobbered through it, and the App Group container's random
UUID path makes it unguessable from the app container. This is not vault-key compromise. It
*is* attacker-chosen file writes anywhere in the app sandbox from a single import with zero
further taps, plus a second leg through `exportPlaintext()` joining `manifest.filename`
directly. Files written outside the root are also invisible to `reconcile()` and survive
`eraseAll()`.

Fixes:
- `VaultBackup.validatedArtifacts` (~`:328`): reject any `PortableArtifact` whose `id` or
  `ownerItemId` is not a canonical UUID, and any `filename` that is not a bare basename —
  no separators, no control characters, bounded length. Reject at the wire level, before
  anything is written.
- `ArtifactStore.fileURL(for:)` and `exportPlaintext()`: defense in depth — resolve
  `standardizedFileURL` and assert the result is a descendant of the intended root before
  any write.

**Tests:** crafted traversal vectors must fail *before* any file write, and leave the
filesystem and store unchanged.

---

## Agent 3C — import and export lifecycle

**Owns:** `Vaultify/Features/ImportExport/ImportView.swift`, `ExportView.swift`.

1. **Hoist Level-2 adoption before `addAll`** so the outcome from Agent 3A is known before
   any item is written, and show a pre-import warning when the payload carries
   level2-sealed fields and adoption was skipped. Surface the adoption outcome in the
   result.
2. **Size pre-check off the main actor.** `Data(contentsOf:)` is unbounded; add a file /
   envelope / artifact-count / row-count ceiling and read off `MainActor`.
3. **Hold the decrypt `Task` in `@State` and add Cancel** while `working`. Distinguish
   "malformed file" from "wrong password" — today `ARGON2_SALT_TOO_SHORT` looks like a bad
   passphrase.
4. **Honest partial-restore reporting.** Restore is multi-step (folders, items, artifacts,
   passkeys, L2) and a mid-flight failure leaves partial state. Either preflight everything
   then commit, or report imported/skipped per category. Do not claim success on a partial
   run.
5. **Export completeness.** `compactMap` silently drops artifacts with missing/load/manifest
   errors while the item keeps its `fileRef`, so a "successful" backup can be missing
   attachments the user only discovers at restore. Fail, or require explicit acceptance.
6. **Temp file lifecycle.** `ExportView.swift:164-178` writes a fixed
   `temporaryDirectory/loox-export.csv` (plaintext) and never removes it — not on share
   completion, dismiss, lock, background, or launch. Encrypted backup uses a fixed name too.
   Use a unique per-export directory and clean up on all five triggers.
7. **Export memory ceiling.** Encrypted export loads every artifact plaintext into memory at
   once on the main actor — ten 20 MiB attachments is roughly 800 MiB peak and a jetsam
   kill. **Do not redesign around a streaming `AsyncSequence` provider protocol** (L-effort
   API change). Seal each `PortableArtifact` inside the existing loop so only one plaintext
   is live, wrap it in an `autoreleasepool`, hop the decrypt off `MainActor`, and add a
   total-bytes ceiling with a clear message. Same outcome, S/M effort, no new abstraction.

---

## Migration (P1-05) — split, do not over-build

- **Ship now:** `VaultStore`'s `fatalError("Failed to initialise vault store: \(error)")`
  interpolates a Core Data `NSError` whose `userInfo` carries the store path — into a
  message `CLAUDE.md` explicitly says is uploaded to Crashlytics and must not contain
  paths. Fix the message.
- **Ship now:** an empty `SchemaMigrationPlan` / `VersionedSchema` scaffold is cheap
  insurance. Take it.
- **Defer:** the fixture-backed `testContainerLoadsAgainstAStoreWrittenByThePreviousSchema`
  test. v1.49.1 → v1.50.0 adds exactly one standalone entity (`ArtifactRecord`) and changes
  zero existing columns — the case lightweight migration handles.
- **Keep as a manual Phase 7 gate:** install v1.49.1, build a representative vault, upgrade
  in place, then unlock / read / edit / export / relaunch and verify items, passkeys,
  artifacts, folders and personas. Repeat under low storage.

## Phase exit criteria

- [ ] Out-of-policy KDF params rejected at decode; malicious vectors neither OOM nor hang
- [ ] Foreign L2 wrap never adopted when out of policy; adoption outcome surfaced
- [ ] Wrap collision warns before import instead of stranding data silently
- [ ] Traversal vectors rejected before any write; filesystem unchanged
- [ ] Import reports per-category outcome; no silent partial success
- [ ] Export never leaves a plaintext temp file; bounded peak memory
- [ ] Crashlytics-bound fatal messages contain no paths
