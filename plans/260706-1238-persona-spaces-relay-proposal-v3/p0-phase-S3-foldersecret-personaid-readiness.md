# P0-S3 — FolderSecret personaId readiness (sealed)

Context: [p0-plan.md](p0-plan.md) · D10/D12 · review Part A (sync LWW) · **parallel track (isolated file)**

## Overview
- Priority: P2 · Status: pending · Depends on: none (parallel; touches only `Folder.swift`)
- Make `FolderSecret` ready to carry a sealed, nullable `personaId` so P1 (PersonaRecord) can bind a Space to a Persona **without a schema/migration churn**. P0 only adds the optional field; it is never written yet.
- ⚠️ YAGNI flag: this adds an unused field one phase ahead of its consumer. Justified **only** because `folderId`/folder identity lives inside the sealed blob and re-sealing later is an LWW-sensitive operation — landing the optional field now avoids re-sealing every folder during P1. If the team prefers strict YAGNI, this phase can be **deferred to P1** at the cost of a one-time re-seal migration then. See decision below.

## Key insights
- `FolderSecret` is `{ name }` only (`Folder.swift:40-42`), sealed AES-256-GCM under the Vault Key (`VaultRepository+Folders.swift:11-13`), decoded with a plain `JSONDecoder` (`:17`).
- Swift synthesized `Codable` decodes a **missing** optional key to `nil` → old sealed blobs (no `personaId`) decode cleanly with zero migration. This is the whole reason the field is safe to add early.
- Sync carries the folder's `sealed` blob wholesale (`CloudSyncService.swift:202`, `upsertFolderFromRemote` `VaultStore.swift:169-201`). Adding a field to the *plaintext-inside-sealed* struct changes ciphertext **only when a folder is re-sealed** (`updateFolder` `:64-76`, which already bumps `updatedAt` at `:71`). Since P0 never writes `personaId`, no folder is re-sealed → **no sync traffic, no LWW risk** in P0.
- The LWW trap (review Part A / `VaultStore.swift:62-71`) bites **P1**, when it starts writing `personaId`: that write path MUST go through `updateFolder` (or equivalent) so `updatedAt` bumps, or the change is dropped on pull. Document this in the field's doc comment.

## Requirements
- Functional: `FolderSecret` gains `var personaId: String?` (default nil); all existing seal/open round-trips unchanged; old blobs decode to `personaId == nil`.
- Non-functional: zero behavior change in P0; no re-seal of existing folders; no new plaintext column on `FolderRecord` (stays sealed — persona linkage is user data).
- Forward contract: doc comment warns any future writer to bump `updatedAt` (LWW).

## Architecture
```swift
nonisolated struct FolderSecret: Codable, Sendable {
    var name: String
    /// Sealed Persona linkage. nil in P0 (nothing writes it yet). When a writer
    /// sets this, it MUST re-seal via updateFolder so updatedAt bumps, or the
    /// whole-record LWW pull gate drops the change. Optional → old blobs decode nil.
    var personaId: String?
}
```
`Folder.secret` (`Folder.swift:36`) currently builds `FolderSecret(name:)`. Two options:
- (a) Add `personaId` to the in-memory `Folder` struct too and thread it through `secret`/`decryptFolder`. — more plumbing, all unused in P0.
- (b) **Minimal (recommended):** keep `Folder` unchanged; `FolderSecret.personaId` defaults nil on encode. `decryptFolder` ignores it. P1 adds the `Folder`-level plumbing when it actually reads/writes personaId.

Recommend (b): the sealed schema is future-proof; no dead plumbing in the domain model until P1 needs it (KISS/YAGNI).

## Related code files
- Modify: `VaultifyCore/Models/Folder.swift` — add `personaId: String?` to `FolderSecret` (+ doc comment). Nothing else if option (b).
- No change: `VaultRepository+Folders.swift` seal/open (still round-trips via Codable), `FolderRecord.swift`, `CloudSyncService.swift`, `VaultStore.swift`.

## Implementation steps
1. Add `var personaId: String?` to `FolderSecret` with the LWW doc comment.
2. Confirm `sealFolder`/`decryptFolder` still compile (Codable auto-handles the new optional).
3. Add a unit test: seal a `FolderSecret(name:)` **without** personaId (old shape) → open → `personaId == nil`; seal with a value → open → round-trips. (Guards the P1 forward-compat contract.)
4. `make check`.

## Todo
- [ ] Add optional `personaId` to `FolderSecret` + doc comment
- [ ] Compile clean
- [ ] Round-trip + backward-decode unit test

## Success criteria
- Existing sealed folders decode unchanged (no crash, `personaId == nil`).
- New/re-sealed folder can round-trip a `personaId` value (proves P1 readiness) — but P0 ships with it always nil.
- No CloudKit diff for existing folders (no re-seal triggered).

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Adding field silently re-seals folders → LWW drop | Low×High | Option (b): nothing writes personaId in P0; no `updateFolder` call triggered. Verified no re-seal path fires. |
| Old-blob decode breaks | Low×High | Optional key decodes to nil (Swift Codable); explicit backward-decode test. |
| Dead field = over-engineering | Med×Low | Documented YAGNI trade-off; defer-to-P1 fallback offered below. |

## Security
`personaId` is user-linkage data → correctly placed **inside** the sealed blob (server never sees it), consistent with `name`. Never add it as a plaintext `FolderRecord` column.

## Open decision (confirm before coding)
- **Land now (readiness) vs defer to P1?** Request says land now to avoid P1 re-seal churn. Strict-YAGNI alternative: skip S3, let P1 add the field + a one-time re-seal migration. Recommend **land now (option b)** — the field is inert, backward-compatible, and removes a migration from P1's critical path. Confirm.

## Next steps
P1 threads `personaId` through the `Folder` domain model, writes it via `updateFolder` (bumps `updatedAt`), and links Spaces to the seeded Personal persona.
