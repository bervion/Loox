# Phase 2 — Write-back to profile / login

## Context
- Overview: [reldest-plan.md](reldest-plan.md) · Depends: [Phase 1](reldest-phase-01-destination-plumbing.md)
- Locked decision 2: after activation, write the alias back as a NEW `.email` field labeled
  "Private email" — persona-tier → profile card; per-site → bound login.

## Overview
- Priority: P1. Status: pending.
- Idempotent write-back so the activated alias is visible/usable on the right item.

## Key insights (verified)
- Full working address = `AliasAddress.display(localPart:status:.active, relayDomain: RelayConfig.emailDomain)` → `local@domain` — `AliasAddress.swift:11-15`, domain `RelayConfig.swift:18`.
- `fieldLabelText(label)` = `Text(LocalizedStringKey(label))` — `VaultComponents.swift:21-23`. So a stored English label "Private email" **localizes** IF added to the catalog. VI value must be added.
- `username(from:)` picks the FIRST `.email` field — `VaultRepository+PersonaContext.swift:15-20`. Real Email is field[1] in the identity template (`ItemCategory.swift:74`); appending "Private email" AFTER keeps the real email as the AutoFill/suggestion value on the profile card. On a LOGIN (no `.email` in template) the appended alias BECOMES the AutoFill email — the intended per-site behavior.
- `VaultRepository.update(_:)` re-seals + bumps `updatedAt` — `VaultRepository.swift:365`.
- `identityUsername(forPersona:)` currently seeds `forwardingTarget` at reserve time — `VaultRepository+AliasManagement.swift:19,34`. Phase 1 overwrites `forwardingTarget` with the real destination on activate; write-back is separate (writes the ALIAS address, not the destination).

## Requirements
- `attachAliasToProfile(_ alias, persona)`: upsert a `.email` field labeled "Private email" (value = full alias address) on `profileItem(for: persona)`. Append if absent; update value if present. Never touch the real Email field.
- `attachAliasToLogin(_ alias)`: upsert the same "Private email" `.email` field on `item(id: alias.boundItemId)` (the bound login).
- Both invoked from `RelayService.activate` AFTER `.active` is set (local, idempotent, non-fatal — a write-back failure must not un-live the alias).
- Route by tier: `.persona` → profile; `.perSite` → login.

## Architecture / data flow
```
activate(...) → (alias now .active) →
  switch alias.tier:
    .persona: repository.attachAliasToProfile(alias, persona)
    .perSite: repository.attachAliasToLogin(alias)      // item id = alias.boundItemId (persona's Space)
attach: item = target; addr = AliasAddress.display(.active)
        if let i = fields.firstIndex(label=="Private email", kind==.email): fields[i].value = addr
        else: fields.append(DynamicField(label:"Private email", kind:.email, value:addr))
        repository.update(item)                          // re-seal, bump updatedAt
```

## Related code files
Create:
- `Vaultify/Data/Repositories/VaultRepository+AliasWriteback.swift` — `attachAliasToProfile`, `attachAliasToLogin`, shared private `upsertPrivateEmail(on:address:)` (keeps files <200 LOC, clear ownership vs +AliasManagement).
Modify:
- `Vaultify/Services/Relay/RelayService.swift` — call write-back after `.active` (tier switch).
- `Vaultify/Localizable.xcstrings` — add "Private email" (EN source + VI, e.g. "Email riêng").
Read for context: `VaultItem.swift`, `DynamicField.swift`, `ItemCategory.swift` (identity template), `VaultRepository.swift` (`update`, `item(id:)` at +Folders.swift:235).

## Implementation steps
1. New file with `upsertPrivateEmail(on item: VaultItem, address: String)` returning mutated item; append-or-update by (`label=="Private email"`, `kind==.email`).
2. `attachAliasToProfile(_:persona:)`: guard `profileItem(for:persona)`; compute address; `update(upsertPrivateEmail(...))`.
3. `attachAliasToLogin(_:)`: guard `alias.boundItemId` + `item(id:)`; same upsert. (Login belongs to persona's Space — no INV-R03 breach.)
4. In `activate`, after `.active`, `try? attach…` per tier (non-fatal).
5. Add "Private email" to `Localizable.xcstrings` (EN + VI). `tuist generate` (new file) → `make check`.

## Todo
- [ ] `VaultRepository+AliasWriteback.swift` (upsert + two entry points)
- [ ] wire write-back into `activate` by tier
- [ ] "Private email" EN+VI catalog entry
- [ ] `tuist generate` + `make check`

## Success criteria
- Activating a persona alias appends exactly one "Private email" field to the profile card; re-activating updates it, never duplicates.
- Profile card's real Email remains field-first → `username(from:)`/suggestions still return the real email (verified by unit test).
- Activating a per-site alias writes "Private email" onto the bound login; that login's AutoFill email becomes the alias.
- "Private email" renders localized (VI) in item detail.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Write-back offers the alias as a suggestion (leak alias as username) | Med×Med | Append AFTER real Email so `first(.email)` = real; unit-test ordering |
| Duplicate "Private email" fields on repeat activate | Med×Low | Upsert by label+kind (idempotent) |
| Write-back failure un-lives alias | Low×High | Called after `.active`, `try?` non-fatal — backend state already correct |
| Per-site login has a pre-existing `.email` | Low×Low | Upsert matches label "Private email" specifically; leaves any other `.email` intact |

## Security
- Alias address is not a secret (`.email`, not protected). No cross-persona write: profile via `profileItem(for:)`, login via `alias.boundItemId` (Space-owned).

## Next
- P4 detail screen reads/derives these fields for display; P3 changes destination (not the written alias address).
