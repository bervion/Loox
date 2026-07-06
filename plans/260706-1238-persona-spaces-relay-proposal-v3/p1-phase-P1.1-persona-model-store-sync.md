# P1.1 — Persona model + store + CloudKit sync

Context: [p1-plan.md](p1-plan.md) · canonical [proposal-v3-locked-decisions.md](proposal-v3-locked-decisions.md) P1/D12/INV-R03 · mirrors `FolderRecord`/`VaultFolder`.

## Overview
- Priority: P1 · Status: pending · Depends on: none (foundational infra)
- Land the persistence + sync substrate for personas: a sealed domain model, an `@Model` record, `VaultStore` accessors, and a **new CloudKit record type** — all mirroring the proven folder path. **No repository behavior, no seed, no UI** in this phase (that is P1.2/P1.3). Pure infra so it can compile + unit-test in isolation.

## Key insights
- `FolderRecord`/`VaultFolder` is the exact template: sealed blob + plaintext presentation/sort/sync columns, single-content-gate LWW (`VaultStore.swift:169-201`), delta-pull switch on `recordType` (`CloudSyncService.swift:139-145`).
- **Do NOT** add persona fields to `ItemRecord` — its whole-record LWW would drop column-only persona edits (the trap the plan calls out). A dedicated record type + dedicated sealed blob is the only correct shape.
- Swift synthesized `Codable` decodes a **missing** optional/defaulted key to its default → forward/backward-compatible sealed payloads with zero migration (same reason `FolderSecret.personaId` was safe to add early in P0-S3).
- The **default** flag is a plaintext synced column (`isDefault: Bool`), mirroring `ItemRecord.isDefaultIdentity` — it is the multi-device-converged invariant anchor, so it must be visible to sync without unsealing.
- Adding a `@Model` type to the `ModelContainer` (`VaultStore.swift:34`) affects **both** targets (app + AutoFill, shared `VaultifyCore`). The extension never reads personas → no behavior change there, but the schema must include the type or the container fails to load.

## Requirements
- **Functional:** define `PersonaKind`, `PersonaIsolationPolicy`, `PersonaSecret`, `Persona` (in-memory), `PersonaRecord` (@Model); `VaultStore` gains persona fetch + LWW upsert + markSynced; `CloudSyncService` pushes/pulls `VaultPersona`. `eraseAll` deletes personas.
- **Non-functional:** all crypto/data types `nonisolated`; store/sync methods `@MainActor` like their folder siblings; each new file <200 LOC; new files → `tuist generate`.
- **Forward contract:** doc-comment every sealed field + the "bump `updatedAt` on any sealed write" LWW rule.

## Architecture

**Data flow (write):** `Persona` → `.secret` (`PersonaSecret`) → `JSONEncoder` → `AESGCM.seal(key)` → `PersonaRecord.sealed` → `ckPersonaRecord` → CloudKit `VaultPersona`.
**Data flow (read/pull):** `VaultPersona` CKRecord → `applyPersona` → `upsertPersonaFromRemote` (LWW by `updatedAt`) → `PersonaRecord`. (Decrypt back to `Persona` is P1.2's `loadPersonas`.)

`VaultifyCore/Models/Persona.swift` (new):
```swift
nonisolated enum PersonaKind: String, Codable, Sendable, CaseIterable {
    case personal, professional, pseudonymous, anonymous, custom
}
/// Defined + stored in P1; CONSUMED in P2 (search/AutoFill hard-exclusion, INV-R03).
nonisolated enum PersonaIsolationPolicy: String, Codable, Sendable, CaseIterable {
    case standard, isolated, strictAnonymous
}
nonisolated struct Persona: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var kind: PersonaKind
    var isolationPolicy: PersonaIsolationPolicy
    var primaryProfileItemID: String?   // soft link → the identity ItemRecord (isDefaultIdentity)
    var primarySpaceID: String?         // D12 single pointer to the primary Space (folder id)
    var isDefault: Bool                 // synced convergence flag (plaintext column)
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Fixed id for the auto-seeded Personal persona so multi-device first-run
    /// seeds collide on ONE record id (CloudKit LWW merges them) instead of
    /// producing duplicates that would need a merge pass.
    static let bootstrapPersonalID = "persona-default-personal"
    var secret: PersonaSecret {
        PersonaSecret(displayName: displayName, kind: kind, isolationPolicy: isolationPolicy,
                      primaryProfileItemID: primaryProfileItemID, primarySpaceID: primarySpaceID)
    }
}
nonisolated struct PersonaSecret: Codable, Sendable {
    var displayName: String
    var kind: PersonaKind
    // Old blobs lacking these decode to the defaults below (backward-compatible).
    var isolationPolicy: PersonaIsolationPolicy = .standard
    var primaryProfileItemID: String?
    var primarySpaceID: String?
}
```
> `isDefault`/`sortIndex`/timestamps live as **plaintext columns** on `PersonaRecord` (not in the sealed blob) — sync must converge the default flag and sort without unsealing, exactly like `FolderRecord`. Only identity-bearing content (name/kind/policy/links) is sealed.

`VaultifyCore/Store/PersonaRecord.swift` (new): `@Model final class PersonaRecord` — copy `FolderRecord` columns (`id` unique, `sealed`, `sortIndex`, `createdAt`, `updatedAt`, `deletedAt?`, `dirty`, `ckRecordName?`, `ckChangeTag?`) **plus** `var isDefault: Bool = false`. No `iconAsset`/`colorRaw` (kind drives the icon; avatar deferred — YAGNI). No avatar column in P1.

`VaultStore.swift` changes:
- `makeContainer` `ModelContainer(for: ItemRecord.self, PasskeyRecord.self, FolderRecord.self, PersonaRecord.self, …)`.
- `eraseAll`: `try context.delete(model: PersonaRecord.self)`.
- Add `allPersonaRecords()`, `personaRecord(id:)`, `upsertPersonaFromRemote(...)`, `markPersonaSynced(...)` — **direct copies** of the folder methods but with the extra `isDefault` field carried in the content gate (bumped with `updatedAt`, like `isDefaultIdentity` rides the item content gate).

`CloudSyncService.swift` changes:
- `private let personaRecordType = "VaultPersona"`.
- `push()` also `try await pushPersonas()` (copy `pushFolders`).
- `ckPersonaRecord(from:)` sets `sealed`, `sortIndex`, `isDefault` (as Int), `createdAt`, `updatedAt`, optional `deletedAt`.
- `applyPersona(_:)` → `upsertPersonaFromRemote(...)`.
- `pull()` switch: `case self.personaRecordType: self.applyPersona(record)`.

## Related code files
- Create: `VaultifyCore/Models/Persona.swift` (~55 LOC), `VaultifyCore/Store/PersonaRecord.swift` (~45 LOC)
- Modify: `VaultifyCore/Store/VaultStore.swift` (container line 34, `eraseAll` 40-45, + 4 persona methods ~50 LOC)
- Modify: `Vaultify/Services/Sync/CloudSyncService.swift` (`push` 83-86, `pull` switch 139-145, + `pushPersonas`/`ckPersonaRecord`/`applyPersona` ~40 LOC)
- Then: `tuist generate --no-open` (new files must enter the globbed project)

## Implementation steps
1. Create `Persona.swift` with the enums + `Persona` + `PersonaSecret` + `bootstrapPersonalID`, fully doc-commented (LWW rule + P2-consumes-isolation note).
2. Create `PersonaRecord.swift` mirroring `FolderRecord` + `isDefault`. Doc-comment: name/kind/policy sealed, `isDefault`/`sortIndex` plaintext for sync convergence.
3. `VaultStore`: register `PersonaRecord.self`; extend `eraseAll`; add `allPersonaRecords`/`personaRecord(id:)`/`upsertPersonaFromRemote`/`markPersonaSynced` (copy folder methods; carry `isDefault` in the content gate).
4. `CloudSyncService`: add `personaRecordType`, `pushPersonas`, `ckPersonaRecord`, `applyPersona`; wire into `push()` and the `pull()` switch.
5. `tuist generate --no-open`; `make check` (app + embedded extension compile).
6. Unit tests (below).

## Todo
- [ ] `Persona.swift` (enums, struct, `PersonaSecret`, `bootstrapPersonalID`)
- [ ] `PersonaRecord.swift` (@Model + `isDefault`)
- [ ] `VaultStore`: container + eraseAll + 4 persona methods
- [ ] `CloudSyncService`: persona push/pull/ck-map + switch
- [ ] `tuist generate` + `make check` clean (both targets)
- [ ] Unit tests: seal round-trip, backward-decode, upsert LWW

## Success criteria
- `make check` compiles app + AutoFill extension.
- Seal a `PersonaSecret` → open → all fields round-trip; a blob missing `isolationPolicy`/`primarySpaceID`/`primaryProfileItemID` decodes to `.standard`/`nil` (backward-compat proven).
- `upsertPersonaFromRemote`: newer `updatedAt` wins; identical `changeTag` is a no-op; strictly-older remote re-marks local `dirty`; `isDefault` propagates with the content gate.
- No `PersonaRecord` field touches `ItemRecord`; grep confirms no persona column on `ItemRecord`.

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| New CK record type not in CloudKit schema → pull fails in prod | Med×High | Dev/sandbox auto-creates fields on first save. Add "deploy `VaultPersona` schema to prod CK" to the pre-release checklist (same as `VaultFolder` originally). Local-first works with sync OFF regardless. |
| Adding `PersonaRecord` to container breaks AutoFill extension load | Low×High | Shared `VaultifyCore`; extension just gains an unused type. `make check` builds the embedded extension — verified there. |
| `isDefault` treated as a column-only toggle (like `pinned`) → dropped on pull | Low×High | Carry `isDefault` in the **content** gate (bump `updatedAt` on change), NOT a separate meta gate — mirrors `isDefaultIdentity`. Documented. |
| Sealed-schema drift between app versions | Low×Med | All new sealed keys optional/defaulted; explicit backward-decode test guards it. |

## Security
Identity-bearing fields (displayName, kind, isolationPolicy, profile/space links) are **sealed** under the Vault Key — iCloud sees ciphertext only. `isDefault`/`sortIndex`/timestamps are non-secret presentation/convergence metadata, plaintext by the same rationale as `FolderRecord` ("secrets sealed", not "zero cleartext"). No new key material.

## Next steps
P1.2 decrypts `PersonaRecord` into a `personas` cache, seeds/migrates the bootstrap persona, enforces the invariants, and rebinds `primarySpaceId`.
