# Phase 1 — Destination plumbing + resumable activate

## Context
- Overview: [reldest-plan.md](reldest-plan.md) · Locked decisions: [proposal-v3-locked-decisions.md](proposal-v3-locked-decisions.md)
- Backend: `POST /v1/relay/aliases/{local-part}/destination`, body carries `destination`, 204 = ok.
  createAlias (kind=1) does NOT carry destination; rotateDestination (kind=3) does.

## Overview
- Priority: P1 (blocks all). Status: pending.
- Make `activate` a two-call flow (mint → set real email) that is **resumable** on partial failure,
  and add the per-persona destination resolver.

## Key insights (verified)
- `RelayService.send(kind:aliasID:path:method:genesis:)` builds `RelayCommand` WITHOUT destination — `RelayService.swift:80-90`.
- `RelayCommand.destination` + canonical `optionalString(cmd.destination)` already exist/frozen — `RelayCommand.swift:31`, `RelayCommandCanonical.swift:29`.
- `RelayAPIClient.body` already emits `destination` when set — `RelayAPIClient.swift:32`.
- `activate` retry loop re-mints local-part on `alias_exists` — `RelayService.swift:27-45`. **Failure mode:** if createAlias succeeds then rotateDestination fails, a naive retry hits `alias_exists` and re-mints, **orphaning** the first (placeholder-forwarding) alias on the backend. Must checkpoint the mint.
- `EmailAliasSecret` is a growable sealed struct (custom `Decodable`, `decodeIfPresent`) — `EmailAlias.swift:79-113`. Safe to add an optional marker.
- `profileItem(for:)` returns the persona's identity card (live-only, no cross-persona fallback) — `VaultRepository+PersonaContext.swift:27-32`. `username(from:)` picks first `.email` — `:15-20`.

## Requirements
- `destinationEmail(for persona:) -> String?` = the profile card's real `.email` value (excludes the
  "Private email" write-back field; nil if none/empty).
- `send` carries an optional `destination`.
- `activate` = createAlias (collision re-mint) → **checkpoint** minted → rotateDestination(destination)
  → `.active` + store `forwardingTarget = destination`. Resumable: a retry after a mint skips createAlias.
- Guard activate when persona has no destination email → typed `Failure.missingDestination` (UI surfaces "add an email first").
- `disable`/`delete` must hit the backend when the alias was minted OR active (not just active) — else a
  minted-but-reserved alias is deleted locally and orphaned.

## Architecture / data flow
```
UI activate(alias)
 → RelayService.activate(alias)
    resolve persona = repository.persona(id: alias.personaId)          // INV-R03: own persona only
    dest = repository.destinationEmail(for: persona) ?? throw .missingDestination
    if !alias.backendMinted:
        send(.createAlias, aliasID: localPart, genesis:true)           // retry re-mint on alias_exists
        repository: mark backendMinted=true (still .reserved)          // CHECKPOINT (sealed, bumps updatedAt)
    send(.rotateDestination, aliasID: localPart,
         path:"/v1/relay/aliases/\(localPart)/destination", destination: dest)
    repository.setAliasStatus(.active) + store forwardingTarget=dest   // after backend 204 only
```
- `backendMinted: Bool?` added to `EmailAlias` + `EmailAliasSecret` (growable decode default nil/false).

## Related code files
Modify:
- `Vaultify/Services/Relay/RelayService.swift` — `send` gains `destination:`; rewrite `activate`; fix `disable`/`delete` guard to `alias.backendMinted == true || status == .active`.
- `VaultifyCore/Models/EmailAlias.swift` — add `backendMinted: Bool?` to struct + secret + init + `decodeIfPresent`.
- `Vaultify/Data/Repositories/VaultRepository+Aliases.swift` — carry `backendMinted` through `decryptAlias`.
- `Vaultify/Data/Repositories/VaultRepository+AliasManagement.swift` — add `func markMinted(_ alias:)`; ensure `createPersona/PerSiteAlias` default `backendMinted=false`.
- `Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift` — add `destinationEmail(for:)`.
Read for context: `RelayCommand.swift`, `RelayCommandCanonical.swift`, `RelayAPIClient.swift`, `VaultRepository+Aliases.swift` (`personaAlias`), `VaultRepository+PersonaManagement.swift` (`persona(id:)` — verify accessor exists; else use `personas.first{$0.id==}`).

## Implementation steps
1. Add `backendMinted: Bool?` to `EmailAlias` + `EmailAliasSecret` (default `false` in inits, `decodeIfPresent(...) ?? false` in decode, mirror in `secret` + `decryptAlias`).
2. `destinationEmail(for:)`: `profileItem(for:)?.fields.first { $0.kind == .email && $0.label != "Private email" && !$0.value.isEmpty }?.value`.
3. `send(...)` gains `destination: String? = nil`; pass into `RelayCommand(...)`.
4. `markMinted(_:)` in +AliasManagement: set `backendMinted=true`, re-seal via `updateAlias`.
5. Rewrite `activate`: resolve persona+dest (throw `.missingDestination` if nil); createAlias-with-retry only if `!backendMinted`, then `markMinted`; then rotateDestination; then `.active` + `forwardingTarget`.
6. Add `Failure.missingDestination` to `RelayService.Failure`.
7. Guard `disable`/`delete` backend call on `backendMinted || active`.
8. `tuist generate --no-open` (EmailAlias field change is source-compatible; no new file) → `make check`.

## Todo
- [ ] `backendMinted` on model + secret + decode
- [ ] `destinationEmail(for:)`
- [ ] `send` destination param
- [ ] `markMinted` + resumable `activate`
- [ ] `Failure.missingDestination`
- [ ] disable/delete backend guard
- [ ] `make check` green

## Success criteria
- Fresh reserved alias with a valid persona email → activate performs both calls, ends `.active`, `forwardingTarget == real email`.
- rotateDestination failure after mint → alias stays `.reserved` with `backendMinted==true`; retry does NOT re-mint, resumes at rotateDestination.
- No persona email → `.missingDestination` thrown, no backend call, alias unchanged.
- Deleting a minted-but-reserved alias fires backend delete.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Orphan alias on mint-then-rotate failure | Med×Med | `backendMinted` checkpoint makes activate resumable (skip re-mint) |
| `backendMinted` field breaks old sealed blobs | Low×High | `decodeIfPresent ?? false` (proven growable pattern, EmailAlias.swift:103) |
| Repeated offline taps burn createAlias calls / rate-limit (429) | Med×Low | Checkpoint means ≥1 mint only; 429 already mapped to `.rejected("rate_limited")` |
| Wrong persona resolved (INV-R03) | Low×High | Resolve strictly by `alias.personaId`; never active-persona fallback |

## Security
- Destination (real email) rides only on kind=3 transcript (frozen); never logged. Genesis key still gates on epoch==1.
- No cross-persona read: `destinationEmail` uses `profileItem(for:)` (live, own-persona only).

## Next
- P2 consumes the now-active alias + address for write-back; P3 reuses `send(destination:)`.
