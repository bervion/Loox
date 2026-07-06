# P3 Phase 1 — Alias domain model + sealed record + feature flag + pure helpers

**Context:** `p3-plan.md` · canonical `proposal-v3-locked-decisions.md` §P3, D14.
**Pattern source (mirror EXACTLY):** `VaultifyCore/Models/Persona.swift`,
`VaultifyCore/Store/PersonaRecord.swift`, `VaultifyCore/Theme/WallpaperFeature.swift:9-11`.

## Overview
Priority P2 · Status pending · No dependencies.
Pure, store-free layer: domain model, sealed payload, `@Model` record, feature flag, and
two pure helpers (lifecycle state-machine + address rendering). Fully unit-testable in
isolation before any store/sync wiring exists.

## Key insights
- **P1 sealed-schema lesson** (`Persona.swift:98-109`): a non-optional property *with a
  default* still throws `keyNotFound` under synthesized `Codable`. Custom `init(from:)` with
  `decodeIfPresent` is what makes the sealed schema growable. Applies to `status`, `tier`,
  and every optional binding on `EmailAliasSecret`.
- **Anti-correlation** (canonical "2 tầng chống correlation"): per-site alias `localPart`
  MUST be random, never derived from the site domain or persona name.
- **No live-looking address** pre-relay: the `@domain` suffix is only ever constructed inside
  `AliasAddress.display` when `RelayFeature.activeAliasesEnabled && status == .active`.

## Requirements
Functional:
- `AliasTier { persona, perSite }`, `AliasStatus { draft, reserved, active, paused, disabled }`.
- `EmailAlias` (in-memory) + `EmailAliasSecret` (sealed Codable, custom backward-decode).
- `EmailAliasRecord` (`@Model`) mirroring `PersonaRecord` (sealed + sort/sync metadata plaintext).
- `RelayFeature.activeAliasesEnabled = false`.
- `AliasLifecycle`: allowed states given the flag + a transition guard.
- `AliasAddress`: display rendering (flag-guarded) + random `localPart` generator.

Non-functional: `nonisolated` types (off-main safe); every file <200 LOC; no networking.

## Architecture — data model
`EmailAliasSecret` (SEALED under Vault Key):
- `personaId: String` — owner (identity-correlating → sealed).
- `tier: AliasTier`
- `localPart: String` — the address left-side (sealed; the sensitive fragment).
- `boundItemId: String?` — per-site: which login item.
- `boundDomain: String?` — per-site: which website/domain.
- `status: AliasStatus`
- `forwardingTarget: String?` — local label/reference of the real inbox it *would* forward to
  (P3: a display label captured from the persona's profile email; becomes a verified-
  destination reference at P4B). No inbox entity (YAGNI).
- `disabledAt: Date?`

`EmailAliasRecord` (`@Model`, mirrors `PersonaRecord.swift` — plaintext columns only carry
convergence/sort/sync metadata): `id`, `sealed`, `sortIndex`, `createdAt`, `updatedAt`,
`deletedAt?`, `dirty`, `ckRecordName?`, `ckChangeTag?`. **No `isDefault`** (aliases have no
singleton invariant). `status`/`tier` stay SEALED (no plaintext status signal in CloudKit;
they ride the `updatedAt` content gate).

Data flow: `EmailAlias` (in mem) → `.secret` → `JSONEncoder` → `AESGCM.seal` → `.sealed`
(store/CK). Reverse on read. Identical to persona seal path (`+Personas.swift:16-33`).

## Related code files
Create:
- `VaultifyCore/Models/EmailAlias.swift` — enums + `EmailAlias` struct + `EmailAliasSecret`
  (custom `init(from:)` with `decodeIfPresent`). ~130 LOC.
- `VaultifyCore/Models/AliasLifecycle.swift` — `userReachableStates(flag:)`,
  `canTransition(from:to:flag:)`. Pure. ~60 LOC.
- `VaultifyCore/Models/AliasAddress.swift` — `display(localPart:status:relayDomain:flag:)`
  (never emits `@` unless flag+`.active`) + `randomLocalPart()`. ~70 LOC.
- `VaultifyCore/RelayFeature.swift` — feature flag enum. ~12 LOC.
- `VaultifyCore/Store/EmailAliasRecord.swift` — `@Model`, mirrors `PersonaRecord`. ~45 LOC.

Modify: none (store registration is Phase 2).

## Implementation steps
1. `RelayFeature.swift`: `nonisolated enum RelayFeature { static let activeAliasesEnabled = false }`
   with a comment mirroring `WallpaperFeature` (relay backend doesn't exist; keeping active
   unreachable prevents shipping a fake-working address — App Review + trust guard).
2. `EmailAlias.swift`: declare `AliasTier`/`AliasStatus` (`String, Codable, Sendable, CaseIterable`),
   the `EmailAlias` struct (`Identifiable, Equatable, Sendable`) with memberwise `init` +
   `var secret: EmailAliasSecret`, and `EmailAliasSecret` with a custom `init(from:)` using
   `decodeIfPresent` for `tier`/`status` (defaults `.perSite`/`.draft`) and all optionals.
3. `AliasLifecycle.swift`: `userReachableStates(flag:) -> [AliasStatus]` returns
   `[.draft, .reserved, .disabled]` when flag off (adds `.active, .paused` when on);
   `canTransition(from:to:flag:)` rejects any `to == .active` while flag off.
4. `AliasAddress.swift`: `display(...)` returns bare `localPart` for non-active/flag-off;
   `"\(localPart)@\(relayDomain)"` only when `flag && status == .active`. `randomLocalPart()`
   = 12-char lowercased base32 from `SystemRandomNumberGenerator` (no domain/persona input).
5. `EmailAliasRecord.swift`: copy `PersonaRecord` shape; drop `isDefault`; keep `dirty=true`
   default in `init`.
6. `tuist generate --no-open` (new files must enter both target globs), then `make check`.

## Todo
- [ ] RelayFeature.swift
- [ ] EmailAlias.swift (enums + struct + sealed secret w/ decodeIfPresent)
- [ ] AliasLifecycle.swift
- [ ] AliasAddress.swift
- [ ] EmailAliasRecord.swift
- [ ] tuist generate + make check compiles

## Success criteria
- Compiles (app + extension) via `make check`.
- (Tested in Phase 2 suite, but authored here) `EmailAliasSecret` decodes a legacy blob
  `{"personaId":"p","localPart":"x"}` → `tier=.perSite`, `status=.draft`, nil bindings.
- `AliasAddress.display` returns a string containing NO `@` for any (status, flag=false).
- `AliasLifecycle.canTransition(from:.reserved,to:.active,flag:false) == false`.

## Risks
| Risk | L×I | Mitigation |
|------|-----|------------|
| Legacy/partial sealed blob throws `keyNotFound` → alias vanishes | M×H | custom `init(from:)` + `decodeIfPresent`; backward-decode test (Phase 2) |
| `@domain` leaks into a pre-relay surface | L×H | single choke point `AliasAddress.display`; unit test asserts no `@` |
| localPart correlates sites | L×M | `randomLocalPart()` ignores domain/persona |

## Security
- Identity-bearing fields (`personaId`, `localPart`, bindings, `forwardingTarget`) are sealed;
  only sort/sync metadata is plaintext — matches the persona/folder "secrets sealed" contract.
- `nonisolated` so seal/JSON runs off-main.

## Next steps
Phase 2 wires these into `VaultStore`, `CloudSyncService`, and `VaultRepository`.
