# P1.2 — Repository: load, seed/migrate, invariants, resolver, rebind

Context: [p1-plan.md](p1-plan.md) · D12/D7/INV · mirrors `normalizeDefaultIdentity` (`VaultRepository.swift:147-168`). Depends on **P1.1**.

## Overview
- Priority: P1 · Status: pending · Depends on: P1.1
- Bring personas to life in the unlocked repository: decrypt into a cache on `reload()`, **seed/migrate** the bootstrap Personal persona idempotently, enforce **≥1 persona + exactly-1-default**, expose the **active-persona resolver**, minimal **create/setDefault/setActive** CRUD, and **rebind `primarySpaceId`** to the active persona. Also thread `FolderSecret.personaId` through the `Folder` domain model with an `updateFolder`-based writer (no forced population — inert until P2 needs it).

## Key insights
- `reload()` (`VaultRepository.swift:36-71`) already runs post-unlock with the Vault Key in scope and ends with `normalizeDefaultIdentity()` + a conditional seed-folder merge — the exact hook point + discipline to copy (patch in place, **never** re-enter `reload()`).
- **Default vs active are two concepts:**
  - **default persona** — synced, converged plaintext `isDefault` flag; the durable invariant anchor (guarantees a well-defined persona on any device after sync). Mirrors `isDefaultIdentity`.
  - **active persona** — device-local UI selection (which persona the UI currently shows / whose `primarySpaceID` drives things). Stored in `SettingsStore.activePersonaID` (like `selectedPaymentCardId`), **not synced** (D7). Resolver falls back to the default when the selection is nil/stale.
- **Fixed bootstrap id** (`Persona.bootstrapPersonalID`) makes the seed idempotent *and* multi-device-safe: `guard personaRecord(id: bootstrapPersonalID) == nil` — two devices seeding offline collide on one record id → CloudKit LWW merges them. No `mergeDuplicatePersonas` pass needed in P1.
- The seed covers **both** new + existing installs from one place: after onboarding seeds identity/folder, the subsequent `reload()` seeds the persona. `OnboardingFlow` needs **no** change (DRY).
- **LWW:** `addPersona`/`setDefaultPersona` writes MUST bump `updatedAt` (content gate) — copy `updateFolder`/`writeIdentityDefault`.
- `primaryProfileItemID` is a **soft** link: if the identity item is later trashed, the pointer dangles but the persona stays valid (P1 tolerates nil/dangling; don't cascade).

## Requirements
- **Functional:**
  1. `reload()` loads `personas`, runs `ensurePersonaExists()` then `normalizeDefaultPersona()` (both patch-in-place, no reload recursion).
  2. `ensurePersonaExists()`: if `personas.isEmpty`, seal + insert a `.personal` persona at `bootstrapPersonalID` with `isDefault=true`, `isolationPolicy=.standard`, `primaryProfileItemID = defaultIdentity?.id`, `primarySpaceID = primarySpaceId`. Idempotent.
  3. `normalizeDefaultPersona()`: converge to exactly one `isDefault` (winner = max `updatedAt`,`createdAt`), promoting one when zero. No-op when already exactly one.
  4. `activePersona: Persona?` resolver = `personas.first { $0.id == settings.activePersonaID } ?? defaultPersona`.
  5. Minimal CRUD: `addPersona(displayName:kind:) -> String` (random UUID, `isDefault=false`, `sortIndex` = max+1, `primarySpaceID = primarySpaceId`), `setDefaultPersona(_:)`, `setActivePersona(_:)` (writes `settings.activePersonaID`, no record write).
  6. Rebind `primarySpaceId` → `activePersona?.primarySpaceID ?? folders.first?.id` (preserves P0 fallback).
  7. Thread `Folder.personaId` (struct field + `secret` builder + `decryptFolder`) + `assignSpace(_:toPersona:)` writer (re-seals via `updateFolder`, bumps `updatedAt`). **Not** auto-populated in P1.
- **Non-functional:** `personas` cache is `private(set)`, cleared in `clear()`; resolver is a cheap pure read; no sync of `activePersonaID`.

## Architecture
`Vaultify/Data/Repositories/VaultRepository+Personas.swift` (new) — the persona analogue of `+Folders`/`+Identity`:
```swift
extension VaultRepository {
    // sealPersona/decryptPersona (mirror sealFolder/decryptFolder)
    func loadPersonas(key: SecureBytes) -> [Persona] { … sorted by (sortIndex, createdAt) }
    var defaultPersona: Persona? { personas.first(where: \.isDefault) }
    var activePersona: Persona? { personas.first { $0.id == session/settings.activePersonaID } ?? defaultPersona }
    func ensurePersonaExists()          // seed/migrate — patch in place, no reload()
    func normalizeDefaultPersona()      // converge exactly-1-default — patch in place
    @discardableResult func addPersona(displayName:, kind: PersonaKind) throws -> String
    func setDefaultPersona(_ persona: Persona)
    func setActivePersona(_ id: String)
}
```
Reaching `settings`: `VaultRepository` holds `session`, not `settings`. **Add** `let settings: SettingsStore` to `VaultRepository` (inject at `AppEnvironment.init:65`) OR read active id via `session`. → **Decision D-P1-a (below): inject `SettingsStore`** — cleanest, matches how `CloudSyncService`/`ClipboardService` already take `settings`.

`VaultRepository.reload()` tail (after `normalizeDefaultIdentity()`):
```swift
personas = loadPersonas(key: key)
ensurePersonaExists()          // may append to personas + insert a record (in place)
normalizeDefaultPersona()      // may rewrite isDefault flags (in place)
```

`Folder.swift`: add `var personaId: String?` to `Folder`; `secret` → `FolderSecret(name: name, personaId: personaId)`; `decryptFolder` sets `personaId: secret.personaId`.

`VaultRepository+Folders.swift`: change only `primarySpaceId`'s body (line 48).

## Related code files
- Create: `Vaultify/Data/Repositories/VaultRepository+Personas.swift` (~150 LOC — may split seal/CRUD vs invariants if >200)
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift` (add `personas` cache 16-17 area, `clear()` 26-33, `reload()` tail 63-70, inject `settings`)
- Modify: `Vaultify/Data/Repositories/VaultRepository+Folders.swift` (rebind `primarySpaceId` :48 only)
- Modify: `VaultifyCore/Models/Folder.swift` (`Folder.personaId` + `secret` + nothing in `FolderSecret` — field already present from P0-S3)
- Modify: `Vaultify/App/SettingsStore.swift` (add `activePersonaID: String?` device-local, + `Key.activePersona`; init decode) and `Vaultify/App/AppEnvironment.swift` (pass `settings` into `VaultRepository(store:session:settings:)`)

## Implementation steps
1. `Folder.swift`: add `personaId: String?` to `Folder` (default nil in init) + pass through `secret`; `decryptFolder` reads `secret.personaId`.
2. `SettingsStore`: add `var activePersonaID: String? { didSet { defaults.set(...) } }` + `Key.activePersona = "active_persona_id"`; init `d.string(forKey:)`. Device-local, not synced (doc-comment the D7 rationale).
3. `VaultRepository`: add `private(set) var personas: [Persona] = []`; clear it in `clear()`; add `let settings: SettingsStore`; update `init` + `AppEnvironment.init` call site.
4. `VaultRepository+Personas.swift`: `sealPersona`/`decryptPersona`, `loadPersonas`, `defaultPersona`, `activePersona`, `ensurePersonaExists`, `normalizeDefaultPersona`, `addPersona`, `setDefaultPersona`, `setActivePersona`. Model `ensurePersonaExists`/`normalizeDefaultPersona` on `mergeDuplicateSeedFolders`/`normalizeDefaultIdentity` (patch in place, save, `noteLocalMutation`, no `reload()`).
5. `reload()`: append the 3-line persona block after `normalizeDefaultIdentity()`.
6. `VaultRepository+Folders.swift`: rebind `primarySpaceId` to `activePersona?.primarySpaceID ?? folders.first?.id`; keep the doc comment (explain the persona backing without naming plan artifacts).
7. Add `assignSpace(_ folder:toPersona:)` to `+Personas` (or `+Folders`): sets `folder.personaId`, calls `updateFolder`.
8. `make check`; unit tests (below).

## Todo
- [ ] `Folder.personaId` threaded through struct/secret/decrypt
- [ ] `SettingsStore.activePersonaID` (local, not synced)
- [ ] `VaultRepository`: `personas` cache + `settings` injection + `reload()` block
- [ ] `+Personas`: load, resolver, ensure, normalize, CRUD, assignSpace
- [ ] `primarySpaceId` rebind (active persona)
- [ ] `make check` + unit tests green

## Success criteria
- Fresh in-memory vault + a default identity → after `reload()`: exactly 1 persona (`bootstrapPersonalID`, `.personal`, `isDefault`), `primaryProfileItemID == defaultIdentity.id`, `primarySpaceID == primarySpaceId`.
- `ensurePersonaExists` idempotent: second `reload()` does not create a duplicate.
- `normalizeDefaultPersona`: seed a 2nd persona both flagged default → converges to one; zero-default → promotes one.
- `activePersona`: nil `activePersonaID` → default; stale id → default; valid id → that persona.
- `primarySpaceId` returns active persona's `primarySpaceID`; nil → `folders.first?.id` (P0 parity).
- `assignSpace` round-trips `Folder.personaId` and bumps the folder `updatedAt` (LWW-safe).
- `isDefaultIdentity` + `VaultReader.defaultIdentityUsername` still work (grep: untouched).

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Seed runs before folders/identity loaded → links nil | Med×Med | Place the persona block **after** `folders = loadFolders` and `normalizeDefaultIdentity` in `reload()`. `primaryProfileItemID` nil is tolerated (soft link); reload re-derives on next unlock. |
| `reload()` recursion / infinite loop | Low×High | `ensurePersonaExists`/`normalizeDefaultPersona` patch `personas` + records in place and call `save()`+`noteLocalMutation()` only — **never** `reload()` (copy `normalizeDefaultIdentity` discipline). |
| Multi-device duplicate personas | Low×High | Fixed `bootstrapPersonalID` → LWW merge by id. User-created personas get UUIDs (duplicates there are a deliberate user choice, not seeds). |
| Injecting `settings` into `VaultRepository` ripples to other call sites | Low×Med | Only two constructors: `AppEnvironment.init:65` and test `makeStack` helpers. Enumerated; update both. |
| Forced `personaId` population re-seals every folder → sync churn | Low×Med | P1 does **not** auto-populate `Folder.personaId`; `Persona.primarySpaceID` is the authoritative link. Writer exists but is called only by P2's assignment UI. |

## Security
Persona payloads sealed (P1.1). `activePersonaID` is a non-secret device-local selection (a persona id reveals nothing without the sealed name) — excluding it from sync is the privacy-correct default (D7). `Folder.personaId` stays inside the sealed blob.

## Next steps
P1.3 wires `SettingsStore.activePersonaID` to a switcher UI and replaces `PersonaID.placeholder` at the Home/Search call sites with `activePersona.id`.
