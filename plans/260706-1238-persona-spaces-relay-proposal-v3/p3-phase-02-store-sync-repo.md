# P3 Phase 2 — Store + CloudKit sync + repository CRUD/resolvers

**Context:** `p3-plan.md` · Phase 1 (model). Mirror the persona wiring EXACTLY.
**Pattern sources (verified file:line):**
- `VaultifyCore/Store/VaultStore.swift:34-47` (container + eraseAll), `:216-277` (persona sync block).
- `Vaultify/Services/Sync/CloudSyncService.swift:25` (recordType), `:84-88` (push()),
  `:138-149` (pull switch), `:230-269` (persona push/ck/apply).
- `Vaultify/Data/Repositories/VaultRepository.swift:18` (cache), `:27-35` (clear),
  `:75-78` (reload persona load).
- `VaultRepository+Personas.swift` (seal/decode/load/resolvers), `+PersonaManagement.swift` (CRUD).

## Overview
Priority P2 · Status pending · Depends P1.
Register the alias record, add LWW upsert + CK push/pull, load into the repository cache, and
expose CRUD (create persona/per-site alias, flag-guarded status change, tombstone) + resolvers.

## Key insights
- **Pull switch is fail-silent**: a `recordType` not in the `pull()` switch is `default:
  break` → aliases silently never sync. Adding `case aliasRecordType: applyAlias` is mandatory.
- **`upsertFromRemote` guard-let is fail-silent**: a missing/wrong-typed CK field returns
  early → the alias is dropped. `ckAliasRecord`/`applyAlias` field names+types must match.
- Aliases need **no seed and no normalize** (unlike personas) — a vault legitimately has zero
  aliases. `reload()` just loads them; nothing to converge.
- **Cascade on persona delete**: `deletePersona` (`+PersonaManagement.swift:63`) must also
  tombstone that persona's aliases, else orphans. Add a cascade call.

## Requirements
- `VaultStore`: register `EmailAliasRecord.self` in container + `eraseAll`; add
  `allAliasRecords`/`aliasRecord(id:)`/`upsertAliasFromRemote(...)`/`markAliasSynced(...)`
  (verbatim copies of the persona methods, minus `isDefault`).
- `CloudSyncService`: `aliasRecordType = "VaultEmailAlias"`; `pushAliases`, `ckAliasRecord`,
  `applyAlias`; add `try await pushAliases()` to `push()` and the `case` to `pull()`.
- `VaultRepository`: `private(set) var aliases: [EmailAlias]`; load in `reload()`; clear in `clear()`.
- `+Aliases.swift`: `sealAlias`/`decryptAlias`/`loadAliases`; resolvers `aliases(forPersona:)`,
  `personaAlias(forPersona:)`, `aliases(forItem:)`.
- `+AliasManagement.swift`: `createPersonaAlias(for:)`, `createPerSiteAlias(for:boundItemId:)`,
  `setAliasStatus(_:to:)` (flag-guarded), `updateAlias(_:)`, `deleteAlias(_:)`,
  `deleteAliases(forPersona:)`.

## Architecture — data flow
Write: repo CRUD → `sealAlias` → `EmailAliasRecord.dirty=true` → `save` → `reload` →
`noteLocalMutation` → debounced push → `ckAliasRecord` → CK zone "Vault".
Read/merge: `pull()` → `applyAlias` → `upsertAliasFromRemote` (LWW by `updatedAt`, change-tag
short-circuit) → `reloadAfterRemoteSync` → `loadAliases` decrypts → `aliases` cache.
Isolation (INV-R03): resolvers filter by `personaId`; `aliases(forPersona:)` returns only that
persona's aliases — cross-persona surfacing is impossible because the caller passes one id.

## Related code files
Modify:
- `VaultifyCore/Store/VaultStore.swift` — container line, `eraseAll`, +alias sync block.
- `Vaultify/Services/Sync/CloudSyncService.swift` — record type, `push()`, `pull()` switch,
  push/ck/apply methods.
- `Vaultify/Data/Repositories/VaultRepository.swift` — cache field, `reload()`, `clear()`.
- `Vaultify/Data/Repositories/VaultRepository+PersonaManagement.swift` — cascade in `deletePersona`.
Create:
- `Vaultify/Data/Repositories/VaultRepository+Aliases.swift` — seal/decode/load/resolvers (~90 LOC).
- `Vaultify/Data/Repositories/VaultRepository+AliasManagement.swift` — CRUD (~110 LOC).

## Implementation steps
1. `VaultStore.swift:34-36`: add `EmailAliasRecord.self` to `ModelContainer(for:)`.
   `:42-46`: add `try context.delete(model: EmailAliasRecord.self)` to `eraseAll`.
2. Append an alias sync block to `VaultStore` copying `:216-277` (drop `isDefault` param/field).
3. `CloudSyncService`: add `private let aliasRecordType = "VaultEmailAlias"`; add
   `try await pushAliases()` to `push()`; add `case self.aliasRecordType: self.applyAlias(record)`
   to the `pull()` switch; add `pushAliases`/`ckAliasRecord`/`applyAlias` copying `:230-269`
   (fields: `sealed`, `sortIndex`, `createdAt`, `updatedAt`, `deletedAt?` — no `isDefault`).
4. `VaultRepository.swift`: add `private(set) var aliases: [EmailAlias] = []`; in `clear()` set
   `aliases = []`; in `reload()` (after personas, `:78`) `aliases = loadAliases(key: key)`.
5. `+Aliases.swift`: `sealAlias`/`decryptAlias`/`loadAliases` cloning `+Personas.swift:16-43`;
   resolvers filtering the `aliases` cache by `personaId` / `boundItemId`.
6. `+AliasManagement.swift`:
   - `createPersonaAlias(for:)` — guard `personaAlias(forPersona:) == nil` (≤1 per persona);
     `localPart = AliasAddress.randomLocalPart()` (or persona-slug seed for persona tier);
     `status = .reserved`; `forwardingTarget` = persona profile email label.
   - `createPerSiteAlias(for:boundItemId:)` — random localPart, `tier=.perSite`, `boundItemId`,
     `boundDomain` from the item's first `autofillHost`, `status=.reserved`.
   - `setAliasStatus(_:to:)` — `guard AliasLifecycle.canTransition(from:alias.status, to:target,
     flag: RelayFeature.activeAliasesEnabled)` — a request for `.active` while flag off is a no-op.
   - `updateAlias`/`deleteAlias` — clone `updatePersona`/`deletePersona` (re-seal, bump
     `updatedAt`, tombstone).
   - `deleteAliases(forPersona:)` — tombstone each; call from `deletePersona`.
7. `+PersonaManagement.swift:63` `deletePersona`: after the gate, `deleteAliases(forPersona: persona.id)`.
8. `tuist generate --no-open`; `make check`.

## Todo
- [ ] VaultStore: container + eraseAll + alias sync block
- [ ] CloudSyncService: type + push() + pull() case + push/ck/apply
- [ ] VaultRepository: cache + reload + clear
- [ ] +Aliases.swift seal/decode/load/resolvers
- [ ] +AliasManagement.swift CRUD + flag-guarded status
- [ ] deletePersona cascade
- [ ] tuist generate + make check
- [ ] EmailAliasTests suite green

## Success criteria (VaultifyTests/EmailAliasTests)
- Backward-decode: legacy blob → `.perSite`/`.draft`, nil bindings.
- Seal round-trip preserves all fields incl. `tier`/`status`/bindings.
- `upsertAliasFromRemote` LWW: same change-tag = no-op; newer `updatedAt`+new tag = content wins;
  older revision re-marks `dirty` (clone `PersonaCoreTests:109-128`).
- `createPersonaAlias` twice for one persona → second is rejected (≤1 persona-tier invariant).
- `setAliasStatus(to:.active)` with flag off → status stays `.reserved` (no-op).
- `deletePersona` tombstones its aliases (cache no longer lists them).
- Erase: `store.eraseAll()` then `allAliasRecords()` empty.

## Risks
| Risk | L×I | Mitigation |
|------|-----|------------|
| Missing `pull()` case → aliases never sync | M×H | step 3 adds the case; note it's fail-silent |
| CK field name/type mismatch → dropped on pull | M×H | copy persona ck/apply verbatim; LWW test |
| Orphan aliases after persona delete | M×M | `deleteAliases(forPersona:)` cascade |
| Flag-guard bypassed in a code path | L×H | single `setAliasStatus` choke point; test asserts no-op |

## Security
- CK sees only ciphertext + sort/sync metadata (no `status`, no `localPart`) — same guarantee
  as items/folders/personas. Zone deletion on Erase drops alias records with the vault.
- INV-R03 upheld: no resolver returns cross-persona aliases; callers pass a single `personaId`.

## Next steps
Phase 3 surfaces these in a minimal UI. D4 offline-block-erase is NOT needed here (no alias can
be `.active` while the flag is off) — it is a P4A concern.
